# ubuntu-diting

Ubuntu 26.04 LTS (`resolute`) arm64 for the Xiaomi 12T Pro / Redmi K50 Ultra
(`diting`, SM8475) on the upstream **stable** Linux kernel (locked: **7.2.10**)
plus the Diting patch series in `../kernel/patches`.

Status: runs as a daily-usable phone on the owner's unit (Phosh, calls, SMS,
mobile data, Wi-Fi, audio, sensors, two rear cameras, hardware video
decoding). Per-subsystem evidence: `../docs/BRINGUP_STATUS.md`; open problems:
`docs/KNOWN_ISSUES.md`. Installing a released image: `release/INSTALL.md`.

## Layout

```
linux-diting/
├── docs/                    SOURCES, HARDWARE, BRINGUP_STATUS, KERNEL_PORTING, DECISIONS
├── kernel/
│   ├── patches/             patch series on top of the signed stable tag
│   └── config/diting.config config fragment on top of arm64 defconfig
├── tools/                   firmware builder, super/lp parser, ACDB/topology, camera, DSP diag tools
├── references/              upstream/community trees (make sources; git-ignored)
├── device-data/             PRIVATE dumps from the owner's phone (git-ignored, never published)
└── ubuntu-diting/
    ├── Makefile, config/    diting.conf, kernel.lock, package lists, apt keys
    ├── scripts/             build, inspect and verify scripts
    ├── packages/            device-xiaomi-diting, diting-firmware-setup, libva-v4l2-stateful,
    │                        hexagonrpc, libcamera, phoc, audio-topology (debian/ + patches)
    ├── release/             flash script and install guide shipped with images
    ├── docs/
    ├── work/                temporary (git-ignored)
    └── output/              debs, images, logs (git-ignored)
```

## Build

```sh
cd linux-diting/ubuntu-diting
make check-host            # host tools (docs/BUILD.md lists the packages)
make sources               # clone + signature-check v7.2.10, clone references
make kernel packages       # linux-image-*.deb, device-xiaomi-diting, fastrpc, hexagonrpcd
make vaapi firmware-setup  # VA-API driver, first-boot firmware extraction (arm64 chroot)
make release               # public image: rootfs (sudo) + boot images, packed for download
```

`make release` builds the root filesystem with `ROOTFS_PROFILE=public`:
no device firmware, a default PIN (147147), no SSH keys and no debug shell on
the kernel command line. It then packs `output/release/ubuntu-diting-<date>/`
(boot.img, vendor_boot.img, sparse rootfs.img, flash script, checksums) into
`.tar.xz` parts. `make rootfs` (default `ROOTFS_PROFILE=owner`) builds the
developer image instead: the local `firmware-xiaomi-diting` if `make firmware`
built it, a password-less account with the build user's SSH key.

Some packages still need an arm64 host because they build inside a copy of
the rootfs: `make sensors`, `make libcamera`, `make phoc`, `build-fastrpc.sh`,
`build-hexagonrpc.sh` (see `docs/BUILD.md`). Their patches are in
`packages/`.

Nothing here flashes the phone; `release/flash-diting.sh` is run by the user.

## Firmware

The phone needs Xiaomi/Qualcomm firmware that is signed for the device and
may not be redistributed (ADSP, modem, IPA, SLPI, GPU zap shader, video,
Bluetooth NVM, Wi-Fi board data, speaker amplifier tuning, the ACDB voice
calibration, camera register tables). Images never contain it:
`diting-firmware-setup` reads it at first boot from the phone's own Android
partitions (read-only) and builds `firmware-xiaomi-diting` locally, with the
same builder (`tools/firmware/diting-build-firmware`) that `make firmware`
uses on the owner's backups. Details: `docs/FIRMWARE.md`.

## Updating the kernel

```sh
make check-latest-kernel   # read-only comparison with kernel.org
make update-kernel         # verify new signed tag, rebase patches, rewrite kernel.lock
```

No build target changes the locked version.

## Verify without the phone

`make verify` checks the kernel release string, DTB, deb contents, the rootfs
(`os-release`, arm64 dpkg, systemd, signed sources, no Alpine/OpenRC, initramfs) and
compares the boot images field by field with the stock images. Passing it says
nothing about whether the phone boots.
