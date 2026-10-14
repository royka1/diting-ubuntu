# Safe testing on the phone (owner-operated)

Nothing in this repository flashes, erases or reboots the phone. Every command in
this file is to be typed by the owner, deliberately, after reading it.

## Risk summary

| Test | Writes to phone | Risk | Rollback |
| --- | --- | --- | --- |
| T0 read-only inspection (`make inspect-device`) | nothing | none | – |
| T1 debug initramfs (no root mount) | `boot_b`, `vendor_boot_b`, erase `dtbo_b` | medium: Android on slot b will not boot until restored | flash backups from fastboot (ABL/fastboot itself is not touched) |
| T2 Ubuntu rootfs | additionally a root partition | **not defined yet** – no partition approved | – |

Fastboot mode is provided by ABL (`abl_b`), which is never written. As long as
`abl_b`/`xbl_b` are intact, fastboot stays reachable with **Power + Volume down**
from power-off, even if the kernel hangs.

## Prerequisites

1. Backups (already taken 2026-10-11, keep a second copy off this PC):
   `device-data/images/{boot_b,vendor_boot_b,dtbo_b,vbmeta_b}.img` and `SHA256SUMS`.
   Check them: `cd device-data/images && sha256sum -c SHA256SUMS`.
   Note: `boot_b.img` is the Magisk-patched boot currently in use.
2. Host has `fastboot`; phone charged > 50 %.
3. Built and verified artifacts: `make verify` shows no FAIL for the boot pair.

## T1: kernel + initramfs only (stage C/D evidence)

Artifacts: `output/boot/boot-diting-ubuntu-7.2.10-diting-debug.img` and
`output/boot/vendor_boot-diting-ubuntu-7.2.10-diting-debug.img`
(cmdline `diting.debug=hold`: no root mount, USB gadget, shell on USB serial).

```sh
adb reboot bootloader
fastboot getvar current-slot          # expect: b
fastboot erase dtbo                   # owner-approved mainline procedure (backup: dtbo_b.img)
fastboot flash boot_b        output/boot/boot-diting-ubuntu-7.2.10-diting-debug.img
fastboot flash vendor_boot_b output/boot/vendor_boot-diting-ubuntu-7.2.10-diting-debug.img
fastboot reboot
```

Expected on success (watch on the host):

```sh
dmesg -w                    # new USB device 1d6b:0104 "Diting Ubuntu debug"
ip link                     # a new usbX/enx... interface (cdc_ncm)
sudo ip addr add 172.16.42.2/24 dev <iface> && ping 172.16.42.1
sudo screen /dev/ttyACM0    # root shell inside the initramfs
```

In that shell, collect (read-only): `uname -a; cat /proc/cmdline; dmesg; ls /sys/class/udc;
cat /proc/partitions; ls -l /dev/disk/by-partlabel` and copy it to the host.
**Do not mount UFS read-write.** For read-only: `mount -o ro /dev/sdXN /mnt`.

What a result means:

| Observation | Meaning |
| --- | --- |
| USB gadget appears | kernel, DTB, initramfs, eUSB2/dwc3 all work (stage C+D) |
| Screen shows console text | simpledrm on splash works (cmd-mode panel may stay frozen instead) |
| Nothing on USB, phone stuck | collect pstore (below), then restore |
| Phone reboots to fastboot / "dtb not found" | ABL rejected the image; restore, report the fastboot output |

## Restore stock (always works from fastboot)

```sh
# Power + Volume down for ~10 s if needed, until FASTBOOT is shown
fastboot flash boot_b        device-data/images/boot_b.img
fastboot flash vendor_boot_b device-data/images/vendor_boot_b.img
fastboot flash dtbo_b        device-data/images/dtbo_b.img
fastboot reboot
```

## Reading logs of a failed boot (pstore)

The mainline ramoops region and layout are identical to Android's (0xa7000000,
console 2 MiB, pmsg 2 MiB). After a failed mainline boot, a *warm* reset may keep
RAM contents: from the hung state hold Power+Volume down into fastboot, restore
stock, boot Android, then:

```sh
adb shell su -c 'ls -l /sys/fs/pstore; cat /sys/fs/pstore/console-ramoops-0' > mainline-console.txt
adb shell su -c 'cat /sys/fs/pstore/pmsg-ramoops-0' > mainline-dmesg.txt
```

Whether RAM survives this reset path is **UNTESTED** on this unit; if the files are
missing, the logs were lost, not necessarily that the kernel did not start.

## AVB note

The bootloader is unlocked (orange state). The Magisk-patched `boot_b` boots, so
modified boot images are accepted. If ABL refuses the new `vendor_boot`, the
next step would be `fastboot --disable-verity --disable-verification flash vbmeta_b
device-data/images/vbmeta_b.img` — an **owner decision**, reversible by flashing
the original `vbmeta_b.img` again.

## T2: rootfs

Blocked until a root location is approved. Partitions ≥ 1 GiB on this unit
(measured): `userdata` (sda37, 223.6 GiB, Android data — using it wipes Android),
`super` (sda28, 8.5 GiB, Android system/vendor — must not be touched), `cust`
(sda27, 2 GiB, Xiaomi region customisation; contents/use not yet checked). There is
no SD card slot and USB is peripheral-only so far. Options to discuss:

1. shrink nothing, but use a loop image file stored on Android's `userdata`
   (needs f2fs + file-based-encryption access from the initramfs — not possible
   while userdata is FBE-encrypted);
2. dedicate `userdata` to Ubuntu (Android data loss; Android can be restored by a
   factory reset later);
3. a RAM-only Ubuntu test (small rootfs inside the initramfs, no UFS writes) to
   reach stage F without choosing a partition.

Until the owner decides, `output/ubuntu-diting-rootfs-resolute-arm64.img` is an
image file only and `BOOT_MODE=rootfs` refuses to build without `ROOT_SPEC`.
