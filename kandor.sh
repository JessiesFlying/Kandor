#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# =============================================================================
#  Kandor – AMD eGPU for the Mac Pro (Late 2013) - kandor.sh  v1.0.0
#  AMD eGPU over Thunderbolt 2 on macOS Monterey to Tahoe (OpenCore Legacy Patcher)
#
#  Usage:   sudo bash kandor.sh                    interactive menu
#           sudo bash kandor.sh credits            credits and license
#           sudo bash kandor.sh status             system status (read-only)
#           sudo bash kandor.sh log                collect the logs into logs/log-<date>/ (read-only)
#           sudo bash kandor.sh efi                install / update Kandor in the EFI
#  Tahoe only:
#           sudo bash kandor.sh shim-patch         build + install the Metal shim wrapper (shim/kandor_shim.m) for
#                                                  Vega and Navi, into every AMD Metal driver where OCLP put its shim
#           sudo bash kandor.sh shim-patch-revert  put OCLP's original shims back
#
#  Only standard macOS tools are used (plutil, diskutil, perl, md5, kmutil, bless); shim-patch also needs the
#  Command Line Tools (xcode-select --install).
#  Every change asks for confirmation, makes a backup first and is logged to ./logs/ (read-only commands write no log).
# =============================================================================

KANDOR_VERSION="1.0.0"
KRY_VERSION="1.3.0"                # the one Kryptonite build of Kandor: kernel 21–25 (Monterey to Tahoe)
KRY_MAXKERNEL="25.99.99"; KRY_RANGE="Monterey to Tahoe"
# OCLP's Metal shims on Tahoe: Vega (AMDRadeonX5000MTLDriver) and Navi (AMDRadeonX6000MTLDriver). The wrapper is
# installed into every bundle that has one (the eGPU is unplugged then, so the card can't be detected); each copy is
# only loaded when its own driver is in use.
SHIM_BUNDLES="AMDRadeonX5000MTLDriver AMDRadeonX6000MTLDriver"
SHIM_LOG=/Users/Shared/kandor-shim.log
KRY_KEXT="Kryptonite-$KRY_VERSION.kext"
HERE="$(cd "$(dirname "$0")" && pwd)"
KEXTS="$HERE/Kexts"
BACKUP="$HERE/backup"            # backup/EFI/EFI-<date>, backup/Shim/<build>/<bundle>/ – local only
OC_GUID="4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102"
APPLE_GUID="7C436110-AB2A-4BBB-A880-FE41995C9F82"
MNT=/System/Volumes/Update/mnt1
AMD_REL="System/Library/Extensions/AMDSupport.kext"
AMD_MD5_TESTED="195fa14a0eac1953e97988dfc5b72a78"     # OCLP 2.4.1 / 2.5.1 / 3.0.0-rc.5 build of AMDSupport 4.0.8 (same on every macOS)
BOOTARGS_NEEDED="krygpu=AMD krytbtv=2"

# ------------------------------------------------------------------ output ---
if [ -t 1 ]; then
  B=$'\033[1m'; D=$'\033[2m'; R=$'\033[0m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'; CYN=$'\033[36m'
else B=""; D=""; R=""; RED=""; GRN=""; YEL=""; BLU=""; CYN=""; fi
ok()    { printf "  ${GRN}✓${R} %s\n" "$*"; }
warn()  { printf "  ${YEL}!${R} %s\n" "$*"; }
bad()   { printf "  ${RED}✗${R} %s\n" "$*"; }
info()  { printf "  ${BLU}·${R} %s\n" "$*"; }
step()  { printf "\n${B}${CYN}▸ %s${R}\n" "$*"; }
line()  { printf "${D}%s${R}\n" "────────────────────────────────────────────────────────────────────"; }
die()   { printf "\n  ${RED}${B}Stopped:${R} %s\n  Nothing else was changed.%s\n\n" "$*" "${LOG:+ Log: $LOG}"; exit 1; }
ask()   { # ask "question" -> 0 = yes
  local a; printf "\n  ${B}%s${R} [y/N] " "$1"; read -r a < /dev/tty; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }
choose() { # choose "prompt" [default] -> echo answer
  local a; if [ -n "${2:-}" ]; then printf "  ${B}%s${R} [%s] " "$1" "$2" >&2; else printf "  ${B}%s:${R} " "$1" >&2; fi
  read -r a < /dev/tty; echo "${a:-${2:-}}"; }

banner() {
  local rule="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "\n  ${B}${CYN}%s${R}\n" "$rule"
  printf "  ${B}Kandor %s${R}  ·  AMD eGPU for the Mac Pro (Late 2013)\n" "$KANDOR_VERSION"
  printf "  macOS Monterey – Tahoe with OpenCore Legacy Patcher\n"
  printf "  ${B}${CYN}%s${R}\n" "$rule"
  [ "$(kernel_major)" = 25 ] && printf "  ${YEL}Tahoe with Vega or Navi:${R} menu 4 after OCLP's root patch, before restarting (README, step 3a)\n"
  printf "  ${YEL}Supported for now:${R} MacPro6,1 only · ${B}AMD${R} eGPUs only (tested: RX Vega 56, RX 580, RX 6900 XT)\n"
  printf "                     eGPU on a ${B}lower${R} Thunderbolt 2 port (the upper ports hang at boot)\n"
  printf "  ${YEL}Cold boot only:${R} eGPU attached and powered on ${B}before${R} the Mac starts. Never power it on,\n"
  printf "                  plug it in or unplug it while the Mac boots or runs.\n\n"
  printf "  ${D}OpenCore & Lilu by acidanthera · OCLP by Dortania\n"
  printf "  Kryptonite (GPL-3.0) by mayankk2308 & mac_editor\n"
  printf "  Original concept, Kryptonite fork for Sequoia/Tahoe and Navi support on Tahoe by ne1rom\n"
  printf "  Ventura/Sonoma adaptation, AMD driver fix, Tahoe Vega support and Kandor by JessiesFlying${R}\n"
}

credits() {
  cat <<EOF

${B}Credits${R}
  ${B}OpenCore & OpenCore Legacy Patcher${R}
  - acidanthera and its contributors for OpenCore and Lilu
  - Dortania and its contributors for OpenCore Legacy Patcher (OCLP)

  ${B}Kryptonite${R} (original, release 1.0.2)
  - mayankk2308 & mac_editor for:
     * Thunderbolt patches for native eGFX support on macOS 10.13.4-10.15.1
     * Updated Thunderbolt patches for native eGFX support on macOS 10.15.1+
     * Bypass for Thunderbolt driver compatibility (IOPCITunnelCompatible) checks on macOS 10.13.4+
  - goalque for: support for NVIDIA eGFX on macOS 10.13.4+
  - rgov for: Ti82 Thunderbolt patches - adapted for Lilu by mac_editor

  ${B}Original concept and Kryptonite for macOS Sequoia and Tahoe${R}
  - ne1rom, with assistance from Claude (Anthropic)

  ${B}Navi on macOS Tahoe${R}
  - ne1rom, with assistance from Claude (Anthropic), for:
     * the display fix for OCLP's Navi framebuffer, the Navi user-client redirects and holding
       Apple's own Navi driver off until OCLP's Navi patch is installed (Kryptonite)
     * the Navi path in the Metal shim wrapper
     * Navi support in this script (shim-patch for Vega and Navi without unplugging the eGPU,
       Navi checks in status)

  ${B}Kryptonite for Ventura & Sonoma and Kandor${R} (macOS Monterey to Tahoe)
  - JessiesFlying, with assistance from Claude (Anthropic), for:
     * adapting Kryptonite for macOS Ventura & Sonoma (one build for Monterey to Tahoe)
     * fixing OpenCore Legacy Patcher's AMD graphics driver (AMDSupport) for eGPU display output
     * the Tahoe user-client redirects and the Vega Metal shim wrapper
     * creating Kandor (this script and its documentation)

${B}Licenses${R}
  - OpenCore and Lilu: BSD-3-Clause. OCLP: BSD-4-Clause for its own files, its bundled
    components under their own licenses. None of them is included in Kandor.
  - Kryptonite: GPL-3.0. Kryptonite $KRY_VERSION in Kandor is built from the upstream source plus
    the patches in src/. Kandor's own files (kandor.sh, shim/, src/) are GPL-3.0 as well.
    Full license text: LICENSE; details: LICENSE-NOTES.md.
  - mayankk2308 made his own eGPU patches available for general use
    (dortania/OpenCore-Legacy-Patcher issue "eGPU patches", see LICENSE-NOTES.md).
EOF
}

