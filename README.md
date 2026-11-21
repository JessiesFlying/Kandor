# Kandor 1.0.0 – AMD eGPU for the Mac Pro (Late 2013, "trash can")

Named after the Kryptonian city in a bottle from the Superman stories – a whole world in a cylinder, like this
Mac – and a companion to Kryptonite, the eGPU kext it is built on.

**Scope:** MacPro6,1 · AMD eGPUs, tested: RX Vega 56 (Vega) and RX 580 (Polaris) · eGPU on a **lower**
Thunderbolt 2 port · macOS Monterey, Ventura, Sonoma, Sequoia, Tahoe with OpenCore Legacy Patcher 2.5.1 or
3.0.0-rc.5 (Tahoe: 3.0.0-rc.5, section below).

**Cold boot only.** Attach the eGPU to a lower Thunderbolt 2 port and power the box on **before** you switch the
Mac on. Never power the box on, plug it in or unplug it while the Mac boots (that freezes it instantly) or runs.
Shut the Mac down first, then change the eGPU. Do not use "Disconnect" in the menu bar (freezes the Mac).

## Graphics cards

Only AMD cards whose chip macOS has a driver for. Kandor itself supports Polaris and Vega; Navi (RX 5000/6000)
is being added by ne1rom. `1 status` names the card it finds.

