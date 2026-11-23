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
`mayankk2308/kryptonite` `6e97e36` plus patches 1–9 in `src/`: ne1rom's five (`kandor-sequoia-24G720.patch`,
`kandor-tahoe-25G241.patch`, Navi display fix, Navi user-client redirects and holding Apple's Navi driver off until
OCLP's Navi patch, for Tahoe) and Kandor's four (Sonoma
threshold, AMDSupport display fix in memory, X5000 user-client redirects for Tahoe, version). Binary md5 and tests:
added with the release build.

Earlier builds are no longer shipped: 1.2.0 (patches 1–6, no Navi; md5 `f95cb8769554439ff91828d957884ddf`, tested on
21 Nov 2026 on Monterey 12.7.6, Sonoma 14.8.9, Sequoia 15.8.1 and Tahoe 26.7.2 with an RX Vega 56) and 1.1.0
(ne1rom's Sequoia build with one byte changed, Monterey to Sequoia).

## Credits
- acidanthera: OpenCore, Lilu; Dortania: OpenCore Legacy Patcher
- mayankk2308 & mac_editor: Kryptonite; goalque: NVIDIA eGFX support; rgov: Ti82 patches (adapted by mac_editor)
- ne1rom, with assistance from Claude (Anthropic): Kryptonite for macOS Sequoia and Tahoe; Navi on Tahoe (AGDC fix for
  the Navi framebuffer, user-client redirects for AMDRadeonX6000, holding Apple's Navi driver off until OCLP's Navi
  patch, Navi path in the shim wrapper)
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
- Mac Pro (Late 2013, MacPro6,1) only
- AMD eGPUs only (tested: Radeon RX Vega 56 and RX 580 in a Razer Core X Chroma, Radeon RX 6900 XT in an Akitio
  Node Titan); NVIDIA is not supported; Navi cards on Monterey and Tahoe only
- eGPU on a lower Thunderbolt 2 port (Bus 0), cold boot only; the upper ports hang the firmware at boot
- macOS Monterey to Tahoe with OCLP 2.5.1 / 3.0.0-rc.5 (Tahoe: 3.0.0-rc.5, shim wrapper for Vega and Navi, eGPU attached at boot)