# --------------------------------------------------------------- helpers ---
count_hex() { [ -f "$2" ] || { echo 0; return; }; perl -0777 -ne 'BEGIN{$p=pack("H*",shift @ARGV)} $n=()=/\Q$p\E/g; print $n+0' "$1" "$2" 2>/dev/null || echo 0; }
kernel_major() { uname -r | cut -d. -f1; }
boot_epoch() { sysctl -n kern.boottime 2>/dev/null | sed -E 's/^\{ sec = ([0-9]+),.*/\1/'; }
# 0 = the system snapshot that boots next is not the running one: OCLP's root patch or menu 4 waits for a restart
restart_pending() {
  local cur sl i=0 r u
  cur=$(diskutil info -plist / 2>/dev/null | plutil -extract APFSSnapshotUUID raw -o - - 2>/dev/null) || return 1
  sl=$(diskutil apfs listSnapshots -plist / 2>/dev/null) || return 1
  while r=$(printf '%s' "$sl" | plutil -extract "Snapshots.$i.RootTo" raw -o - - 2>/dev/null); do
    if [ "$r" = true ]; then
      u=$(printf '%s' "$sl" | plutil -extract "Snapshots.$i.SnapshotUUID" raw -o - - 2>/dev/null)
      [ -n "$u" ] && [ "$u" != "$cur" ]; return
    fi
    i=$((i+1))
  done
  return 1
}
is_navi() { case "$1" in 731f|7340|73bf|73ff) return 0;; *) return 1;; esac; }   # Navi cards in Apple's drivers (device-id)
os_name() { case "$(kernel_major)" in 21) echo Monterey;; 22) echo Ventura;; 23) echo Sonoma;; 24) echo Sequoia;; 25) echo Tahoe;; *) echo "kernel $(kernel_major)";; esac; }
pl() { local v; v=$(plutil -extract "$1" raw -o - "$2" 2>/dev/null) || return 1; printf '%s\n' "$v"; }   # pl KEYPATH FILE -> value

need_root() { [ "$(id -u)" = 0 ] || { printf "\n  Please run with sudo:  ${B}sudo bash \"%s\"${R}\n\n" "$0"; exit 1; }; }

# AppleGPUWrangler: which GPUWrangler patch pattern exists -> old | new | both | none
gpuwrangler_style() {
  local g=/System/Library/Extensions/AppleGraphicsControl.kext/Contents/PlugIns/AppleGPUWrangler.kext/Contents/MacOS/AppleGPUWrangler o n
  [ -f "$g" ] || { echo unknown; return; }
  o=$(count_hex f8030f8278ffffff498b06c6807801 "$g"); n=$(count_hex c1e80c2401 "$g")
  if [ "$o" = 1 ] && [ "$n" = 1 ]; then echo both; elif [ "$o" = 1 ]; then echo old; elif [ "$n" = 1 ]; then echo new; else echo none; fi
}

