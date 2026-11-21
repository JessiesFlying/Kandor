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
#           sudo bash kandor.sh efi                install / update Kryptonite in the EFI
#  Tahoe only:
#           sudo bash kandor.sh vega-patch         build + install the Vega Metal shim wrapper (shim/kandor_shim.m)
#           sudo bash kandor.sh vega-patch-revert  put OCLP's original shim back
#
#  Only standard macOS tools are used (plutil, diskutil, perl, md5, kmutil, bless); vega-patch also needs the
#  Command Line Tools (xcode-select --install).
#  Every change asks for confirmation, makes a backup first and is logged to ./logs/ (read-only commands write no log).
# =============================================================================

KANDOR_VERSION="1.0.0"
KRY_VERSION="1.2.0"                # the one Kryptonite build of Kandor: kernel 21–25 (Monterey to Tahoe)
KRY_MAXKERNEL="25.99.99"; KRY_RANGE="Monterey to Tahoe"
SHIM_REL="System/Library/Extensions/AMDRadeonX5000MTLDriver.bundle/Contents/MacOS"   # OCLP's Vega Metal shim lives here
SHIM_LOG=/Users/Shared/kandor-shim.log
KRY_KEXT="Kryptonite-$KRY_VERSION.kext"
HERE="$(cd "$(dirname "$0")" && pwd)"
KEXTS="$HERE/Kexts"
BACKUP="$HERE/backup"            # backup/EFI/EFI-<date>, backup/Shim/<build>/ – local only
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
  [ "$(kernel_major)" = 25 ] && printf "  ${YEL}Tahoe:${R} menu 4–5, see README (Tahoe)\n"
  printf "  ${YEL}Supported for now:${R} MacPro6,1 only · ${B}AMD${R} eGPUs only (tested: RX Vega 56, RX 580)\n"
  printf "                     eGPU on a ${B}lower${R} Thunderbolt 2 port (the upper ports hang at boot)\n"
  printf "  ${YEL}Cold boot only:${R} eGPU attached and powered on ${B}before${R} the Mac starts. Never power it on,\n"
  printf "                  plug it in or unplug it while the Mac boots or runs.\n\n"
  printf "  ${D}OpenCore & Lilu by acidanthera · OCLP by Dortania\n"
  printf "  Kryptonite (GPL-3.0) by mayankk2308 & mac_editor\n"
  printf "  Sequoia/Tahoe fork by ne1rom\n"
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

  ${B}Kryptonite for macOS Sequoia and Tahoe${R}
  - ne1rom, with assistance from Claude (Anthropic)

  ${B}Kryptonite 1.2.0 and Kandor${R} (macOS Monterey to Tahoe)
  - JessiesFlying, with assistance from Claude (Anthropic), for:
     * adapting Kryptonite for macOS Ventura & Sonoma (one build for Monterey to Tahoe)
     * fixing OpenCore Legacy Patcher's AMD graphics driver (AMDSupport) for eGPU display output
     * the Tahoe user-client redirects and the Vega Metal shim wrapper
     * creating Kandor (this script and its documentation)

${B}Licenses${R}
  - OpenCore and Lilu: BSD-3-Clause. OCLP: BSD-4-Clause for its own files, its bundled
    components under their own licenses. None of them is included in Kandor.
  - Kryptonite: GPL-3.0. Kryptonite 1.2.0 in Kandor is built from the upstream source plus
    the patches in src/. Kandor's own files (kandor.sh, shim/, src/) are GPL-3.0 as well.
    Full license text: LICENSE; details: LICENSE-NOTES.md.
  - mayankk2308 made his own eGPU patches available for general use
    (dortania/OpenCore-Legacy-Patcher issue "eGPU patches", see LICENSE-NOTES.md).
EOF
}

