# Packaging

| Package | Built by | Arch | Contents |
| --- | --- | --- | --- |
| `linux-image-7.2.10-diting` | `make bindeb-pkg` (upstream kernel packaging) | arm64 | `/boot/vmlinuz-*`, `config-*`, `System.map-*`, `/lib/modules/7.2.10-diting/`, DTBs in `/usr/lib/linux-image-7.2.10-diting/` |
| `linux-headers-7.2.10-diting` | same | arm64 | headers for out-of-tree modules |
| `linux-libc-dev` | same | arm64 | built by bindeb-pkg; **not installed** in the rootfs (Ubuntu's own is kept) |
| `device-xiaomi-diting` | `scripts/build-packages.sh` (debhelper 13) | all | see below |

`device-xiaomi-diting`:

- `/usr/sbin/diting-mkbootimg` (+ `/etc/diting/bootimg.conf` generated from `config/diting.conf`)
- `/etc/kernel/postinst.d/zz-diting-bootimg`, symlinked as
  `/etc/initramfs/post-update.d/zz-diting-bootimg` → `/boot/diting/{boot,vendor_boot}-<ver>.img`
  for every `*-diting` kernel/initramfs update. Never flashes.
- initramfs-tools conf/hook/init-top script (see INITRAMFS.md)
- `diting-usb-gadget.service` (enabled, not started during install)
- `/etc/apt/preferences.d/no-generic-kernel.pref`: pins Ubuntu generic kernels to -1

Install order matters only in the image build: the device package goes in first so
the kernel postinst already sees the hooks. On a running system,
`apt install ./linux-image-*.deb` runs both hooks automatically.

pmOS → Ubuntu mapping used:

| pmOS (device-xiaomi-diting) | Ubuntu |
| --- | --- |
| `deviceinfo` boot offsets | `/etc/diting/bootimg.conf` (re-measured, not copied) |
| `mkinitfs` + boot-deploy | initramfs-tools + `diting-mkbootimg` hook |
| openrc `tqftpserv`, `pd-mapper` | not yet (no remoteprocs); will be Ubuntu `tqftpserv`/`pd-mapper` systemd units when needed |
| `qbootctl` (slot marking) | not included: flashing the active slot directly, no slot switching |
| `make-dynpart-mappings` | not needed (Ubuntu does not use `super`) |
| `firmware-xiaomi-diting-*` | `make firmware` (later, local-only) |
