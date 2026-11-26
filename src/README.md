# Kryptonite source for Kandor

Kryptonite is GPL-3.0 (full text: `../LICENSE`). Upstream: https://github.com/mayankk2308/kryptonite
(the patches below apply to its `master` branch, commit `6e97e36`; files under `Kryptonite/Kryptonite/`).

Apply in this order:

| # | File | Author | What it does |
|---|---|---|---|
| 1 | `kandor-sequoia-24G720.patch` | ne1rom, with assistance from Claude (Anthropic) | Sequoia: new AppleGPUWrangler patch (`shr eax,0xc; and al,1` → `mov al,1`), IOPCIFamily `b5` variant, plugin range up to Sequoia |
| 2 | `kandor-tahoe-25G241.patch` | ne1rom, with assistance from Claude (Anthropic) | Tahoe: IOPCIFamily `b5` variant also for Tahoe, plugin range up to Tahoe |
| 3 | `kandor-sonoma-threshold.patch` | JessiesFlying, with assistance from Claude (Anthropic) | the newer AppleGPUWrangler patch from Sonoma on (`>= Sonoma` instead of `>= Sequoia`) |
| 4 | `kandor-amdsupport-agdc.patch` | JessiesFlying, with assistance from Claude (Anthropic) | the AMDSupport fix (enlarged AGDC structures, 5 find/replace pairs) in memory, kernel 22+; replaces the on-disk AMD driver patch of earlier versions. Off with `-krynoagdc` |
| 5 | `kandor-x5000-selectors.patch` | JessiesFlying, with assistance from Claude (Anthropic) | redirects the two user-client calls that OCLP's Tahoe Vega userland makes in Tahoe's numbering to the old `AMDRadeonX5000.kext` (0x102→0x103, 0x105→0x106), only when that old kext is loaded; kernel 22+. Off with `-krynoredirect` |
| 6 | `kandor-version-1.3.0.patch` | JessiesFlying, with assistance from Claude (Anthropic) | version 1.3.0 |
| 7 | `kandor-navi-agdc.patch` | ne1rom, with assistance from Claude (Anthropic) | the same AGDC fix for Navi: OCLP's Monterey `AMDRadeonX6000Framebuffer` 4.8.101 on Tahoe, 4 find/replace pairs in memory; kernel 25+ (Tahoe). Off with `-krynoagdc` |
| 8 | `kandor-navi-selectors.patch` | ne1rom, with assistance from Claude (Anthropic) | extends patch 5 to Navi: the same two user-client redirects for OCLP's old `AMDRadeonX6000.kext` on Tahoe (detected by its `ForceLegacyMode` symbol). Off with `-krynoredirect` |
| 9 | `kandor-navi-hold.patch` | ne1rom, with assistance from Claude (Anthropic) | on Tahoe without AVX2, holds Apple's own Navi driver off (its controller probes return no match) while OCLP's Navi framebuffer is not installed yet: the Mac starts on its built-in GPUs and OCLP's root patch offers "AMD Navi" (without it WindowServer aborts on every start). Off with `-krynonavihold` |

Build (Mac with Xcode, Apple Silicon or Intel):

```
bash src/build-kext.sh
```

It clones upstream, applies 1–9, fetches Lilu 1.7.2 (DEBUG, for headers and library) and acidanthera's MacKernelSDK,
builds for x86_64 and writes `src/out/Kryptonite-1.3.0.kext` with a log (the shipped copy is `../Kexts/Kryptonite-1.3.0.kext`). `src/build/` and `src/out/` are local only.

**1.3.0** (`../Kexts/Kryptonite-1.3.0.kext`, kernel 21–25, the build `kandor.sh efi` installs) is built from all
nine. The earlier 1.2.0 was built from 1–6 (no Navi).
