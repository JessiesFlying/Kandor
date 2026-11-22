# Kandor - a whole new world in the cylinder

**External Graphic Cards for the Mac Pro 2013 "Trash Can".**

Kandor gets an external AMD graphics card working on the Mac Pro 2013 from macOS Monterey to Tahoe and the internal
FirePro GPUs keep working as before. It is built on the Monterey project "[Kryptonite](https://github.com/mayankk2308/kryptonite)" and,
like Superman's city in a bottle "Kandor", it is a whole new world in the cylinder.

## 🧰 What you need

- A **Mac Pro (Late 2013)** running macOS Monterey (12), Ventura (13), Sonoma (14), Sequoia (15) or Tahoe (26) – from Ventura on with
  [OpenCore Legacy Patcher](https://dortania.github.io/OpenCore-Legacy-Patcher/) (OCLP)
- A **Thunderbolt 3 eGPU box** and a Thunderbolt 2 cable
- The original **Apple Thunderbolt 3 (USB-C) to Thunderbolt 2 Adapter** (not a third-party one)
- A supported **AMD graphics card** (table below)

> [!TIP]
> Not every eGPU box gets along with the Mac Pro. Before you buy one, check [egpu.io](https://egpu.io) for boxes
> that others have used successfully with Thunderbolt 2 Macs. Kandor was tested with a Razer Core X Chroma.

## 🎮 Graphics cards

| | Cards | AMD family |
|---|---|---|
| ✅ **Tested** | Radeon RX Vega 56 · Radeon RX 580 | Vega · Polaris |
| 🟢 **Should work** (same drivers) | RX Vega 64 · Vega Frontier Edition · Radeon Pro WX 9100 · Radeon VII · RX 460 · RX 470 · RX 480 · RX 560 · RX 570 · RX 590 · Radeon Pro WX 4100 / 5100 / 7100 · R9 280X / 290 / 380 / 390 / Fury / Nano | Vega · Polaris · older GCN |
| 🔜 **Coming soon** | RX 6800 · RX 6800 XT · RX 6900 XT | Navi (RDNA 2) |
| 🟡 **Might work** with the Navi update | RX 5500 / 5600 / 5700 (XT) · RX 6600 (XT) | Navi (RDNA 1 and 2) |
| ❌ **Not supported** | RX 540 / 550 (most of them) · RX 580 2048SP · RX 590 GME · RX 6950 XT · RX 6900 XT "XTXH" models · RX 6650 XT · RX 6700 / 6750 XT · RX 6400 / 6500 XT · all RX 7000 and RX 9000 · NVIDIA · Intel Arc | Polaris · Navi (RDNA 2) · RDNA 3 and 4 · other brands |

## 🚀 Setup

> [!IMPORTANT]
> **Always switch the eGPU box on first, then the Mac.** Never plug in, unplug or switch on the eGPU while the Mac
> starts up or runs – the Mac freezes. To change something, shut the Mac down first. Don't use "Disconnect" in the
> menu bar either.

### 0. Monterey only: install OpenCore (optional)

Monterey runs on the Mac Pro without OCLP. If OpenCore isn't installed yet, click **Build and Install OpenCore** in
OCLP first. On Ventura and later it is already there.

### 1. Get and install Kandor

Download **Kandor.zip** from the [latest release](https://github.com/JessiesFlying/Kandor/releases/latest) and unzip
it (for example in Downloads). Open Terminal, go into the folder and start the Kandor menu:

```
cd ~/Downloads/Kandor
sudo bash kandor.sh
```

Then choose menu option **#3: "efi"**. It asks before it changes anything and keeps a backup of your EFI.

### 2. Shut down and attach the eGPU

Shut down the Mac, connect the eGPU to one of the **two lower Thunderbolt ports** (the pair next to HDMI), switch the
box on, then start the Mac.

> [!WARNING]
> The upper Thunderbolt ports don't work for the eGPU: with the eGPU there, the Mac doesn't start (no chime).

### 3. Install the drivers

Skip this step on Monterey.

In OCLP, click **Post-Install Root Patch** with the eGPU attached. If OCLP says the system is already patched, click
**Revert Root Patches** first, restart and try again. Then restart.

On **Tahoe with a Vega card**: shut down instead of restarting and go on with step 4.

### 4. Tahoe with a Vega card only

With the **eGPU unplugged**, start the Mac, start the Kandor menu and choose menu option **#4: "vega-patch"**. Then shut down, plug the eGPU back in, switch the box on and start the Mac.

### 5. Check

```
sudo bash kandor.sh
```

Start the Kandor menu and choose menu option **#1: "status"**. Every line should show a green ✓. 🎉

## 🔁 What to do after updating

| After … | do this |
|---|---|
| OCLP **Build and Install OpenCore** | menu option **#3: "efi"** again |
| an OCLP root patch or a macOS update | nothing – except on Tahoe with a Vega card: menu option **#4: "vega-patch"** again, with the eGPU unplugged |

## 📋 Menu

| | |
|---|---|
| **#0: "credits"** | who made what, license |
| **#1: "status"** | checks everything, changes nothing |
| **#2: "log"** | collects the logs into the `logs` folder when something goes wrong, changes nothing |
| **#3: "efi"** | installs Kandor into OpenCore |
| **#4: "vega-patch"** | Tahoe with a Vega card: installs the graphics fix |
| **#5: "vega-patch-revert"** | Tahoe: removes it again |

## 🛟 If something goes wrong

- **The Mac hangs while starting:** hold the power button until it turns off, unplug the eGPU and start the Mac
  again (or pick another macOS in the OpenCore boot menu).
- **No picture on the eGPU:** choose menu option **#1: "status"** – the lines marked ✗ or ! tell you what to do.
- **Still stuck:** choose menu option **#2: "log"** and share the new folder in `logs` when you ask for help.

Kandor creates the folders `backup` and `logs` next to `kandor.sh`. They stay on your Mac – don't share `backup`.

## ❤️ Credits

Kryptonite by mayankk2308 and mac_editor (with patches by goalque and rgov) · Kryptonite for Sequoia and Tahoe by
ne1rom, with assistance from Claude (Anthropic) · Kandor by JessiesFlying, with assistance from Claude (Anthropic) ·
OpenCore and Lilu by acidanthera · OpenCore Legacy Patcher by Dortania.

Who did which part: [AUTHORS](AUTHORS) · licenses: [LICENSE-NOTES.md](LICENSE-NOTES.md) · Kandor is GPL-3.0
([LICENSE](LICENSE)).