# --------------------------------------------------------------- helpers ---
count_hex() { [ -f "$2" ] || { echo 0; return; }; perl -0777 -ne 'BEGIN{$p=pack("H*",shift @ARGV)} $n=()=/\Q$p\E/g; print $n+0' "$1" "$2" 2>/dev/null || echo 0; }
kernel_major() { uname -r | cut -d. -f1; }
os_name() { case "$(kernel_major)" in 21) echo Monterey;; 22) echo Ventura;; 23) echo Sonoma;; 24) echo Sequoia;; 25) echo Tahoe;; *) echo "kernel $(kernel_major)";; esac; }
pl() { plutil -extract "$1" raw -o - "$2" 2>/dev/null; }   # pl KEYPATH FILE -> value

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
  local model; model=$(sysctl -n hw.model 2>/dev/null)
  [ "$model" = "MacPro6,1" ] && ok "Mac: $model" || warn "Mac: $model (Kandor is made for MacPro6,1)"
  ok "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(os_name), kernel $(uname -r)"
  local ocv rpv; ocv=$(nvram "$OC_GUID:OCLP-Version" 2>/dev/null | cut -f2- | sed 's/%00//g')
  [ -n "$ocv" ] && ok "Booted through OpenCore built by OCLP $ocv" || warn "No OCLP-Version in NVRAM (not booted through an OCLP-built OpenCore?)"
  rpv=$(plutil -extract "OpenCore Legacy Patcher" raw /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist 2>/dev/null)
  if [ "$(kernel_major)" -ge 22 ]; then
    [ -n "$rpv" ] && ok "OCLP root patches installed ($rpv)" || bad "No OCLP root patches on this macOS: run OCLP → Post-Install Root Patch (with the eGPU attached)"
  else info "Monterey: no OCLP root patches needed"; fi
  local ba; ba=$(nvram boot-args 2>/dev/null | cut -f2-)
  case " $ba " in *" krygpu=AMD "*) ok "boot-args contain krygpu=AMD";; *) bad "boot-args lack krygpu=AMD (install Kryptonite into the EFI: menu 3)";; esac
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
  if [ -z "$dev" ]; then bad "No eGPU found (display@0). Box powered? Bottom Thunderbolt port? Kryptonite loaded?"
  else
    pci=$(echo "$node" | grep -m1 '"pcidebug"' | grep -oE '"[0-9]+:[0-9]+:[0-9]+' | tr -d '"')
    ok "eGPU found: $name  (PCI $pci)"
    if ioreg -r -n display@0 -d 2 -w0 2>/dev/null | grep -qE "class AMD[0-9]+Controller"; then ok "AMD driver attached to the eGPU"
    else bad "AMD driver not attached (System Information: driver installed = no) → Kryptonite patch missing or OCLP root patch missing"; fi
  fi
  # displaypolicyd keeps one log per GPU, named after its PCI address (the Vega's changes between boots/ports)
  local lf="/var/log/displaypolicy/displaypolicyd.$pci.log"; [ -n "$pci" ] && [ -f "$lf" ] || lf=""
  if [ -n "$lf" ] && [ -n "$dev" ]; then
    local last; last=$(grep -E "Do online device.*(completed|not completed)|To errorQ" "$lf" | tail -1)
    case "$last" in
      *"- completed"*) ok "Display policy: last 'online' attempt completed (picture expected)";;
      *errorQ*|*"not completed"*) bad "Display policy: last 'online' attempt failed → menu 2 (log)";;
      *) info "Display policy log: no online attempt yet ($(basename "$lf"))";;
    esac
  fi

  step "AMD driver (AMDSupport)"
  local am agdc=0; am=$(md5 -q "/$AMD_REL/Contents/MacOS/AMDSupport" 2>/dev/null)
  # Kryptonite 1.2.0 adapts OCLP's AMDSupport in memory on Ventura and later, unless -krynoagdc is set
  [ "$(kernel_major)" -ge 22 ] && [ "$kv" = "$KRY_VERSION" ] && case " $ba " in *" -krynoagdc "*) ;; *) agdc=1;; esac
  if [ -z "$am" ]; then info "No AMDSupport on the system volume"
  elif [ "$am" != "$AMD_MD5_TESTED" ]; then
    warn "AMDSupport is not OCLP's tested build (md5 $am): Kryptonite's display fix may not apply – an OCLP root patch puts OCLP's build back"
  elif [ "$(kernel_major)" -lt 22 ]; then ok "AMDSupport: OCLP's build, unchanged (Monterey needs no display fix)"
  elif [ "$agdc" = 1 ]; then ok "AMDSupport: OCLP's build; Kryptonite $kv adapts it in memory for the larger display structures"
  else bad "AMDSupport needs the eGPU display fix: Kryptonite $KRY_VERSION without -krynoagdc (menu 3)"; fi
  if [ "$(kernel_major)" = 25 ]; then
    step "Tahoe: Vega Metal shim and user-client redirects"
    shim_status
    local x5="/System/Library/Extensions/AMDRadeonX5000.kext/Contents/MacOS/AMDRadeonX5000" fails
    if [ "$kv" != "$KRY_VERSION" ]; then warn "Kryptonite $kv has no user-client redirects → menu 3 (efi)"
    elif [ ! -f "$x5" ]; then info "no AMDRadeonX5000.kext (Vega root patch missing?) – redirects not needed"
    elif ! grep -q ForceLegacyMode "$x5" 2>/dev/null; then info "Apple's own AMDRadeonX5000.kext: no redirects needed"
    else
      case " $ba " in *" -krynoredirect "*) warn "OCLP's older AMDRadeonX5000.kext, but the redirects are switched off (-krynoredirect)";;
      *) # the wrapper logs every failing call to the unified log; this boot only
         if [ -z "$dev" ]; then info "user-client redirects: checked only with the eGPU attached at boot"
         else
           local ul; ul=$(/usr/bin/log show --last boot --style compact --predicate 'eventMessage CONTAINS "KANDOR ioconnect"' 2>/dev/null)
           if ! echo "$ul" | grep -q "watch installed"; then warn "user-client redirects: the shim wrapper did not run in this boot → menu 4 (vega-patch)"
           else
             fails=$(echo "$ul" | grep -cE 'sel 0x10[25] in=.*-> 0xe')
             if [ "${fails:-0}" = 0 ]; then ok "user-client redirects working (OCLP's older AMDRadeonX5000.kext, no failing 0x102/0x105 calls in this boot)"
             else bad "$fails failing 0x102/0x105 calls in this boot → redirects not working, menu 2 (log)"; fi
           fi
         fi;;
      esac
    fi
  fi
  line
}