# --------------------------------------------------------------- status ---
do_status() {
  step "System"
  local model pend=0; model=$(sysctl -n hw.model 2>/dev/null)
  restart_pending && pend=1
  [ "$model" = "MacPro6,1" ] && ok "Mac: $model" || warn "Mac: $model (Kandor is made for MacPro6,1)"
  ok "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(os_name), kernel $(uname -r)"
  local ocv rpv; ocv=$(nvram "$OC_GUID:OCLP-Version" 2>/dev/null | cut -f2- | sed 's/%00//g')
  [ -n "$ocv" ] && ok "Booted through OpenCore built by OCLP $ocv" || warn "No OCLP-Version in NVRAM (not booted through an OCLP-built OpenCore?)"
  rpv=$(pl "OpenCore Legacy Patcher" /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist)
  [ "$pend" = 1 ] && warn "A restart is pending: the system volume has changed (e.g. OCLP's root patch or menu 4); the lines
    below show the system as it runs now. Tahoe with a Vega or Navi card: menu 4 first if not done yet, then restart."
  if [ "$(kernel_major)" -ge 22 ]; then
    if [ -n "$rpv" ]; then ok "OCLP root patches installed ($rpv)"
    elif [ "$pend" = 1 ]; then info "OCLP root patches: not active until the restart"
    else bad "No OCLP root patches on this macOS: run OCLP → Post-Install Root Patch (with the eGPU attached)"; fi
  else info "Monterey: no OCLP root patches needed"; fi
  local ba; ba=$(nvram boot-args 2>/dev/null | cut -f2-)
  case " $ba " in *" krygpu=AMD "*) ok "boot-args contain krygpu=AMD";; *) bad "boot-args lack krygpu=AMD → menu 3 (efi)";; esac
  case " $ba " in *" amfi_get_out_of_my_way=1 "*) warn "AMFI is off (amfi_get_out_of_my_way=1) – not needed any more: menu 3 (efi) removes it";; *) ok "AMFI on";; esac

  step "Kryptonite"
  local kl; kl=$(kry_loaded)
  local kv; kv=$(echo "$kl" | grep -oE '\([0-9.]+\)' | head -1 | tr -d '()')
  if [ -z "$kl" ]; then bad "Kryptonite is not loaded → menu 3 (efi)"
  elif [ "$kv" = "$KRY_VERSION" ]; then ok "Kryptonite $kv loaded"
  else warn "Kryptonite $kv loaded, Kandor's build is $KRY_VERSION → menu 3 (efi), then reboot"; fi
  kmutil showloaded --list-only 2>/dev/null | grep -q "as.vit9696.Lilu" && ok "Lilu loaded" || warn "Lilu not listed as loaded"
  local gw; gw=$(gpuwrangler_style)
  # Kryptonite uses the older GPUWrangler pattern up to kernel 22 and the newer one from 23 on
  case "$(kernel_major)/$gw" in
    21/old|21/both|22/old|22/both|23/new|23/both|24/new|24/both|25/new|25/both) ok "AppleGPUWrangler matches the Kryptonite patch";;
    */unknown) info "AppleGPUWrangler is inside the kernel collection (no file to check): see the PlatformSupportsExternalGPUs line";;
    *) bad "AppleGPUWrangler: unexpected pattern ($gw) for kernel $(kernel_major) – the Kryptonite patch will not apply";;
  esac
  # the state itself (ne1rom): Kryptonite's GPUWrangler patch from kernel 23 on makes PlatformSupportsExternalGPUs true
  local pse kp; pse=$(ioreg -l -w0 2>/dev/null | grep -m1 '"PlatformSupportsExternalGPUs"' | sed -E 's/.*= *//')
  kp=$(ioreg -l -w0 2>/dev/null | grep -m1 -E '"Kryptonite" = ' | sed -E 's/.*= *//')
  [ -n "$kp" ] && info "ioreg: Kryptonite = $kp"
  case "$(kernel_major)/$pse" in
    2[3-9]/"<01>"|2[3-9]/Yes) ok "ioreg: PlatformSupportsExternalGPUs = $pse (Kryptonite's GPUWrangler patch is active)";;
    2[3-9]/"<00>"|2[3-9]/No)  bad "ioreg: PlatformSupportsExternalGPUs = $pse → Kryptonite's GPUWrangler patch did not apply";;
    2[3-9]/)                  info "ioreg: no PlatformSupportsExternalGPUs entry";;
    *)                        [ -n "$pse" ] && info "ioreg: PlatformSupportsExternalGPUs = $pse (not used for the check on this macOS)";;
  esac

  step "eGPU"
  local node dev name pci
  node=$(ioreg -r -n display@0 -d 1 -w0 -l 2>/dev/null)
  dev=$(echo "$node" | grep -m1 '"device-id"' | grep -oE '<[0-9a-f]+>' | cut -c2-5)
  dev=$(echo "$dev" | sed -E 's/(..)(..)/\2\1/')
  case "$dev" in
    687f) name="Radeon RX Vega 56/64 (Vega 10)";;           6863|6868) name="Radeon Vega Frontier / Pro WX 9100 (Vega 10)";;
    66af) name="Radeon VII (Vega 20)";;                      67df) name="Radeon RX 470/480/570/580/590 (Polaris)";;
    67ef|67ff) name="Radeon RX 460/560 (Polaris 11/21)";;     699f) name="Radeon RX 550 (Polaris 12)";;
    731f) name="Radeon RX 5600/5700 (XT) (Navi 10)";;        7340) name="Radeon RX 5500 (XT) (Navi 14)";;
    73bf) name="Radeon RX 6800/6800 XT/6900 XT (Navi 21)";;  73ff) name="Radeon RX 6600/6600 XT (Navi 23)";;
    73a5|73af|73ef) name="AMD GPU 1002:$dev (RX 6950 XT / 6900 XTXH / 6650 XT: not in Apple's drivers)";;
    "") name="";; *) name="AMD GPU 1002:$dev";;
  esac
  local ven; ven=$(echo "$node" | grep -m1 '"vendor-id"' | grep -oE '<[0-9a-f]+>' | cut -c2-5)
  [ -n "$ven" ] && [ "$ven" != "0210" ] && bad "eGPU vendor is not AMD (vendor-id $ven): Kandor supports AMD eGPUs only"
  # unplugged or "Disconnect"ed while running: macOS keeps a dead display@0 (inactive, same device-id) until a restart
  local gone=0; echo "$node" | grep -m1 -E '^\+-o display@0' | grep -q ' inactive' && gone=1
  if [ -z "$dev" ]; then bad "No eGPU found (display@0). Box powered? Bottom Thunderbolt port? Kryptonite loaded?"
  elif [ "$gone" = 1 ]; then
    bad "The eGPU was unplugged or disconnected while the Mac was running ($name). It can't come back until a restart:
    shut down, check that the eGPU is plugged in and on, then start the Mac."
  else
    pci=$(echo "$node" | grep -m1 '"pcidebug"' | grep -oE '"[0-9]+:[0-9]+:[0-9]+' | tr -d '"')
    ok "eGPU found: $name  (PCI $pci)"
    case "$(kernel_major)" in 22|23|24) is_navi "$dev" &&
        bad "Navi cards work on macOS Monterey and Tahoe only – not on Ventura, Sonoma or Sequoia (Apple's Navi drivers there need a newer CPU)";; esac
    # Polaris/Vega: AMD<n>Controller; Navi: AMDRadeonX6000_AmdRadeonController<chip>
    if ioreg -r -n display@0 -d 2 -w0 2>/dev/null | grep -qE "class (AMD[0-9]+Controller|AMDRadeonX[0-9]+_AmdRadeonController)"; then ok "AMD driver attached to the eGPU"
    elif [ "$(kernel_major)" = 25 ] && is_navi "$dev" && [ "$(count_hex 4881fa044000007562 /System/Library/Extensions/AMDRadeonX6000Framebuffer.kext/Contents/MacOS/AMDRadeonX6000Framebuffer)" = 0 ]; then
      if [ "$pend" = 1 ]; then info "no AMD driver attached yet: Kryptonite holds Apple's own Navi driver off until OCLP's Navi patch is active (after the restart)"
      else info "no AMD driver attached yet: Kryptonite holds Apple's own Navi driver off until OCLP's Navi patch is installed → OCLP → Post-Install Root Patch (\"AMD Navi\"), then menu 4 (shim-patch) before restarting"; fi
    else bad "AMD driver not attached (System Information: driver installed = no) → Kryptonite patch missing or OCLP root patch missing"; fi
  fi
  # displaypolicyd keeps one log per GPU, named after its PCI address (the Vega's changes between boots/ports)
  local lf="/var/log/displaypolicy/displaypolicyd.$pci.log"; [ -n "$pci" ] && [ -f "$lf" ] || lf=""
  if [ -n "$lf" ] && [ -n "$dev" ] && [ "$gone" = 0 ]; then
    local last lt; last=$(grep -E "Do online device.*(completed|not completed)|To errorQ" "$lf" | tail -1)
    # the log survives restarts: only an attempt of this boot counts
    lt=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(printf '%s' "$last" | cut -c1-19)" +%s 2>/dev/null)
    [ -n "$lt" ] && [ -n "$(boot_epoch)" ] && [ "$lt" -lt "$(boot_epoch)" ] && last="before-boot"
    case "$last" in
      before-boot) info "Display policy: no 'online' attempt in this boot yet ($(basename "$lf"))";;
      *"- completed"*) ok "Display policy: last 'online' attempt completed (picture expected)";;
      *errorQ*|*"not completed"*) bad "Display policy: last 'online' attempt failed → menu 2 (log)";;
      *) info "Display policy log: no online attempt yet ($(basename "$lf"))";;
    esac
  fi

  step "AMD driver (display fix)"
  local am agdc=0; am=$(md5 -q "/$AMD_REL/Contents/MacOS/AMDSupport" 2>/dev/null)
  # Kryptonite 1.2.0 and later adapt OCLP's AMDSupport in memory on Ventura and later, unless -krynoagdc is set
  [ "$(kernel_major)" -ge 22 ] && [ "$kv" = "$KRY_VERSION" ] && case " $ba " in *" -krynoagdc "*) ;; *) agdc=1;; esac
  if [ -z "$am" ]; then info "No AMDSupport on the system volume"
  elif [ "$(kernel_major)" -lt 22 ]; then ok "AMDSupport: Apple's own driver (Monterey needs no display fix)"
  elif [ "$am" != "$AMD_MD5_TESTED" ]; then warn "AMDSupport is not OCLP's tested build: run OCLP's root patch again"
  elif [ "$agdc" = 1 ]; then ok "AMDSupport: OCLP's build, display fix active"
  elif [ -n "$kv" ] && [ "$kv" != "$KRY_VERSION" ]; then warn "AMDSupport: OCLP's build; Kryptonite $kv is loaded instead of $KRY_VERSION → menu 3 (efi), then reboot"
  else bad "AMDSupport: display fix not active → menu 3 (efi)"; fi
  # Navi on Tahoe: Kryptonite's Navi display fix only matches OCLP's (Monterey) AMDRadeonX6000Framebuffer, each pattern once
  if [ "$(kernel_major)" = 25 ] && is_navi "$dev"; then
    local fb=/System/Library/Extensions/AMDRadeonX6000Framebuffer.kext/Contents/MacOS/AMDRadeonX6000Framebuffer h nf=0
    for h in 4881fa044000007562 83fb100f86bc000000 4881facc3d00007565 4881facc3d00000f85a5000000; do
      [ "$(count_hex "$h" "$fb")" = 1 ] && nf=$((nf+1))
    done
    case "$nf" in
      4) ok "AMDRadeonX6000Framebuffer: OCLP's Navi build, Kryptonite's Navi display fix matches";;
      0) if [ "$pend" = 1 ]; then info "AMDRadeonX6000Framebuffer: Apple's own until the restart"
         else bad "AMDRadeonX6000Framebuffer: not OCLP's Navi build → OCLP → Post-Install Root Patch (\"AMD Navi\") with the eGPU attached"; fi;;
      *) bad "AMDRadeonX6000Framebuffer: unknown build ($nf of 4 patterns) – the Navi display fix will not apply, menu 2 (log)";;
    esac
  fi
  if [ "$(kernel_major)" = 25 ]; then
    step "Tahoe: Metal shim wrapper and user-client redirects"
    shim_status "$pend"
    local k f olds="" fails
    # OCLP's older AMDRadeonX5000 (Vega) / AMDRadeonX6000 (Navi) still have ForceLegacyMode: those need the redirects
    for k in AMDRadeonX5000 AMDRadeonX6000; do
      f="/System/Library/Extensions/$k.kext/Contents/MacOS/$k"
      [ -f "$f" ] && grep -q ForceLegacyMode "$f" 2>/dev/null && olds="$olds $k.kext"
    done
    olds="${olds# }"
    if [ "$kv" != "$KRY_VERSION" ]; then warn "Kryptonite ${kv:-none}: Kandor's user-client redirects need $KRY_VERSION → menu 3 (efi)"
    elif [ -z "$olds" ]; then info "Apple's own AMDRadeonX5000/X6000 kexts (no OCLP Vega or Navi patch): no redirects needed"
    else
      case " $ba " in *" -krynoredirect "*) warn "OCLP's older $olds, but the redirects are switched off (-krynoredirect)";;
      *) # the wrapper logs every failing call to the unified log; this boot only
         if [ -z "$dev" ]; then info "user-client redirects: checked only with the eGPU attached at boot"
         else
           local ul; ul=$(/usr/bin/log show --last boot --style compact --predicate 'eventMessage CONTAINS "KANDOR ioconnect"' 2>/dev/null)
           if ! echo "$ul" | grep -q "watch installed"; then
             if [ "$pend" = 1 ]; then info "user-client redirects: the shim wrapper did not run in this boot (a restart is pending)"
             else warn "user-client redirects: the shim wrapper did not run in this boot → menu 4 (shim-patch)"; fi
           else
             fails=$(echo "$ul" | grep -cE 'sel 0x10[25] in=.*-> 0xe')
             if [ "${fails:-0}" = 0 ]; then ok "user-client redirects working (OCLP's older $olds, no failing 0x102/0x105 calls in this boot)"
             else bad "$fails failing 0x102/0x105 calls in this boot → redirects not working, menu 2 (log)"; fi
           fi
         fi;;
      esac
    fi
  fi
  line
}

