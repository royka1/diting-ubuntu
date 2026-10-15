# Ubuntu 26.04 for the Xiaomi 12T Pro (diting)

Ubuntu 26.04 LTS (arm64) with Phosh, on a mainline Linux 7.2 kernel.
Experimental: tested on one phone (22081212UG, EEA, HyperOS
OS3.0.5.0.VLFEUXM). Sources: https://github.com/royka1/diting-ubuntu

## What works

| Function | State |
| --- | --- |
| Display 60/90/120 Hz, touch, GPU (Turnip/freedreno, Phosh GPU-rendered) | works |
| Wi-Fi, Bluetooth | works |
| Loudspeakers (with Xiaomi's speaker protection and this phone's calibration), microphones | works |
| Calls (3G, earpiece and speaker, echo cancellation), SMS, mobile data (LTE/5G) | works; no VoLTE, calls fall back to 3G |
| Battery level, charging status | works |
| Rotation, proximity (screen off at the ear), light, compass | works |
| Rear main camera (200 MP) and ultrawide | work in GNOME Snapshot; no colour tuning yet, autofocus slow |
| Hardware video decoding (H.264, HEVC, VP9) in Firefox and Chromium | works; 4K YouTube plays smoothly |
| Suspend/resume | works; power use while suspended not measured |

Not working or not tested: front and macro cameras, the video encoder, AV1,
VoLTE, fingerprint sensor, NFC, IR blaster, USB host mode, vibration.
The phone's vendor partition also carries drivers for a Samsung HM6 main
camera; if your unit has that sensor instead of the HP1, the main camera
does not work. Details: `docs/KNOWN_ISSUES.md` in the source repository.

## Before you start

- **This erases Android's data** (userdata: apps, photos, everything). Back
  up first.
- The **bootloader must be unlocked** (Xiaomi's unlock tool, which takes
  a waiting period).
- Android should be a recent HyperOS/MIUI for this phone. The first Ubuntu
  boot copies the phone's own firmware (modem, audio DSP, GPU, Wi-Fi/BT
  calibration, cameras) from the Android partitions of the active slot, so
  that slot must hold a complete, booting Android. Other firmware versions
  than the tested one should work but are untested.
- A computer with `fastboot` (Android platform-tools) and a USB cable.

## Install

1. Download the release archive (`ubuntu-diting-<date>.tar.xz`, or all
   `.tar.xz.NNN` parts if it is split) and its `.SHA256SUMS`, and check:
   `sha256sum -c ubuntu-diting-*.SHA256SUMS`
2. Unpack:
   - Linux/macOS: `cat ubuntu-diting-*.tar.xz* | tar -xJ`
   - Windows: open the `.tar.xz` (or `.tar.xz.000`) file with 7-Zip and
     extract it twice (xz, then tar).
3. Phone off, then hold **power + volume down** until FASTBOOT shows;
   connect USB.
4. In the unpacked directory run `./flash-diting.sh` (Linux/macOS). It
   checks the phone, shows the active slot and asks before writing. On
   Windows run the same commands by hand, with `<slot>` from
   `fastboot getvar current-slot`:

   ```
   fastboot flash boot_<slot> boot.img
   fastboot flash vendor_boot_<slot> vendor_boot.img
   fastboot erase dtbo_<slot>
   fastboot flash userdata rootfs.img
   fastboot reboot
   ```

5. First boot: the screen shows text while the phone copies its firmware
   (about 2 minutes), then it **reboots by itself once**. The root
   filesystem grows to the whole userdata partition. Chromium is installed
   in the background during the first minutes (it appears in the app grid
   when ready).
6. Log in with PIN **147147**, then change it: open the Console app and
   run `passwd`.

## After installing

- Connect to Wi-Fi in Settings. Updates: `sudo apt update && sudo apt upgrade`
  (Ubuntu packages; the kernel and device packages come from the release).
- Mobile data: set the APN in Settings → Mobile Network, or
  `nmcli c add type gsm ifname '*' con-name mobile gsm.apn <your-apn>`.
- SSH is installed but accepts keys only: put your key into
  `~/.ssh/authorized_keys` first. Over USB the phone appears as a network
  adapter; it is 172.16.42.1, the computer takes 172.16.42.2.
- If the firmware copy failed (no sound, no modem, slow graphics),
  `/var/lib/diting-firmware-setup/failed` exists; see
  `journalctl -u diting-firmware-setup` and retry with
  `sudo diting-firmware-setup --reboot`.
- Android apps (Waydroid): not preinstalled. Waydroid's own images need two
  fixes on this phone (no storage, no internet with kernels before r44); see
  https://github.com/royka1/diting-ubuntu/blob/main/ubuntu-diting/docs/WAYDROID.md

## Back to Android

Flash `boot`, `vendor_boot` and `dtbo` of the same slot from the stock
fastboot ROM of your HyperOS version (or the full fastboot ROM with Xiaomi's
flash script), then `fastboot -w` to format userdata.

## Licences

The kernel (GPL-2.0), the build system and packages (GPL-2.0-or-later) and
all patches are in https://github.com/royka1/diting-ubuntu and
https://github.com/royka1/linux-diting. Ubuntu packages come from the
Ubuntu archive (sources via `apt source`). The image contains no Xiaomi or
Qualcomm firmware: it is read from each phone's own partitions at first boot.