# ---------------------------------------------------------- Tahoe shim ---
# OCLP's Vega patchset on Tahoe brings its own Metal shim (impostor.dylib) next to the D300's; two shims in one
# process chain and Metal receives a wrongly translated struct. Kandor's wrapper (shim/kandor_shim.m) becomes the
# Vega bundle's impostor.dylib and re-exports OCLP's original, renamed impostor_dortania.dylib (see README, Tahoe).
need_tahoe() { [ "$(kernel_major)" = 25 ] || die "this is for macOS Tahoe only"; }
shim_is_ours() { grep -qa "impostor_dortania.dylib" "$1" 2>/dev/null; }   # every build of the wrapper re-exports the renamed original
shim_is_current() { grep -qa 'KANDOR_MODE=1 KANDOR_USER_REDIRECT=0' "$1" 2>/dev/null; }
kry_loaded() { kmutil showloaded --list-only 2>/dev/null | grep -i "io.egpu.Kryptonite" || kextstat 2>/dev/null | grep -i "io.egpu.Kryptonite"; }
shim_status() {
  local d="/$SHIM_REL" bk="$BACKUP/Shim/$(sw_vers -buildVersion)"
  if [ ! -f "$d/impostor.dylib" ]; then info "no Vega Metal shim (OCLP root patch with the Vega attached adds it)"; return; fi
  if shim_is_ours "$d/impostor.dylib"; then
    if shim_is_current "$d/impostor.dylib"; then ok "Kandor's shim wrapper installed (vega-patch)"
    else warn "an older build of the shim wrapper is installed → menu 4 (vega-patch) with the eGPU unplugged"; fi
    [ -f "$d/impostor_dortania.dylib" ] || bad "impostor_dortania.dylib missing next to the wrapper!"
  else warn "OCLP's original Vega shim installed: boot with the eGPU attached will hang → menu 4 (vega-patch)"; fi
  [ -f "$bk/impostor.dylib" ] && ok "backup of OCLP's shim for $(sw_vers -buildVersion): backup/Shim/" || info "no backup of OCLP's shim yet (vega-patch makes one)"
}
shim_snapshot() {
  bless --folder "$MNT/System/Library/CoreServices" --bootefi --create-snapshot >> "$LOG" 2>&1 || die "bless failed – do not reboot, send the log"
  ok "new boot snapshot created"; umount "$MNT" 2>/dev/null
}
do_vega_patch() { # [after-efi]: called by efi, which has just installed Kryptonite (not loaded before the reboot)
  need_tahoe
  local d="/$SHIM_REL" BD="$HERE/build/shim" src bk="$BACKUP/Shim/$(sw_vers -buildVersion)" kv
  step "Build the Vega shim wrapper"
  # order: menu 3 (efi) → reboot → OCLP root patch with the Vega attached → menu 4
  if [ "${1:-}" != after-efi ]; then
    kv=$(kry_loaded | grep -oE '\([0-9.]+\)' | head -1 | tr -d '()')
    [ "$kv" = "$KRY_VERSION" ] || die "Kryptonite $KRY_VERSION is not running${kv:+ (loaded: $kv)} – first menu 3 (efi), then reboot"
  fi
  [ -f /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist ] \
    || die "no OCLP root patches on this macOS – boot with the eGPU attached, OCLP → Post-Install Root Patch (\"AMD Vega\"), then menu 4"
  [ -f "$d/impostor.dylib" ] || die "OCLP's root patch has no Vega part (no impostor.dylib in the Vega Metal driver) –
  boot with the eGPU attached, OCLP → Post-Install Root Patch (it must offer \"AMD Vega\"), then menu 4"
  [ -f "$HERE/shim/kandor_shim.m" ] || die "missing shim/kandor_shim.m"
  xcrun --find clang >/dev/null 2>&1 || die "no Command Line Tools: run  xcode-select --install"
  src="$d/impostor.dylib"; shim_is_ours "$src" && src="$d/impostor_dortania.dylib"
  [ -f "$src" ] || die "OCLP's impostor.dylib not found"
  rm -rf "$BD"; mkdir -p "$BD"; cp "$src" "$BD/impostor_dortania.dylib"
  # its own install name must point to the renamed file, or the re-export would load the wrapper itself
  install_name_tool -id "/$SHIM_REL/impostor_dortania.dylib" "$BD/impostor_dortania.dylib" 2>>"$LOG" || die "install_name_tool failed"
  codesign -f -s - "$BD/impostor_dortania.dylib" >>"$LOG" 2>&1
  ( cd "$BD" && xcrun clang -arch x86_64 -dynamiclib -fno-objc-arc -O2 \
      -install_name "/$SHIM_REL/impostor.dylib" -Wl,-reexport_library,./impostor_dortania.dylib \
      -framework Foundation -Wno-deprecated-declarations -o impostor.dylib "$HERE/shim/kandor_shim.m" ) >>"$LOG" 2>&1 \
    || die "build failed (see the log; grep for 'error:')"
  codesign -f -s - -i impostor "$BD/impostor.dylib" >>"$LOG" 2>&1
  otool -L "$BD/impostor.dylib" 2>>"$LOG" | grep -q impostor_dortania || die "re-export of impostor_dortania.dylib missing in the build"
  ok "built ($(lipo -archs "$BD/impostor.dylib"))"
  ask "Install it into the Vega Metal driver (system volume, new boot snapshot)?" || die "cancelled by user"
  step "Install"
  mount_root
  local SD="$MNT/$SHIM_REL"
  if [ ! -f "$bk/impostor.dylib" ]; then
    mkdir -p "$bk"
    if shim_is_ours "$SD/impostor.dylib"; then cp -p "$SD/impostor_dortania.dylib" "$bk/impostor.dylib"; else cp -p "$SD/impostor.dylib" "$bk/impostor.dylib"; fi \
      || die "backup failed"
    ok "OCLP's original shim backed up to backup/Shim/$(sw_vers -buildVersion)/"
  fi
  cp "$BD/impostor_dortania.dylib" "$SD/impostor_dortania.dylib" && cp "$BD/impostor.dylib" "$SD/impostor.dylib" || die "copy failed"
  chown root:wheel "$SD/impostor.dylib" "$SD/impostor_dortania.dylib"; chmod 755 "$SD/impostor.dylib" "$SD/impostor_dortania.dylib"
  ok "installed: impostor.dylib (Kandor's wrapper) + impostor_dortania.dylib (OCLP's original)"
  touch "$SHIM_LOG" && chmod 666 "$SHIM_LOG" && echo "---- install vega-patch $(date)" >> "$SHIM_LOG"
  shim_snapshot
  printf "\n  ${GRN}${B}Done.${R} Shut down, attach the eGPU, boot. Afterwards: menu 1 (status); if something is wrong: menu 2 (log).\n"
}
do_vega_patch_revert() {
  need_tahoe
  local bk="$BACKUP/Shim/$(sw_vers -buildVersion)"
  step "Restore OCLP's Vega Metal shim"
  [ -f "$bk/impostor.dylib" ] || die "no backup for build $(sw_vers -buildVersion) in backup/Shim/ – use OCLP: Revert Root Patches, then Post-Install Root Patch"
  warn "with OCLP's original shim a boot with the eGPU attached hangs – unplug the eGPU first"
  ask "Restore it (system volume, new boot snapshot)?" || die "cancelled by user"
  mount_root
  local SD="$MNT/$SHIM_REL"
  cp -p "$bk/impostor.dylib" "$SD/impostor.dylib" && rm -f "$SD/impostor_dortania.dylib" || die "restore failed"
  chown root:wheel "$SD/impostor.dylib"; chmod 755 "$SD/impostor.dylib"
  ok "OCLP's original impostor.dylib restored"
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
  ls "$O"/*.log >/dev/null 2>&1 && ok "the last Kandor action logs (efi, vega-patch, …)"
  { echo "== sw_vers / kernel"; sw_vers; uname -a
    echo; echo "== boot-args"; nvram boot-args 2>/dev/null
    echo; echo "== loaded kexts (Kryptonite, Lilu, AMD, AGDC, GPU)"
    kmutil showloaded --list-only 2>/dev/null | grep -iE 'kryptonite|lilu|amd|radeon|agdc|graphicsdevice|gpuwrangler|ioaccel'
    echo; echo "== Kryptonite in /Library/Extensions? (should be none: OpenCore injects it)"; ls -d /Library/Extensions/Kryptonite* 2>/dev/null
    echo; echo "== AMD driver files (md5)"
    for f in /System/Library/Extensions/AMDSupport.kext/Contents/MacOS/AMDSupport \
             /System/Library/Extensions/AMDRadeonX5000.kext/Contents/MacOS/AMDRadeonX5000 \
             /System/Library/Extensions/AMDRadeonX4000.kext/Contents/MacOS/AMDRadeonX4000 \
             "/$SHIM_REL/impostor.dylib" "/$SHIM_REL/impostor_dortania.dylib"; do
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
    EFI_DEV=$(diskutil info -plist "$guid" 2>/dev/null | plutil -extract DeviceIdentifier raw - 2>/dev/null)
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
  parent=$(diskutil info -plist "$EFI_DEV" | plutil -extract ParentWholeDisk raw - 2>/dev/null)
  media=$(diskutil info "${parent:-$EFI_DEV}" | awk -F: '/Device \/ Media Name/{print $2}' | sed 's/^ *//; s/ *$//')
  info "Partition: /dev/$EFI_DEV ($size) on /dev/${parent:-?}${media:+, $media}"
  EFI_MP=$(diskutil info -plist "$EFI_DEV" | plutil -extract MountPoint raw - 2>/dev/null)
  if [ -z "$EFI_MP" ]; then
    ask "Mount /dev/$EFI_DEV now?" || die "EFI not mounted"
    diskutil mount "$EFI_DEV" >/dev/null || die "diskutil mount $EFI_DEV failed"
    EFI_MP=$(diskutil info -plist "$EFI_DEV" | plutil -extract MountPoint raw - 2>/dev/null)
    EFI_MOUNTED_BY_US=1
  fi
  ok "EFI mounted at $EFI_MP"
}

# config.plist is edited with plutil only (insert/remove/extract); indexed PlistBuddy edits on
# Kernel:Add have produced phantom entries that pass plutil -lint but stop OpenCore.
kext_count() { local i=0; while plutil -extract "Kernel.Add.$i" xml1 -o /dev/null "$1" 2>/dev/null; do i=$((i+1)); done; echo $i; }
# all BundlePaths in order (used to prove that nothing else changed)
kext_paths() { local i=0 n; n=$(kext_count "$1"); while [ $i -lt $n ]; do pl "Kernel.Add.$i.BundlePath" "$1"; i=$((i+1)); done; }
patch_count() { local i=0; while plutil -extract "Kernel.Patch.$i" xml1 -o /dev/null "$1" 2>/dev/null; do i=$((i+1)); done; echo $i; }
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
  # Tahoe's Vega shim wrapper needs library validation off; the patch only acts on kernel 25 (Tahoe), AMFI stays on
  local lv=remove t
  if [ "$(kernel_major)" = 25 ]; then lv=add; info "Tahoe is running → library-validation patch for Tahoe (for the Vega shim wrapper)"
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
  [ "${EFI_MOUNTED_BY_US:-0}" = 1 ] && ask "Unmount the EFI partition?" && diskutil unmount "$EFI_DEV" >/dev/null && ok "EFI unmounted"
  printf "\n\n  ${GRN}${B}Done.${R} The EFI change takes effect at the next boot.\n"
  # what comes next on this macOS
  if [ "$(kernel_major)" = 25 ]; then
    if [ ! -f "/$SHIM_REL/impostor.dylib" ]; then
      printf "  Next on Tahoe: shut down, attach the eGPU, boot (fine as long as OCLP's Vega part is not installed),\n"
      printf "  OCLP → Post-Install Root Patch (it must offer \"AMD Vega\"), then shut down, unplug the eGPU, boot\n"
      printf "  and run menu 4 (vega-patch).\n"
    elif shim_is_current "/$SHIM_REL/impostor.dylib"; then
      printf "  Kandor's Vega shim wrapper is already installed: shut down, attach the eGPU, boot.\n"
    else
      printf "\n  Tahoe also needs Kandor's Vega Metal shim wrapper (menu 4); no reboot needed in between.\n"
      if ask "Install it now?"; then do_vega_patch after-efi
      else printf "\n  Before booting with the eGPU attached: menu 4 (vega-patch).\n"; fi
    fi
  elif [ "$(kernel_major)" -ge 22 ] && [ ! -f /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist ]; then
    printf "  Next: reboot with the eGPU attached, then OCLP → Post-Install Root Patch.\n"
  else printf "  Reboot (eGPU attached), then menu 1 (status).\n"; fi
}