# ---------------------------------------------------------- Tahoe shim ---
# OCLP's Vega and Navi patchsets on Tahoe bring their own Metal shim (impostor.dylib) next to the D300's; two shims in
# one process chain and Metal receives a wrongly translated struct. Kandor's wrapper (shim/kandor_shim.m) becomes the
# bundle's impostor.dylib and re-exports OCLP's original, renamed impostor_dortania.dylib (see README, Tahoe).
need_tahoe() { [ "$(kernel_major)" = 25 ] || die "this is for macOS Tahoe only"; }
shim_rel() { echo "System/Library/Extensions/$1.bundle/Contents/MacOS"; }          # shim_rel BUNDLE
shim_family() { case "$1" in *X5000*) echo Vega;; *X6000*) echo Navi;; *) echo "$1";; esac; }
# shim_targets [ROOT]: bundles with an OCLP shim, on the running system or (shim-patch, revert) on the mounted system
# volume that gets the new snapshot – before a reboot the two differ
shim_targets() { local b; for b in $SHIM_BUNDLES; do [ -f "${1:-}/$(shim_rel "$b")/impostor.dylib" ] && echo "$b"; done; }
die_umount() { umount "$MNT" 2>/dev/null; die "$@"; }
# backup/Shim/<build>/<bundle>/impostor.dylib; test builds before 1.3.0 kept the Vega one in backup/Shim/<build>/
shim_backup() {
  local n="$BACKUP/Shim/$(sw_vers -buildVersion)/$1/impostor.dylib" o="$BACKUP/Shim/$(sw_vers -buildVersion)/impostor.dylib"
  if [ ! -f "$n" ] && [ "$1" = AMDRadeonX5000MTLDriver ] && [ -f "$o" ]; then echo "$o"; else echo "$n"; fi
}
shim_is_ours() { grep -qa "impostor_dortania.dylib" "$1" 2>/dev/null; }   # every build of the wrapper re-exports the renamed original
shim_is_current() { grep -qa 'KANDOR_MODE=1 KANDOR_USER_REDIRECT=0' "$1" 2>/dev/null; }
shims_all_current() { local b t; t=$(shim_targets); [ -n "$t" ] || return 1
  for b in $t; do shim_is_current "/$(shim_rel "$b")/impostor.dylib" || return 1; done; }
