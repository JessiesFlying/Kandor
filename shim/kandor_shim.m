// SPDX-License-Identifier: GPL-3.0-only
// kandor_shim.m – wrapper around OCLP's Metal shim (impostor.dylib) for Vega and Navi eGPUs on macOS Tahoe
// Kandor (JessiesFlying, with assistance from Claude (Anthropic)) – macOS Tahoe
// Navi (AMDRadeonX6000MTLDriver) path: ne1rom, with assistance from Claude (Anthropic)
//
// Built and installed by kandor.sh vega-patch as the new impostor.dylib of the eGPU's Metal driver bundle
// (AMDRadeonX5000MTLDriver.bundle for Vega, AMDRadeonX6000MTLDriver.bundle for Navi). It
// re-exports Dortania's original, renamed to impostor_dortania.dylib, so the driver still gets every symbol of it
// and Dortania's constructor (GPU registration, its own swizzles) runs before ours. Then it
// (a) points the real_* pointers of all loaded shims back to Metal's own implementation (breaks the chain of the
//     D300 and Vega shims in one process), and
// (b) installs a dispatcher that gives the translated Monterey layout only to the D300 driver (Bronze) and the
//     native struct to everyone else, the Vega driver included (as in ne1rom's Navi wrapper).
// It also logs failing IOConnect calls to the Vega driver; the two user-client redirects themselves are done by
// Kryptonite 1.2.0 in the kernel (see the IOConnect section).
//
// Log: /Users/Shared/kandor-shim.log (kept across reboots; fallback /tmp/kandor-shim.log).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#include <os/log.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <execinfo.h>

// the tag read by kandor.sh status (earlier test builds had a logging-only mode 0 and userland redirects)
#define KANDOR_MODE 1
#define KANDOR_USER_REDIRECT 0

typedef void *(*acc_t)(id, SEL);
#define KANDOR_STR2(x) #x
#define KANDOR_STR(x) KANDOR_STR2(x)
__attribute__((used)) static const char kandor_mode_tag[] = "KANDOR_MODE=" KANDOR_STR(KANDOR_MODE) " KANDOR_USER_REDIRECT=" KANDOR_STR(KANDOR_USER_REDIRECT);   // read by kandor.sh (shim status)

// /Users/Shared survives a reboot (/tmp does not); one line per event, every line with process and pid
// also to the unified log, because sandboxed processes (WindowServer) cannot write the file:
//   log show --last 30m --predicate 'eventMessage CONTAINS "KANDOR "'
static void klog(const char *fmt, ...) {
    char buf[600]; va_list ap; va_start(ap, fmt); vsnprintf(buf, sizeof buf, fmt, ap); va_end(ap);
    os_log_error(OS_LOG_DEFAULT, "%{public}s", buf);
    FILE *f = fopen("/Users/Shared/kandor-shim.log", "a"); if (!f) f = fopen("/tmp/kandor-shim.log", "a"); if (!f) return;
    fprintf(f, "%s[%d] %s", getprogname(), getpid(), buf); fclose(f);
}

static const char *module_of(const void *addr) {
    Dl_info di; if (!addr || !dladdr(addr, &di) || !di.dli_fname) return "?";
    const char *p = strrchr(di.dli_fname, '/'); return p ? p + 1 : di.dli_fname;
}
static const char *symbol_of(const void *addr) {
    Dl_info di; if (!addr || !dladdr(addr, &di) || !di.dli_sname) return "?"; return di.dli_sname;
}
static int path_contains(const void *addr, const char *needle) {
    Dl_info di; return addr && dladdr(addr, &di) && di.dli_fname && strstr(di.dli_fname, needle);
}

