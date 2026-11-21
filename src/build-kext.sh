#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# build-kext.sh – build Kandor's Kryptonite from upstream source + the patches in this folder
# Kandor (JessiesFlying, with assistance from Claude (Anthropic))
#
#   bash src/build-kext.sh          on a Mac with Xcode (Apple Silicon or Intel); no sudo
#
# Clones mayankk2308/kryptonite at the tested commit, applies patches 1–6 (see README.md), fetches Lilu
# (DEBUG build, for its headers and library) and acidanthera's MacKernelSDK, builds with xcodebuild for x86_64
# and writes  src/out/Kryptonite-<version>.kext  plus a build log. Nothing outside src/build and src/out is touched.

set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM=https://github.com/mayankk2308/kryptonite.git
UPSTREAM_COMMIT=6e97e36            # upstream master the patches were made against
LILU_VERSION=1.7.2                 # the Lilu that OCLP 3.0.0-rc.5 installs
LILU_ZIP="https://github.com/acidanthera/Lilu/releases/download/$LILU_VERSION/Lilu-$LILU_VERSION-DEBUG.zip"
SDK=https://github.com/acidanthera/MacKernelSDK.git
PATCHES="kandor-sequoia-24G720.patch kandor-tahoe-25G241.patch kandor-sonoma-threshold.patch
kandor-amdsupport-agdc.patch kandor-x5000-selectors.patch kandor-version-1.2.0.patch"

B="$HERE/build"; OUT="$HERE/out"; LOG="$OUT/build-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$OUT"
say() { printf "  %s\n" "$*" | tee -a "$LOG"; }
die() { printf "\n  Stopped: %s\n  Log: %s\n\n" "$*" "$LOG"; exit 1; }

command -v xcodebuild >/dev/null && xcodebuild -version >/dev/null 2>&1 || die "Xcode not found (xcode-select -s /Applications/Xcode.app)"
for p in $PATCHES; do [ -f "$HERE/$p" ] || die "missing $p"; done
say "Xcode: $(xcodebuild -version | head -1)"

rm -rf "$B"; mkdir -p "$B"
say "cloning upstream Kryptonite ($UPSTREAM_COMMIT)"
git clone -q "$UPSTREAM" "$B/kryptonite" >>"$LOG" 2>&1 && git -C "$B/kryptonite" checkout -q "$UPSTREAM_COMMIT" >>"$LOG" 2>&1 || die "git clone/checkout failed"
for p in $PATCHES; do
  git -C "$B/kryptonite" apply --whitespace=nowarn "$HERE/$p" >>"$LOG" 2>&1 || die "patch did not apply: $p"
  say "applied $p"
done

P="$B/kryptonite/Kryptonite"          # Xcode project dir: expects Lilu.kext and MacKernelSDK/ here
say "fetching Lilu $LILU_VERSION (DEBUG) and MacKernelSDK"
curl -fsSL -o "$B/lilu.zip" "$LILU_ZIP" >>"$LOG" 2>&1 || die "download failed: $LILU_ZIP"
ditto -x -k "$B/lilu.zip" "$B/lilu" >>"$LOG" 2>&1 || die "unzip of Lilu failed"
LK=$(find "$B/lilu" -maxdepth 3 -name Lilu.kext -type d | head -1)
[ -n "$LK" ] && [ -d "$LK/Contents/Resources/Headers" ] || die "Lilu.kext with Contents/Resources/Headers not found in the zip"
cp -R "$LK" "$P/Lilu.kext"
git clone -q --depth 1 "$SDK" "$P/MacKernelSDK" >>"$LOG" 2>&1 || die "MacKernelSDK clone failed"

say "building (Release, x86_64, deployment target 12.0 = Monterey, the oldest macOS of Kandor)"
# upstream's project says 10.13.4; current Xcode only accepts 12.0 and later
xcodebuild -project "$P/Kryptonite.xcodeproj" -configuration Release ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=12.0 \
  SYMROOT="$B/xcbuild" CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build >>"$LOG" 2>&1 \
  || { grep -E 'error:' "$LOG" | head -20; die "xcodebuild failed (errors above, full output in the log)"; }
K=$(find "$B/xcbuild" -name Kryptonite.kext -type d -path '*Release*' | head -1)
[ -n "$K" ] || die "Kryptonite.kext not found after the build"
V=$(plutil -extract CFBundleShortVersionString raw "$K/Contents/Info.plist")
lipo -archs "$K/Contents/MacOS/Kryptonite" | grep -q x86_64 || die "the build has no x86_64 slice"
rm -rf "$OUT/Kryptonite-$V.kext"; cp -R "$K" "$OUT/Kryptonite-$V.kext"
say "built: $OUT/Kryptonite-$V.kext"
say "  version $V, binary md5 $(md5 -q "$OUT/Kryptonite-$V.kext/Contents/MacOS/Kryptonite")"
say "  contains: $(strings "$OUT/Kryptonite-$V.kext/Contents/MacOS/Kryptonite" | grep -cE 'krynoagdc|krynoredirect|ForceLegacyModeEv|IOAccelSharedUserClient2') Kandor markers (expect 4)"
echo
echo "  Log: $LOG"