kry_loaded() { kmutil showloaded --list-only 2>/dev/null | grep -i "io.egpu.Kryptonite" || kextstat 2>/dev/null | grep -i "io.egpu.Kryptonite"; }
shim_status() { # shim_status [1 = a restart is pending: the running system is not what boots next]
  local b d t targets pend="${1:-0}"; targets=$(shim_targets)
  if [ -z "$targets" ]; then
    if [ "$pend" = 1 ]; then info "no OCLP Metal shim for Vega or Navi in the running system yet (a restart is pending)"
    else info "no OCLP Metal shim for Vega or Navi (OCLP's root patch with the eGPU attached adds it)"; fi
    return
  fi
  for b in $targets; do
    d="/$(shim_rel "$b")"; t="$(shim_family "$b") ($b)"
    if shim_is_ours "$d/impostor.dylib"; then
      if shim_is_current "$d/impostor.dylib"; then ok "$t: Kandor's shim wrapper installed"
      elif [ "$pend" = 1 ]; then info "$t: an older build of the shim wrapper is running – menu 4 again if it was not done before this restart"
      else warn "$t: an older build of the shim wrapper → menu 4 (shim-patch)"; fi
      [ -f "$d/impostor_dortania.dylib" ] || bad "$t: impostor_dortania.dylib missing next to the wrapper!"
    elif [ "$pend" = 1 ]; then info "$t: OCLP's original shim in the running system – if menu 4 was done, the restart applies Kandor's wrapper"
    else warn "$t: OCLP's original shim installed: boot with the eGPU attached will hang → menu 4 (shim-patch)"; fi
    [ -f "$(shim_backup "$b")" ] && ok "$t: backup of OCLP's shim for $(sw_vers -buildVersion) in backup/Shim/" \
      || info "$t: no backup of OCLP's shim yet (shim-patch makes one)"
  done
}
shim_snapshot() {
  bless --folder "$MNT/System/Library/CoreServices" --bootefi --create-snapshot >> "$LOG" 2>&1 || die "bless failed – do not reboot, send the log"
  ok "new boot snapshot created"; umount "$MNT" 2>/dev/null
}
shim_build() { # shim_build BUNDLE: builds the wrapper for one bundle (from the mounted system volume) into build/shim/BUNDLE/
  local b="$1" rel src BD="$HERE/build/shim/$1"; rel=$(shim_rel "$b")
  src="$MNT/$rel/impostor.dylib"; shim_is_ours "$src" && src="$MNT/$rel/impostor_dortania.dylib"
  [ -f "$src" ] || die_umount "OCLP's impostor.dylib not found in $b"
  rm -rf "$BD"; mkdir -p "$BD"; cp "$src" "$BD/impostor_dortania.dylib"
  # its own install name must point to the renamed file, or the re-export would load the wrapper itself
  install_name_tool -id "/$rel/impostor_dortania.dylib" "$BD/impostor_dortania.dylib" 2>>"$LOG" || die_umount "install_name_tool failed ($b)"
  codesign -f -s - "$BD/impostor_dortania.dylib" >>"$LOG" 2>&1
  ( cd "$BD" && xcrun clang -arch x86_64 -dynamiclib -fno-objc-arc -O2 \
      -install_name "/$rel/impostor.dylib" -Wl,-reexport_library,./impostor_dortania.dylib \
      -framework Foundation -Wno-deprecated-declarations -o impostor.dylib "$HERE/shim/kandor_shim.m" ) >>"$LOG" 2>&1 \
    || die_umount "build failed for $b (see the log; grep for 'error:')"
  codesign -f -s - -i impostor "$BD/impostor.dylib" >>"$LOG" 2>&1
  otool -L "$BD/impostor.dylib" 2>>"$LOG" | grep -q "/$rel/impostor_dortania.dylib" || die_umount "re-export of impostor_dortania.dylib missing in the build ($b)"
  ok "built for $(shim_family "$b") ($b, $(lipo -archs "$BD/impostor.dylib"))"
}
do_shim_patch() { # [after-efi]: called by efi, which has just installed Kryptonite (not loaded before the reboot)
  need_tahoe
  local b targets bk SD kv
  step "Build the Metal shim wrapper"
  # order: menu 3 (efi) → boot with the eGPU attached → OCLP root patch → menu 4, before restarting (the eGPU stays attached)
  if [ "${1:-}" != after-efi ]; then
    kv=$(kry_loaded | grep -oE '\([0-9.]+\)' | head -1 | tr -d '()')
    [ "$kv" = "$KRY_VERSION" ] || die "Kryptonite $KRY_VERSION is not running${kv:+ (loaded: $kv)} – first menu 3 (efi), then reboot"
  fi
  [ -f "$HERE/shim/kandor_shim.m" ] || die "missing shim/kandor_shim.m"
  xcrun --find clang >/dev/null 2>&1 || die "no Command Line Tools: run  xcode-select --install"
  # the shims are read from and written to the system volume that gets the new snapshot: right after OCLP's root
  # patch (before the restart) that volume already has OCLP's files, the running system not yet
  mount_root
  [ -f "$MNT/System/Library/CoreServices/OpenCore-Legacy-Patcher.plist" ] \
    || die_umount "no OCLP root patches on this macOS – boot with the eGPU attached, OCLP → Post-Install Root Patch (\"AMD Vega\" or \"AMD Navi\"), then menu 4"
  targets=$(shim_targets "$MNT")
  [ -n "$targets" ] || die_umount "OCLP's root patch has no Vega or Navi part (no impostor.dylib in AMDRadeonX5000MTLDriver or AMDRadeonX6000MTLDriver) –
  boot with the eGPU attached, OCLP → Post-Install Root Patch (it must offer \"AMD Vega\" or \"AMD Navi\"), then menu 4"
  for b in $targets; do info "OCLP's shim found: $(shim_family "$b") ($b)"; done
  for b in $targets; do shim_build "$b"; done
  ask "Install the wrapper for $(for b in $targets; do printf '%s ' "$(shim_family "$b")"; done | sed 's/ $//; s/ / and /g') (system volume, new boot snapshot)?" || die_umount "cancelled by user"
  step "Install"
  for b in $targets; do
    SD="$MNT/$(shim_rel "$b")"; bk=$(shim_backup "$b")
    if [ ! -f "$bk" ]; then
      mkdir -p "$(dirname "$bk")"
      if shim_is_ours "$SD/impostor.dylib"; then
        # the original was replaced without a backup here: rebuild it from OCLP's copy next to the wrapper
        # (same code, install name set back to impostor.dylib, re-signed ad hoc – not byte-identical)
        cp "$SD/impostor_dortania.dylib" "$bk" && install_name_tool -id "/$(shim_rel "$b")/impostor.dylib" "$bk" 2>>"$LOG" \
          && codesign -f -s - -i impostor "$bk" >>"$LOG" 2>&1 || die "backup failed ($b)"
        warn "$(shim_family "$b"): no backup of OCLP's original shim existed – rebuilt one from the copy next to the wrapper (backup/Shim/$(sw_vers -buildVersion)/$b/)"
      else
        cp -p "$SD/impostor.dylib" "$bk" || die "backup failed ($b)"
        ok "$(shim_family "$b"): OCLP's original shim backed up to backup/Shim/$(sw_vers -buildVersion)/$b/"
      fi
    fi
    cp "$HERE/build/shim/$b/impostor_dortania.dylib" "$SD/impostor_dortania.dylib" && cp "$HERE/build/shim/$b/impostor.dylib" "$SD/impostor.dylib" \
      || die "copy failed ($b)"
    chown root:wheel "$SD/impostor.dylib" "$SD/impostor_dortania.dylib"; chmod 755 "$SD/impostor.dylib" "$SD/impostor_dortania.dylib"
    ok "$(shim_family "$b"): installed impostor.dylib (Kandor's wrapper) + impostor_dortania.dylib (OCLP's original)"
  done
  touch "$SHIM_LOG" && chmod 666 "$SHIM_LOG" && echo "---- install shim-patch ($(echo $targets)) $(date)" >> "$SHIM_LOG"
  shim_snapshot
  if ioreg -r -n display@0 -d 1 2>/dev/null | grep 'IOPCIDevice' | grep -qv ' inactive'; then
    printf "\n  ${GRN}${B}Done.${R} Restart (the eGPU stays attached). Afterwards: menu 1 (status); if something is wrong: menu 2 (log).\n"
  else
    printf "\n  ${GRN}${B}Done.${R} Shut down, attach the eGPU, boot. Afterwards: menu 1 (status); if something is wrong: menu 2 (log).\n"
  fi
}
do_shim_patch_revert() {
  need_tahoe
  local b bk SD todo="" targets
  step "Restore OCLP's Metal shims"
  mount_root   # check and change the system volume that gets the new snapshot (differs from the running one before a reboot)
  targets=$(shim_targets "$MNT")
  for b in $targets; do
    shim_is_ours "$MNT/$(shim_rel "$b")/impostor.dylib" || { info "$(shim_family "$b"): OCLP's original shim already in place"; continue; }
    bk=$(shim_backup "$b")
    if [ -f "$bk" ]; then todo="$todo $b"
    else warn "$(shim_family "$b"): no backup for build $(sw_vers -buildVersion) – use OCLP: Revert Root Patches, then Post-Install Root Patch"; fi
  done
  [ -n "$todo" ] || die_umount "nothing to restore"
  warn "with OCLP's original shim a boot with the eGPU attached hangs – unplug the eGPU first"
  ask "Restore OCLP's shim for$(for b in $todo; do printf ' %s' "$(shim_family "$b")"; done) (system volume, new boot snapshot)?" || die_umount "cancelled by user"
  for b in $todo; do
    SD="$MNT/$(shim_rel "$b")"
    cp -p "$(shim_backup "$b")" "$SD/impostor.dylib" && rm -f "$SD/impostor_dortania.dylib" || die "restore failed ($b)"
    chown root:wheel "$SD/impostor.dylib"; chmod 755 "$SD/impostor.dylib"
    ok "$(shim_family "$b"): OCLP's original impostor.dylib restored"
  done
  shim_snapshot
  printf "\n  ${GRN}${B}Done.${R} Reboot (without the eGPU).\n"
}
do_log() { # read-only: everything needed to diagnose the eGPU, on every macOS
  local O="$HERE/logs/log-$(date +%Y%m%d-%H%M%S)" ref="$HERE/logs/.last-log" f
  mkdir -p "$O"
  # crash reports since the last log run; on the first run those of the last 24 hours
  [ -f "$ref" ] || touch -t "$(date -v-1d +%Y%m%d%H%M)" "$ref"
  step "Collect the logs into logs/$(basename "$O")/"
  ( do_status ) 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$O/status.txt" && ok "status (status.txt)"
  for f in $(ls -t "$HERE"/logs/*.log 2>/dev/null | head -5); do cp "$f" "$O/"; done
  ls "$O"/*.log >/dev/null 2>&1 && ok "the last Kandor action logs (efi, shim-patch, …)"
  { echo "== sw_vers / kernel"; sw_vers; uname -a
    echo; echo "== boot-args"; nvram boot-args 2>/dev/null
    echo; echo "== loaded kexts (Kryptonite, Lilu, AMD, AGDC, GPU)"
    kmutil showloaded --list-only 2>/dev/null | grep -iE 'kryptonite|lilu|amd|radeon|agdc|graphicsdevice|gpuwrangler|ioaccel'
    echo; echo "== Kryptonite in /Library/Extensions? (should be none: OpenCore injects it)"; ls -d /Library/Extensions/Kryptonite* 2>/dev/null
    echo; echo "== AMD driver files (md5)"
    for f in /System/Library/Extensions/AMDSupport.kext/Contents/MacOS/AMDSupport \
             /System/Library/Extensions/AMDRadeonX5000.kext/Contents/MacOS/AMDRadeonX5000 \
             /System/Library/Extensions/AMDRadeonX4000.kext/Contents/MacOS/AMDRadeonX4000 \
             /System/Library/Extensions/AMDRadeonX6000.kext/Contents/MacOS/AMDRadeonX6000 \
             /System/Library/Extensions/AMDRadeonX6000Framebuffer.kext/Contents/MacOS/AMDRadeonX6000Framebuffer \
             $(for b in $SHIM_BUNDLES; do echo "/$(shim_rel "$b")/impostor.dylib /$(shim_rel "$b")/impostor_dortania.dylib"; done); do
      [ -f "$f" ] && echo "$(md5 -q "$f")  $f"; done
    echo "AMDSupport tested OCLP build: $AMD_MD5_TESTED; GPUWrangler pattern: $(gpuwrangler_style)"
    echo; echo "== OCLP root patch record"; plutil -p /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist 2>/dev/null | head -60
    echo; echo "== displays (system_profiler)"; system_profiler SPDisplaysDataType 2>/dev/null
    echo; echo "== eGPU in the I/O registry (display@0)"; ioreg -r -n display@0 -d 3 -w0 2>/dev/null | grep -E '\+-o|"(model|device-id|AAPL,slot-name|ATY,EFIVersion)"'
    echo; echo "== Thunderbolt"; system_profiler SPThunderboltDataType 2>/dev/null | grep -E 'Vendor Name|Device Name|Speed|Status|Port' | head -30
  } > "$O/info.txt" 2>&1; ok "system info (info.txt: versions, loaded kexts, driver md5s, displays, Thunderbolt)"
  /usr/bin/log show --last 2h --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "AMD" OR eventMessage CONTAINS[c] "Radeon" OR eventMessage CONTAINS[c] "GPU" OR eventMessage CONTAINS[c] "IOAccel" OR eventMessage CONTAINS[c] "AGDC" OR eventMessage CONTAINS[c] "Kryptonite" OR eventMessage CONTAINS[c] "framebuffer" OR eventMessage CONTAINS "Library Validation")' \
    > "$O/kernel-gpu.log" 2>/dev/null && ok "kernel GPU messages ($(wc -l < "$O/kernel-gpu.log" | tr -d ' ') lines)"
  for f in $(ls -t /var/log/displaypolicy/displaypolicyd.*.log 2>/dev/null | head -3); do cp "$f" "$O/"; done
  ls "$O"/displaypolicyd.* >/dev/null 2>&1 && ok "display policy logs (the three newest: one per GPU / PCI address)"
  /usr/bin/log show --last 2h --style compact --predicate 'process == "WindowServer" AND (messageType == error OR messageType == fault)' \
    > "$O/windowserver-errors.log" 2>/dev/null && ok "WindowServer errors ($(wc -l < "$O/windowserver-errors.log" | tr -d ' ') lines)"
  if [ "$(kernel_major)" = 25 ]; then
    [ -f "$SHIM_LOG" ] && cp "$SHIM_LOG" "$O/kandor-shim.log" && ok "kandor-shim.log ($(wc -l < "$SHIM_LOG" | tr -d ' ') lines)"
    [ -f /tmp/kandor-shim.log ] && cp /tmp/kandor-shim.log "$O/kandor-shim-tmp.log" && ok "kandor-shim-tmp.log ($(wc -l < /tmp/kandor-shim.log | tr -d ' ') lines)"
    # sandboxed processes (WindowServer) only reach the unified log
    /usr/bin/log show --last 2h --style compact --predicate 'eventMessage CONTAINS "KANDOR "' > "$O/kandor-unified.log" 2>/dev/null && ok "shim wrapper messages from the unified log"
  fi
  for f in /Library/Logs/DiagnosticReports/WindowServer*.ips /Library/Logs/DiagnosticReports/*.panic /Library/Logs/DiagnosticReports/panic*.ips /Users/*/Library/Logs/DiagnosticReports/*.ips; do
    [ -f "$f" ] && [ "$f" -nt "$ref" ] && cp "$f" "$O/" && warn "crash report: $(basename "$f")"
  done
  touch "$ref"
  ls /Library/Logs/DiagnosticReports/*.panic /Library/Logs/DiagnosticReports/panic*.ips >/dev/null 2>&1 || ok "no kernel panic reports on this Mac"
  printf "\n  ${GRN}${B}Done.${R} Logs in %s\n" "$O"
}

# ------------------------------------------------------------------ EFI ---
find_efi() { # sets EFI_DEV, EFI_MP
  EFI_DEV=""; EFI_MP=""
  local bp guid
  bp=$(nvram "$OC_GUID:boot-path" 2>/dev/null | cut -f2-)
  guid=$(echo "$bp" | grep -oE 'GPT,[0-9A-Fa-f-]{36}' | cut -d, -f2)
  if [ -n "$guid" ]; then
    EFI_DEV=$(diskutil info -plist "$guid" 2>/dev/null | plutil -extract DeviceIdentifier raw -o - - 2>/dev/null) || EFI_DEV=""
    [ -n "$EFI_DEV" ] && info "OpenCore booted from partition $guid → /dev/$EFI_DEV"
  fi
  if [ -z "$EFI_DEV" ]; then
    warn "Could not read the boot partition from NVRAM. EFI partitions on this Mac:"
    diskutil list | grep -E "EFI " | awk '{print "      " $NF "   " $0}' | sed 's/  */ /g'
    EFI_DEV=$(choose "Which one holds OpenCore? (e.g. disk0s1)" "disk0s1")
  fi
  diskutil info "$EFI_DEV" >/dev/null 2>&1 || die "/dev/$EFI_DEV does not exist"
  local size parent media
  size=$(diskutil info "$EFI_DEV" | awk -F: '/Disk Size/{print $2}' | cut -d'(' -f1 | sed 's/^ *//; s/ *$//')
  parent=$(diskutil info -plist "$EFI_DEV" | plutil -extract ParentWholeDisk raw -o - - 2>/dev/null) || parent=""
  media=$(diskutil info "${parent:-$EFI_DEV}" | awk -F: '/Device \/ Media Name/{print $2}' | sed 's/^ *//; s/ *$//')
  info "Partition: /dev/$EFI_DEV ($size) on /dev/${parent:-?}${media:+, $media}"
  EFI_MP=$(diskutil info -plist "$EFI_DEV" | plutil -extract MountPoint raw -o - - 2>/dev/null) || EFI_MP=""
  if [ -z "$EFI_MP" ]; then
    ask "Mount /dev/$EFI_DEV now?" || die "EFI not mounted"
    diskutil mount "$EFI_DEV" >/dev/null || die "diskutil mount $EFI_DEV failed"
    EFI_MP=$(diskutil info -plist "$EFI_DEV" | plutil -extract MountPoint raw -o - - 2>/dev/null) || EFI_MP=""
    EFI_MOUNTED_BY_US=1
  fi
  ok "EFI mounted at $EFI_MP"
}

# config.plist is edited with plutil only (insert/remove/extract); indexed PlistBuddy edits on
# Kernel:Add have produced phantom entries that pass plutil -lint but stop OpenCore.
kext_count() { local i=0; while plutil -extract "Kernel.Add.$i" xml1 -o - "$1" >/dev/null 2>&1; do i=$((i+1)); done; echo $i; }
# all BundlePaths in order (used to prove that nothing else changed)
kext_paths() { local i=0 n; n=$(kext_count "$1"); while [ $i -lt $n ]; do pl "Kernel.Add.$i.BundlePath" "$1"; i=$((i+1)); done; }
patch_count() { local i=0; while plutil -extract "Kernel.Patch.$i" xml1 -o - "$1" >/dev/null 2>&1; do i=$((i+1)); done; echo $i; }
patch_comments() { local i=0 n; n=$(patch_count "$1"); while [ $i -lt $n ]; do echo "$i|$(pl "Kernel.Patch.$i.Comment" "$1")"; i=$((i+1)); done; }
# OCLP's own "Disable Library Validation Enforcement" kernel patch (payloads/Config/config.plist: _cs_require_lv -> return 0),
# limited to Tahoe: lets WindowServer load the ad-hoc signed shim wrapper with AMFI on (instead of amfi_get_out_of_my_way=1)
LV_COMMENT="Kandor: Disable Library Validation Enforcement (OCLP patch, Tahoe shim)"
LV_RE="[^|]*: Disable Library Validation Enforcement \(OCLP patch, Tahoe shim\)$"   # marks Kandor's own copy in config.plist (efi finds and replaces it); OCLP's own entry has no prefix
LV_XML="<dict><key>Arch</key><string>x86_64</string><key>Base</key><string>_cs_require_lv</string><key>Comment</key><string>$LV_COMMENT</string><key>Count</key><integer>0</integer><key>Enabled</key><true/><key>Find</key><data></data><key>Identifier</key><string>kernel</string><key>Limit</key><integer>0</integer><key>Mask</key><data></data><key>MaxKernel</key><string></string><key>MinKernel</key><string>25.0.0</string><key>Replace</key><data>uAAAAADD</data><key>ReplaceMask</key><data></data><key>Skip</key><integer>0</integer></dict>"
# Kryptonite entries "index|BundlePath|MinKernel|MaxKernel|Enabled"
kry_entries() {
  local cfg="$1" i=0 n bp; n=$(kext_count "$cfg")
  while [ $i -lt $n ]; do
    bp=$(pl "Kernel.Add.$i.BundlePath" "$cfg")
    case "$bp" in Kryptonite*) echo "$i|$bp|$(pl "Kernel.Add.$i.MinKernel" "$cfg")|$(pl "Kernel.Add.$i.MaxKernel" "$cfg")|$(pl "Kernel.Add.$i.Enabled" "$cfg")";; esac
    i=$((i+1))
  done
}
add_entry() { # cfg bundle min max comment
  local cfg="$1" n
  plutil -insert Kernel.Add -json "{\"Arch\":\"x86_64\",\"BundlePath\":\"$2\",\"Comment\":\"$5\",\"Enabled\":true,\"ExecutablePath\":\"Contents/MacOS/Kryptonite\",\"MaxKernel\":\"$4\",\"MinKernel\":\"$3\",\"PlistPath\":\"Contents/Info.plist\"}" -append "$cfg" || die "plutil could not add $2"
  n=$(( $(kext_count "$cfg") - 1 ))
  [ "$(pl "Kernel.Add.$n.BundlePath" "$cfg")" = "$2" ] && [ "$(pl "Kernel.Add.$n.MinKernel" "$cfg")" = "$3" ] \
    && [ "$(pl "Kernel.Add.$n.MaxKernel" "$cfg")" = "$4" ] && [ "$(pl "Kernel.Add.$n.Enabled" "$cfg")" = "true" ] \
    || die "verification of the new entry $2 failed"
}

do_efi() {
  step "Find the OpenCore EFI partition"
  find_efi
  local OC="$EFI_MP/EFI/OC" CFG
  CFG="$OC/config.plist"
  [ -f "$CFG" ] && [ -f "$OC/OpenCore.efi" ] || die "No OpenCore at $OC"
  local model ver; model=$(pl "NVRAM.Add.$OC_GUID.OCLP-Model" "$CFG"); ver=$(pl "NVRAM.Add.$OC_GUID.OCLP-Version" "$CFG")
  [ "$model" = "MacPro6,1" ] || die "config.plist is not an OCLP build for MacPro6,1 (OCLP-Model: '${model:-none}')"
  kext_paths "$CFG" | grep -qx "Lilu.kext" || die "Lilu.kext is not in this config (Kryptonite needs Lilu)"
  ok "OpenCore config built by OCLP $ver for $model, Lilu present"

  step "Current Kryptonite setup in this EFI"
  local cur; cur=$(kry_entries "$CFG")
  if [ -n "$cur" ]; then echo "$cur" | while IFS='|' read -r i bp mn mx en; do info "$bp  kernel ${mn:-any} – ${mx:-any}  enabled=$en"; done
  else info "none (fresh OCLP config)"; fi

  local plan="$KRY_KEXT|21.0.0|$KRY_MAXKERNEL|Kryptonite $KRY_VERSION: $KRY_RANGE"
  [ -d "$KEXTS/$KRY_KEXT" ] || die "$KRY_KEXT not found in Kexts/"
  info "using $KEXTS/$KRY_KEXT"

  step "Planned changes"
  [ -n "$cur" ] && info "remove all current Kryptonite entries and Kryptonite*.kext folders from EFI/OC/Kexts"
  echo "$plan" | while IFS='|' read -r k mn mx c; do info "add $k  for kernel $mn – $mx"; done
  info "boot-args: make sure '$BOOTARGS_NEEDED' is present"
  # Tahoe's shim wrapper needs library validation off; the patch only acts on kernel 25 (Tahoe), AMFI stays on
  local lv=remove t
  if [ "$(kernel_major)" = 25 ]; then lv=add; info "Tahoe is running → library-validation patch for Tahoe (for the shim wrapper)"
  elif patch_comments "$CFG" | grep -qE "^[0-9]*\|$LV_RE"; then lv=add; info "keep the library-validation patch for Tahoe (already in this EFI)"
  else
    for t in /Volumes/*/System/Library/CoreServices/SystemVersion.plist; do
      case "$(pl ProductVersion "$t")" in 26.*) lv=add; info "Tahoe found on $(echo "$t" | cut -d/ -f3) → library-validation patch for Tahoe";; esac
    done
    [ "$lv" = add ] || { ask "Is (or will) macOS Tahoe be installed on this Mac? (adds the library-validation patch, acts on Tahoe only)" && lv=add; }
  fi
  [ "$lv" = add ] && info "add kernel patch: Disable Library Validation Enforcement (OCLP's patch, Tahoe only)"
  info "backup of the whole EFI folder first → backup/EFI/"
  ask "Apply these changes to $CFG?" || die "cancelled by user"

  step "Applying"
  local bk="$BACKUP/EFI/EFI-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP/EFI" && cp -R "$EFI_MP/EFI" "$bk" || die "backup failed"
  ok "EFI backed up to $bk"
  local idx others_before others_after n_before nk
  others_before=$(kext_paths "$CFG" | grep -v '^Kryptonite'); n_before=$(kext_count "$CFG"); nk=$(kry_entries "$CFG" | wc -l | tr -d ' ')
  for idx in $(kry_entries "$CFG" | cut -d'|' -f1 | sort -rn); do plutil -remove "Kernel.Add.$idx" "$CFG" || die "could not remove entry $idx"; done
  [ "$(kext_count "$CFG")" = $((n_before - nk)) ] || { cp "$bk/OC/config.plist" "$CFG"; die "entry count wrong after removing; restored the backup"; }
  # Kandor's library-validation patch: remove any old copy, add it again if needed
  local p_others_before p_n_before p_nk
  p_others_before=$(patch_comments "$CFG" | cut -d'|' -f2- | grep -vE "^$LV_RE"); p_n_before=$(patch_count "$CFG")
  p_nk=$(patch_comments "$CFG" | cut -d'|' -f2- | grep -cE "^$LV_RE")
  for idx in $(patch_comments "$CFG" | grep -E "^[0-9]*\|$LV_RE" | cut -d'|' -f1 | sort -rn); do plutil -remove "Kernel.Patch.$idx" "$CFG" || die "could not remove kernel patch $idx"; done
  if [ "$lv" = add ]; then
    plutil -insert Kernel.Patch -xml "$LV_XML" -append "$CFG" || { cp "$bk/OC/config.plist" "$CFG"; die "plutil could not add the library-validation patch; restored the backup"; }
    [ "$(pl "Kernel.Patch.$(( $(patch_count "$CFG") - 1 )).Base" "$CFG")" = _cs_require_lv ] || { cp "$bk/OC/config.plist" "$CFG"; die "library-validation patch not where expected; restored the backup"; }
    ok "added kernel patch: library validation off on Tahoe (OCLP's _cs_require_lv patch)"
  elif [ "$p_nk" != 0 ]; then info "removed Kandor's library-validation patch"; fi
  [ "$(patch_count "$CFG")" = $(( p_n_before - p_nk + $([ "$lv" = add ] && echo 1 || echo 0) )) ] \
    && [ "$(patch_comments "$CFG" | cut -d'|' -f2- | grep -vE "^$LV_RE")" = "$p_others_before" ] \
    || { cp "$bk/OC/config.plist" "$CFG"; die "kernel patch list changed unexpectedly; restored the backup"; }
  rm -rf "$OC"/Kexts/Kryptonite*.kext
  while IFS='|' read -r k mn mx c; do
    cp -R "$KEXTS/$k" "$OC/Kexts/" || die "could not copy $k"
    add_entry "$CFG" "$k" "$mn" "$mx" "$c"; ok "added $k ($mn – $mx)"
  done <<< "$plan"
  local ba a
  ba=$(pl "NVRAM.Add.$APPLE_GUID.boot-args" "$CFG")
  for a in $BOOTARGS_NEEDED; do case " $ba " in *" $a "*) ;; *) ba="$ba $a";; esac; done
  case " $ba " in *" amfi_get_out_of_my_way=1 "*) ba=$(echo " $ba " | sed 's/ amfi_get_out_of_my_way=1 / /'); info "removed amfi_get_out_of_my_way=1 (AMFI is on again)";; esac
  ba=$(echo "$ba" | sed 's/^ *//; s/ *$//')
  plutil -replace "NVRAM.Add.$APPLE_GUID.boot-args" -string "$ba" "$CFG" || die "could not set boot-args"
  ok "boot-args: $ba"
  plutil -lint "$CFG" >/dev/null || { cp "$bk/OC/config.plist" "$CFG"; die "config.plist failed validation; restored the backup"; }
  others_after=$(kext_paths "$CFG" | grep -v '^Kryptonite')
  [ "$others_before" = "$others_after" ] || { cp "$bk/OC/config.plist" "$CFG"; die "other kext entries changed unexpectedly; restored the backup"; }
  [ "$(kext_count "$CFG")" = $((n_before - nk + 1)) ] || { cp "$bk/OC/config.plist" "$CFG"; die "entry count wrong; restored the backup"; }
  ok "config.plist is valid, $(kext_count "$CFG") kext entries, $(patch_count "$CFG") kernel patches, all other entries unchanged"

  step "Result"
  kry_entries "$CFG" | while IFS='|' read -r i bp mn mx en; do ok "$bp  kernel $mn – $mx"; done
  # unmount what efi mounted itself (no question); a partition that was already mounted stays as it was
  if [ "${EFI_MOUNTED_BY_US:-0}" = 1 ]; then
    if diskutil unmount "$EFI_DEV" >/dev/null 2>&1; then ok "EFI unmounted"
    else info "EFI still mounted (in use, e.g. by Spotlight) – harmless, it is unmounted at the next restart"; fi
  fi
  printf "\n\n  ${GRN}${B}Done.${R} The EFI change takes effect at the next boot.\n"
  # what comes next on this macOS
  if [ "$(kernel_major)" = 25 ]; then
    if [ -z "$(shim_targets)" ]; then
      printf "  Next on Tahoe: shut down, attach the eGPU (Navi: also a monitor on the Mac's HDMI port – the Navi card shows\n"
      printf "  no picture until the end of this), boot, OCLP → Post-Install Root Patch (it must offer \"AMD Vega\" or\n"
      printf "  \"AMD Navi\"), don't restart yet: menu 4 (shim-patch), then restart.\n"
    elif shims_all_current; then
      if ioreg -r -n display@0 -d 1 2>/dev/null | grep 'IOPCIDevice' | grep -qv ' inactive'; then
        printf "  Kandor's shim wrapper is already installed: restart (the eGPU stays attached).\n"
      else printf "  Kandor's shim wrapper is already installed: shut down, attach the eGPU, boot.\n"; fi
    else
      printf "\n  Tahoe also needs Kandor's Metal shim wrapper (menu 4); no reboot needed in between.\n"
      if ask "Install it now?"; then do_shim_patch after-efi
      else printf "\n  Before booting with the eGPU attached: menu 4 (shim-patch).\n"; fi
    fi
  elif [ "$(kernel_major)" -ge 22 ] && [ ! -f /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist ]; then
    printf "  Next: reboot with the eGPU attached, then OCLP → Post-Install Root Patch.\n"
  else printf "  Reboot (eGPU attached), then menu 1 (status).\n"; fi
}

# ------------------------------------------------------- system volume ---
mount_root() {
  local dev
  dev=$(diskutil info -plist / | plutil -extract DeviceIdentifier raw -o - - 2>/dev/null) || dev=""
  echo "$dev" | grep -qE '^disk[0-9]+s[0-9]+s[0-9]+$' && dev="${dev%s*}"   # booted snapshot -> its volume
  if [ ! -f "$MNT/System/Library/CoreServices/SystemVersion.plist" ]; then
    mount -o nobrowse -t apfs "/dev/$dev" "$MNT" || die "could not mount the system volume /dev/$dev"
  fi
  ok "system volume /dev/$dev mounted at $MNT"
}
# ----------------------------------------------------------------- main ---
need_root
mkdir -p "$HERE/logs"
LOG=""
# with_log NAME CMD...: runs an action that changes something in a subshell, with its screen output copied
# (without colours) to logs/<date>-NAME.log; read-only actions write no log
with_log() {
  local name="$1"; shift
  ( LOG="$HERE/logs/$(date +%Y%m%d-%H%M%S)-$name.log"
    banner | sed 's/\x1b\[[0-9;]*m//g' > "$LOG"
    exec > >(tee >(sed -l 's/\x1b\[[0-9;]*m//g' >> "$LOG")) 2>&1
    "$@"
    printf "\n  ${D}Log: %s${R}\n" "$LOG" )
  sleep 0.3   # let the log copy finish before the menu is printed again
}
banner
case "${1:-menu}" in
  credits) credits;;
  status) do_status;;
  log) do_log;;
  efi) with_log efi do_efi;;
  shim-patch) with_log shim-patch do_shim_patch;;
  shim-patch-revert) with_log shim-patch-revert do_shim_patch_revert;;
  menu)
    while true; do
      printf "\n  ${B}0${R}  Show credits and licenses\n"
      printf "  ${B}1${R}  Show the status (checks everything, changes nothing)\n"
      printf "  ${B}2${R}  Collect error logs\n"
      printf "  ${B}3${R}  Install / update Kandor in the EFI\n"
      if [ "$(kernel_major)" = 25 ]; then
        printf "  ${B}4${R}  macOS Tahoe: install the graphics fix (Vega and Navi)\n"
        printf "  ${B}5${R}  macOS Tahoe: uninstall the graphics fix (Vega and Navi)\n"
      fi
      printf "  ${B}q${R}  Quit\n\n"
      c=$(choose "Choose")
      case "$c" in
        0) credits;; 1) do_status;; 2) ( do_log );; 3) with_log efi do_efi;; 4) with_log shim-patch do_shim_patch;; 5) with_log shim-patch-revert do_shim_patch_revert;;
        q|Q) break;; "") ;; *) warn "unknown choice";;
      esac
    done;;
  *) printf "\n"; warn "unknown command: $1"
     printf "\n  usage: sudo bash %s [command]   (no command: menu)\n" "$0"
     printf "    credits             show credits and licenses\n"
     printf "    status              show the status (checks everything, changes nothing)\n"
     printf "    log                 collect error logs\n"
     printf "    efi                 install / update Kandor in the EFI\n"
     printf "    shim-patch          macOS Tahoe: install the graphics fix (Vega and Navi)\n"
     printf "    shim-patch-revert   macOS Tahoe: uninstall the graphics fix (Vega and Navi)\n";;
esac
printf "\n"