// the five accessors (texture uses descriptorPrivate WITHOUT underscore)
typedef struct { const char *cls, *sel, *realsym, *tag; Class k; SEL s; acc_t prev, orig; int calls; } acc_rec;
static acc_rec R[] = {
    {"MTLRenderPipelineDescriptorInternal", "_descriptorPrivate", "real_MTLRenderPipelineDescriptorInternal__descriptorPrivate", "render"},
    {"MTLComputePipelineDescriptorInternal", "_descriptorPrivate", "real_MTLComputePipelineDescriptorInternal__descriptorPrivate", "compute"},
    {"MTLRenderPipelineColorAttachmentDescriptorInternal", "_descriptorPrivate", "real_MTLRenderPipelineColorAttachmentDescriptorInternal__descriptorPrivate", "colorattach"},
    {"MTLRenderPassDescriptorInternal", "_descriptorPrivate", "real_MTLRenderPassDescriptorInternal__descriptorPrivate", "renderpass"},
    {"MTLTextureDescriptorInternal", "descriptorPrivate", "real_MTLTextureDescriptorInternal_descriptorPrivate", "texture"},
};
#define NREC (int)(sizeof(R) / sizeof(R[0]))

// the shims that may be loaded in this process
static const char *SHIMS[] = {
    "/System/Library/Extensions/AMDRadeonX5000MTLDriver.bundle/Contents/MacOS/impostor_dortania.dylib",
    "/System/Library/Extensions/AMDRadeonX6000MTLDriver.bundle/Contents/MacOS/impostor_dortania.dylib",   // Navi
    "/System/Library/Extensions/AMDMTLBronzeDriver.bundle/Contents/MacOS/impostor.dylib",
};
#define NSHIM (int)(sizeof(SHIMS) / sizeof(SHIMS[0]))

static int from_d300_driver(const void *ret) { return path_contains(ret, "/AMDMTLBronzeDriver.bundle/Contents/MacOS/AMDMTLBronzeDriver"); }

static pthread_mutex_t lk = PTHREAD_MUTEX_INITIALIZER;
static void note_call(acc_rec *r, const void *ret, const char *route) {
    pthread_mutex_lock(&lk);
    if (r->calls < 12) {
        r->calls++;
        klog("KANDOR call %-11s #%d from %s (%s) -> %s\n", r->tag, r->calls, module_of(ret), symbol_of(ret), route);
    }
    pthread_mutex_unlock(&lk);
}

// one dispatcher per accessor, so the record is known without a lookup
#define DISPATCH(i) \
    static void *disp##i(id self, SEL c) { \
        const void *ret = __builtin_return_address(0); \
        if (from_d300_driver(ret)) { note_call(&R[i], ret, "translated (Dortania)"); \
            __attribute__((musttail)) return R[i].prev(self, c); } \
        note_call(&R[i], ret, "native"); \
        __attribute__((musttail)) return R[i].orig(self, c); }
DISPATCH(0) DISPATCH(1) DISPATCH(2) DISPATCH(3) DISPATCH(4)
static IMP DISP[] = {(IMP)disp0, (IMP)disp1, (IMP)disp2, (IMP)disp3, (IMP)disp4};

// ---- IOConnect watch ----------------------------------------------------------------------------------------------
// Tahoe removed ForceLegacyMode (0x102) from AMDRadeonX5000_AMDAccelSharedUserClient, so getIOSurfaceInfo moved
// from 0x103 to 0x102. OCLP installs the old kernel driver; a caller using Tahoe's numbering hits ForceLegacyMode
// (0 scalars) with 1 scalar and is rejected ("inputCount count mismatch 0x1 0x0"); likewise 0x105 with a 12-byte
// packet (old 0x106 RsrcAndXorByteFlag). Kryptonite 1.2.0 redirects both in the kernel; the wrapper only logs
// failing calls (kandor.sh status counts failing 0x102/0x105 calls since boot).
typedef kern_return_t (*iocm_t)(mach_port_t, uint32_t, const uint64_t *, uint32_t, const void *, size_t,
                                uint64_t *, uint32_t *, void *, size_t *);