| | Cards | Chip (family) |
|---|---|---|
| **Tested** | RX Vega 56 · RX 580 · RX 6900 XT (Tahoe, ne1rom; Navi support not in Kandor yet) | Vega 10 · Polaris 20 · Navi 21 |
| **Expected to work** (same chip as a tested card) | RX Vega 64, Vega Frontier Edition, Radeon Pro WX 9100 · RX 470, 480, 570, 590, Radeon Pro WX 7100 · RX 6800, 6800 XT | Vega 10 · Polaris 10/20/30 · Navi 21 |
| **Could work** (same driver, other chip; untested) | Radeon VII (Vega 20) · RX 460, 560, 550 (Polaris 11/21/12), Radeon Pro WX 4100/5100 · RX 5500 (XT), 5600 (XT), 5700 (XT) (Navi 14/10) · RX 6600, 6600 XT (Navi 23) · older GCN: R9 280X, 290/290X, 380/380X, 390/390X, Fury/Fury X/Nano | various |
| **Not out of the box** (chip supported, card ID not in Apple's drivers; needs a device-ID spoof Kandor does not do) | RX 6950 XT, RX 6900 XT "XTXH" variants (e.g. "Extreme"/"Ultimate"), RX 6650 XT | Navi 21 · Navi 23 |
| **Does not work** (no macOS driver at all) | RX 6700, 6700 XT, 6750 XT (Navi 22) · RX 6400, 6500 XT (Navi 24) · all RX 7000 and RX 9000 (RDNA 3/4) · Intel Arc · AMD HD 6000 and older · NVIDIA (Kandor is AMD-only) | – |

On Tahoe only the RX Vega 56 is tested with Kandor (it needs Kandor's Vega shim wrapper); Polaris and older GCN cards
use the internal D300's driver family there and are expected to need no wrapper.

## Contents
| | |
|---|---|
| `kandor.sh` | the script: credits, status, logs, EFI install; Tahoe: Vega Metal shim wrapper |
| `Kexts/Kryptonite-1.2.0.kext` | the one Kryptonite build for Monterey to Tahoe |
| `src/` | Kryptonite source patches (ne1rom's Sequoia and Tahoe patches + Kandor's four) and `build-kext.sh` (writes local builds to `src/out/`) |
| `shim/kandor_shim.m` | Tahoe: Kandor's wrapper for OCLP's Vega Metal shim (own code), built and installed by `kandor.sh vega-patch` |
| `backup/` | all backups, **local only, never publish**: `EFI/` (whole EFI before every `efi` run), `Shim/` (OCLP's original Vega shim per Tahoe build) |
| `logs/`, `build/` | created by the script: one log per change (`efi`, `vega-patch`, …) and the `log` folders |
| `LICENSE`, `LICENSE-NOTES.md` | GPL-3.0 full text; licenses, the kext build, credits, permissions |

## Use
Open Terminal, `cd` into this folder, then `sudo bash kandor.sh` (menu) or `sudo bash kandor.sh <command>`:

| Menu | Command | |
|---|---|---|
| 0 | `credits` | credits and license |
| 1 | `status` | read-only: system, Kryptonite, eGPU, AMD driver; on Tahoe also the shim and the redirects |
| 2 | `log` | read-only: status, kernel GPU messages, display policy log, WindowServer errors, crash reports (Tahoe: shim logs) into `logs/log-<date>/` |
| 3 | `efi` | install / update Kryptonite 1.2.0 in the EFI |
| 4 | `vega-patch` | Tahoe only: install the Vega Metal shim wrapper |
| 5 | `vega-patch-revert` | Tahoe only: put OCLP's original shim back |

### First setup, and after every OCLP "Build and Install OpenCore"
1. OCLP → Build and Install OpenCore (normal settings).
2. **3 efi**. It finds the EFI partition OpenCore booted from (NVRAM boot-path, like OCLP), asks before mounting,
   backs up the whole EFI to `backup/EFI/`, replaces any older Kryptonite entries with Kryptonite 1.2.0
   (kernel 21–25) and adds `krygpu=AMD krytbtv=2`. If Tahoe is running or found on a mounted volume (or you say so),
   it also adds OCLP's library-validation kernel patch, which acts on Tahoe only (needed for the Vega shim wrapper;
   AMFI stays on). It removes `amfi_get_out_of_my_way=1` if an earlier setup added it.
3. Shut down, attach the eGPU to a lower TB2 port, power it on, start the Mac, then **1 status**: every line should be ✓.

### Ventura, Sonoma, Sequoia: after every OCLP root patch or macOS update
OCLP → Post-Install Root Patch (eGPU attached at boot; on OCLP 2.5.x: Revert Root Patches first if already patched)
→ reboot → **1 status**. The root patch is always needed on Ventura and later: it installs the AMD drivers for the
eGPU and the internal D300s. What Kandor no longer needs is its own driver patch: Kryptonite 1.2.0 adapts OCLP's AMD
driver (AMDSupport) in memory for the larger display structures of Ventura and later. Monterey needs no root patch.

## Tahoe

Tahoe 26.7.2 works with the eGPU attached at boot (AMFI on).
Needs the Command Line Tools on the Mac Pro (`xcode-select --install`).

1. **3 efi** (Kryptonite 1.2.0 + the library-validation patch for Tahoe) → shut down, attach the eGPU, boot.
   That is fine as long as OCLP's Vega part is not installed yet.
2. OCLP: Post-Install Root Patch (it must offer "AMD Vega"; if Tahoe is already patched: Revert Root Patches
   first, then reboot with the eGPU attached) → shut down, unplug the eGPU, boot.
3. **4 vega-patch** → shut down, **attach the eGPU, boot**.
4. **1 status**; **2 log** if anything looks wrong.

The script keeps this order: `vega-patch` stops unless Kryptonite 1.2.0 is running (step 1 + reboot) and OCLP's
root patch has the Vega part (step 2). If OCLP's root patch is already there when you run `efi`, `efi` offers
step 3 right away (no reboot needed in between). After any OCLP root patch on Tahoe: step 3 again.

Rules:
- **Boot with the eGPU attached only while Kandor's shim wrapper is installed.** With OCLP's original shim
  the boot hangs halfway. Install, revert or re-patch with the eGPU unplugged.
- If something hangs: hold the power button, unplug the eGPU, boot Tahoe (or another macOS from the OpenCore picker).
- **5 vega-patch-revert** puts OCLP's original shim back from `backup/Shim/`.
