# Initramfs

Ubuntu `initramfs-tools`, generated inside the rootfs by the normal kernel postinst
(`update-initramfs -c -k 7.2.10-diting`). Configuration shipped by
`device-xiaomi-diting`:

- `/etc/initramfs-tools/conf.d/diting`: `MODULES=list`, `COMPRESS=zstd`, `BUSYBOX=y`.
  UFS host/PHY, ICE, eUSB2 PHY, PTN3222, GENI I2C, GPI DMA, dwc3 and USB configfs are
  built into the kernel, so no module is required before the root mount.
- hook `diting`: adds `/usr/lib/diting/diting-usb-gadget` and `ip`.
- `init-top/diting-debug`: only active with `diting.debug=` on the cmdline
  - `usb`: configfs gadget (NCM 172.16.42.1/24 + ACM), root shell on `/dev/ttyGS0`,
    `dmesg` copied to `/dev/pmsg0` every 5 s (pstore)
  - `hold`: same, then stops (no root mount) — used by the first test image

Root selection: none is baked in. `BOOT_MODE=rootfs` requires an explicit
`ROOT_SPEC` (e.g. `root=PARTLABEL=...` or `root=LABEL=diting-root`), to be chosen
only after the owner approves a partition. The rootfs fstab uses `LABEL=diting-root`.

Size budget: vendor_boot partition 96 MiB (initramfs + DTB). Checked by
`diting-mkbootimg` and `verify`.

Firmware in initramfs: none needed yet. When remoteprocs/GPU are enabled, firmware
needed before root will be added by a hook with a manifest.

Security: the debug shell is root without password, reachable only through the
phone's USB port, and only when the cmdline asks for it (images built with
`BOOT_MODE=debug`). Production images (`BOOT_MODE=rootfs`) still pass
`diting.debug=usb` during bring-up — remove it from `build-boot-image.sh` once the
system is stable.