typedef kern_return_t (*iocsc_t)(mach_port_t, uint32_t, const uint64_t *, uint32_t, uint64_t *, uint32_t *);
typedef kern_return_t (*iocst_t)(mach_port_t, uint32_t, const void *, size_t, void *, size_t *);
static iocm_t real_iocm; static iocsc_t real_iocsc; static iocst_t real_iocst;
static int io_seen[0x18]; static int io_hooked;

static void io_note(const char *api, uint32_t sel, uint32_t sel2, uint32_t inCnt, size_t inS, size_t outS, kern_return_t r, const void *ret) {
    if (sel < 0x100 || sel >= 0x118 || (r == KERN_SUCCESS && sel2 == sel)) return;
    int n = __sync_fetch_and_add(&io_seen[sel - 0x100], 1);
    if (n >= 6 && (n & (n - 1))) return;                       // first six, then powers of two
    char to[24] = ""; if (sel2 != sel) snprintf(to, sizeof to, " sent as 0x%x", sel2);
    klog("KANDOR ioconnect %s sel 0x%x%s in=%u inS=%zu outS=%zu -> 0x%x (#%d) from %s (%s)\n", api, sel,
         to, inCnt, inS, outS, r, n + 1, module_of(ret), symbol_of(ret));
    if (n < 2) {
        void *bt[12]; int k = backtrace(bt, 12);
        for (int i = 2; i < k; i++) klog("KANDOR ioconnect     #%d %s (%s)\n", i - 1, module_of(bt[i]), symbol_of(bt[i]));
    }
}
static kern_return_t kandor_iocm(mach_port_t c, uint32_t sel, const uint64_t *in, uint32_t inCnt, const void *inS, size_t inSCnt,
                              uint64_t *out, uint32_t *outCnt, void *outS, size_t *outSCnt) {
    kern_return_t r = real_iocm(c, sel, in, inCnt, inS, inSCnt, out, outCnt, outS, outSCnt);
    io_note("Method", sel, sel, inCnt, inSCnt, outSCnt ? *outSCnt : 0, r, __builtin_return_address(0));
    return r;
}
static kern_return_t kandor_iocsc(mach_port_t c, uint32_t sel, const uint64_t *in, uint32_t inCnt, uint64_t *out, uint32_t *outCnt) {
    kern_return_t r = real_iocsc(c, sel, in, inCnt, out, outCnt);
    io_note("Scalar", sel, sel, inCnt, 0, 0, r, __builtin_return_address(0));
    return r;
}
static kern_return_t kandor_iocst(mach_port_t c, uint32_t sel, const void *inS, size_t inSCnt, void *outS, size_t *outSCnt) {
    kern_return_t r = real_iocst(c, sel, inS, inSCnt, outS, outSCnt);
    io_note("Struct", sel, sel, 0, inSCnt, outSCnt ? *outSCnt : 0, r, __builtin_return_address(0));
    return r;
}
// point every image's GOT entry for the three calls at our wrappers (no logging here: runs under the dyld lock)
static void io_rebind(const struct mach_header *mh, intptr_t slide) {
    if (mh->magic != MH_MAGIC_64) return;
    const struct load_command *lc = (const struct load_command *)((const struct mach_header_64 *)mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++, lc = (const struct load_command *)((const char *)lc + lc->cmdsize)) {
        if (lc->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
        if (strncmp(seg->segname, "__DATA", 6) && strncmp(seg->segname, "__AUTH", 6)) continue;
        const struct section_64 *sec = (const struct section_64 *)(seg + 1);
        for (uint32_t j = 0; j < seg->nsects; j++) {
            uint32_t t = sec[j].flags & SECTION_TYPE;
            if (t != S_NON_LAZY_SYMBOL_POINTERS && t != S_LAZY_SYMBOL_POINTERS) continue;
            void **p = (void **)(uintptr_t)(sec[j].addr + slide); size_t n = sec[j].size / sizeof(void *);
            for (size_t k = 0; k < n; k++) {
                void *nw = p[k] == (void *)real_iocm ? (void *)kandor_iocm : p[k] == (void *)real_iocsc ? (void *)kandor_iocsc
                         : p[k] == (void *)real_iocst ? (void *)kandor_iocst : NULL;
                if (!nw) continue;
                vm_address_t pg = (vm_address_t)&p[k] & ~((vm_address_t)vm_page_size - 1);
                if (vm_protect(mach_task_self(), pg, vm_page_size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) == KERN_SUCCESS) {
                    p[k] = nw; __sync_fetch_and_add(&io_hooked, 1);
                }
            }
        }
    }
}
static void io_install(void) {
    real_iocm  = (iocm_t)dlsym(RTLD_DEFAULT, "IOConnectCallMethod");
    real_iocsc = (iocsc_t)dlsym(RTLD_DEFAULT, "IOConnectCallScalarMethod");
    real_iocst = (iocst_t)dlsym(RTLD_DEFAULT, "IOConnectCallStructMethod");
    if (!real_iocm || !real_iocsc || !real_iocst) { klog("KANDOR ioconnect: IOKit symbols not found – watch off\n"); return; }
    _dyld_register_func_for_add_image(io_rebind);             // runs for all loaded images now, and for later ones
    klog("KANDOR ioconnect watch installed (%d GOT entries, redirects left to Kryptonite)\n", io_hooked);
}

__attribute__((constructor)) static void kandor_init(void) {
    @autoreleasepool {
        klog("KANDOR ---- kandor_shim mode %d in %s (pid %d)\n", KANDOR_MODE, getprogname(), getpid());
        void *h[NSHIM];
        for (int j = 0; j < NSHIM; j++) {
            h[j] = dlopen(SHIMS[j], RTLD_NOLOAD | RTLD_LAZY);
            klog("KANDOR shim %s: %s\n", SHIMS[j], h[j] ? "loaded" : "not loaded");
        }
        for (int i = 0; i < NREC; i++) {
            acc_rec *r = &R[i];
            r->k = objc_getClass(r->cls); r->s = sel_registerName(r->sel);
            Method m = r->k ? class_getInstanceMethod(r->k, r->s) : NULL;
            if (!m) { klog("KANDOR %-11s: class or method missing – skipped\n", r->tag); continue; }
            r->prev = (acc_t)method_getImplementation(m);
            klog("KANDOR %-11s current IMP %p in %s (%s)\n", r->tag, (void *)r->prev, module_of((void *)r->prev), symbol_of((void *)r->prev));

            // where does each shim's real_* point? Metal = fine, a shim = chained
            for (int j = 0; j < NSHIM; j++) {
                if (!h[j]) continue;
                acc_t *slot = (acc_t *)dlsym(h[j], r->realsym);
                if (!slot) continue;
                acc_t v = *slot;
                klog("KANDOR %-11s   %s real_ -> %p in %s (%s)\n", r->tag, module_of(slot), (void *)v, module_of((void *)v), symbol_of((void *)v));
                if (v && path_contains((void *)v, "/Metal.framework/")) r->orig = v;
            }
            if (!r->orig) { klog("KANDOR %-11s: Metal's own IMP not found – left unchanged\n", r->tag); continue; }
            // break the chain: every shim's real_ now calls Metal directly
            for (int j = 0; j < NSHIM; j++) {
                if (!h[j]) continue;
                acc_t *slot = (acc_t *)dlsym(h[j], r->realsym);
                if (slot && *slot != r->orig) { klog("KANDOR %-11s   relinked %s real_ -> Metal\n", r->tag, module_of(slot)); *slot = r->orig; }
            }
            method_setImplementation(m, DISP[i]);
            klog("KANDOR %-11s dispatcher installed\n", r->tag);
        }
        io_install();
        klog("KANDOR ---- init done\n");
    }
}