# ------------------------------------------------------- system volume ---
mount_root() {
  local dev
  dev=$(diskutil info -plist / | plutil -extract DeviceIdentifier raw -)
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
  vega-patch) with_log vega-patch do_vega_patch;;
  vega-patch-revert) with_log vega-patch-revert do_vega_patch_revert;;
  menu)
    while true; do
      printf "\n  ${B}0${R}  Show credits and licenses\n"
      printf "  ${B}1${R}  Show current status of your Mac regarding eGPU support\n"
      printf "  ${B}2${R}  Collect boot and error logs\n"
      printf "  ${B}3${R}  Install / update Kryptonite in the EFI\n"
      if [ "$(kernel_major)" = 25 ]; then
        printf "  ${B}4${R}  Install the Vega Metal shim wrapper (macOS 26 Tahoe only)\n"
        printf "  ${B}5${R}  Restore OCLP's Vega Metal shim (macOS 26 Tahoe only)\n"
      fi
      printf "  ${B}q${R}  Quit\n\n"
      c=$(choose "Choose")
      case "$c" in
        0) credits;; 1) do_status;; 2) ( do_log );; 3) with_log efi do_efi;; 4) with_log vega-patch do_vega_patch;; 5) with_log vega-patch-revert do_vega_patch_revert;;
        q|Q) break;; "") ;; *) warn "unknown choice";;
      esac
    done;;
  *) printf "\n"; warn "unknown command: $1"
     printf "\n  usage: sudo bash %s [command]   (no command: menu)\n" "$0"
     printf "    credits             credits and license\n"
     printf "    status              system status (read-only)\n"
     printf "    log                 collect the logs into logs/log-<date>/ (read-only)\n"
     printf "    efi                 install / update Kryptonite %s in the EFI\n" "$KRY_VERSION"
     printf "    vega-patch          install the Vega Metal shim wrapper (Tahoe)\n"
     printf "    vega-patch-revert   restore OCLP's Vega Metal shim (Tahoe)\n";;
esac
printf "\n"
