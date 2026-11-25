# License notes – Kandor 1.0.0

## Licenses
- **OpenCore, Lilu** (acidanthera): BSD-3-Clause. Not included; OCLP installs them.
- **OpenCore Legacy Patcher** (Dortania): BSD-4-Clause for its own files, bundled components under their own
  licenses (https://dortania.github.io/OpenCore-Legacy-Patcher/LICENSE.html). Not included.
- **Kryptonite** (mayankk2308, https://github.com/mayankk2308/kryptonite): GPL-3.0. Full text in `LICENSE`.
  `Kexts/Kryptonite-1.3.0.kext` is distributed under GPL-3.0; its source is the upstream repository plus
  patches 1–9 in `src/` (see `src/README.md`).
- **kandor.sh**, **shim/kandor_shim.m**, **src/build-kext.sh** and the source patches 3–6 (JessiesFlying, with assistance from
  Claude (Anthropic)): GPL-3.0 (`SPDX-License-Identifier: GPL-3.0-only`).
- Source patches 1–2 and 7–9 (ne1rom, with assistance from Claude (Anthropic)): changes to Kryptonite, GPL-3.0 like
  Kryptonite (`SPDX-License-Identifier: GPL-3.0-only`).

**No Apple or OCLP binaries are part of Kandor.** The AMD driver fix is a patch inside Kryptonite that changes
OCLP's AMDSupport (and, for Navi, OCLP's AMDRadeonX6000Framebuffer) in memory only; the shim wrapper re-exports
OCLP's shim installed on the user's own machine.
The `backup/` folder is created locally by the script and must never be published.

## Kryptonite builds
**1.3.0** (the one build of Kandor, kernel 21–25, Monterey to Tahoe): built by `src/build-kext.sh` from upstream
`mayankk2308/kryptonite` `6e97e36` plus patches 1–9 in `src/`: ne1rom's five (Sequoia support; Tahoe support;
Navi display fix on Tahoe; Navi user-client redirects on Tahoe; holding Apple's Navi driver off until OCLP's Navi
patch on Tahoe) and JessiesFlying's four (Sonoma threshold; AMDSupport display fix in memory; X5000 user-client
redirects for Tahoe; version). Binary md5
`69990739914d3e69294d5253c7238caa` (built 23 Nov 2026); tested with this binary: Radeon RX 6900 XT (Navi) on Tahoe 26.7.3 by ne1rom, including patch 9;
Radeon RX Vega 56 on Tahoe 26.7.2 (install order efi → root patch → shim-patch → restart, Geekbench Metal 88,558)
and on Monterey 12.7.6 by JessiesFlying.

## Credits
- acidanthera: OpenCore, Lilu
- Dortania: OpenCore Legacy Patcher
- mayankk2308 & mac_editor: Kryptonite; goalque: NVIDIA eGFX support; rgov: Ti82 patches (adapted by mac_editor)
- ne1rom, with assistance from Claude (Anthropic): Kryptonite for macOS Sequoia and Tahoe; Navi on Tahoe (AGDC fix for
  the Navi framebuffer, user-client redirects for AMDRadeonX6000, holding Apple's Navi driver off until OCLP's Navi
  patch, Navi path in the shim wrapper, Navi support in kandor.sh)
- JessiesFlying, with assistance from Claude (Anthropic): Kryptonite for Ventura & Sonoma (one build for Monterey to Tahoe), the AMDSupport fix for
  eGPU display output, the Tahoe user-client redirects and Vega Metal shim wrapper, Kandor

## Permission from mayankk2308
In an issue he opened at dortania/OpenCore-Legacy-Patcher (follow-up to #396, never resolved),
mayankk2308 granted the rights to his eGPU patches for general use:
- Thunderbolt-version check bypass (old patch 10.13.4–10.15, new patch 10.15.1+, AppleGPUWrangler)
- `IOPCITunnelCompatible` bypass (IOPCIFamily), so older AMD drivers load over Thunderbolt

He states that his kext as a whole cannot be taken over directly (e.g. into OCLP), because it
also contains patches by others (goalque: NVIDIA eGFX; rgov: Ti82) that he used with their
explicit permission. Kandor therefore does not relicense anything: it redistributes Kryptonite
under its own GPL-3.0 with credits.

He also noted: an AMD eGPU on a Mac with an internal NVIDIA GPU gives a black external screen
(workaround `nv_disable=1` + mux to iGPU). Not relevant for the Mac Pro 2013 (internal GPUs are AMD).

## Scope of Kandor
- Mac Pro (Late 2013, MacPro6,1)
- AMD eGPUs only (for now) – tested: Radeon RX Vega 56 and RX 580 in a Razer Core X Chroma, Radeon RX 6900 XT in an
  Akitio Node Titan; NVIDIA not supported (for now); Navi cards on Monterey and Tahoe only
- eGPU on a lower Thunderbolt 2 port (Bus 0), cold boot only; the upper ports hang the firmware at boot
- macOS Monterey to Tahoe with OCLP 2.5.1 / 3.0.0-rc.5
