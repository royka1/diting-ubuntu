# Boot layout (Xiaomi Diting, owner's 22081212UG unit)

Measured 2026-10-11 from raw partition dumps (`device-data/images`, read with
`cat /dev/block/by-name/<p>` over adb root) and parsed with `scripts/bootimg_info.py`
and `unpack_bootimg`. Cross-checked with LineageOS BoardConfig (agrees).

## Stock images (slot b, active)

| Field | boot_b | vendor_boot_b |
| --- | --- | --- |
| magic | `ANDROID!` | `VNDRBOOT` |
| header version | 4 | 4 |
| page size | (4096, implied by v4) | 4096 |
| kernel | 46 854 828 bytes, uncompressed arm64 `Image` (ARMd magic) | – |
| ramdisk | 1 959 519 bytes, LZ4 (Magisk-patched generic ramdisk) | 1 vendor ramdisk, 23 729 061 bytes |
| cmdline | empty | `video=vfb:640x400,bpp=32,memsize=3072000 disable_dma32=on swinfo.fingerprint=... mtdoops.fingerprint=... bootconfig` |
| os version / patch | 12.0.0 / 2025-09 | – |
| kernel / ramdisk / tags / dtb addr | – | 0x8000 / 0x1000000 / 0x100 / 0x1f00000 (base 0) |
| DTB section | – | 6 443 663 bytes, **14** base DTBs (Cape, CapeP, Cape LTE, Diwali, Ukee, Waipio variants), all `board-id 0 0` |
| bootconfig | – | 85 bytes |
| boot signature | 4096 bytes | – |
| partition size | 201 326 592 | 100 663 296 |

`dtbo_b`: Android DT table (magic `d7b7ab1e`) with the board overlays (board-id
0x10008). `boot_a` is byte-identical to `boot_b`. `vendor_boot_a` and `dtbo_a` are
**all zeros**; slot A bootloader partitions (xbl, abl, tz, ...) hold different,
older firmware. No `init_boot` partition.

ABL combines one base DTB (selected by msm-id, here CapeSoC 0x212 → live DT shows
msm-id 0x213/0x21c/0x212) with the matching dtbo overlay (board-id 0x10008).

## Generated images (`scripts/build-boot-image.sh`, `diting-mkbootimg`)

| Field | boot | vendor_boot |
| --- | --- | --- |
| header version | 4 (same as stock) | 4 (same as stock) |
| page size | 4096 | 4096 |
| kernel | `Image` of 7.2.10-diting, uncompressed | – |
| generic ramdisk | none | – |
| vendor ramdisk | – | Ubuntu initramfs-tools initrd (zstd) |
| DTB | – | one `sm8475-xiaomi-diting.dtb` + `qcom,msm-id = <531 0x10000 540 0x10000 530 0x10000>`, `qcom,board-id = <0x10008 0>` (fdtput) |
| addresses | – | identical to stock (verified by `verify-boot-image.sh`) |
| cmdline (vendor) | – | `console=tty0 earlycon clk_ignore_unused pd_ignore_unused` + mode args |
| os version / patch | 12.0.0 / 2025-09 (copied from stock) | – |

ABL appends its own arguments (androidboot.*, serial etc. as bootconfig) and adds
memory/chosen nodes; `CONFIG_BOOT_CONFIG=y` makes the kernel strip/parse the bootconfig
trailer.

## Unknowns (must be measured on the phone)

1. Whether ABL accepts a vendor_boot with a single DTB carrying these ids (UNTESTED).
2. Whether ABL boots with `dtbo` erased (owner reports this is the usual mainline
   procedure; not yet observed on this unit).
3. Whether AVB in orange state accepts a non-matching vendor_boot hash without
   touching vbmeta. Evidence for "yes": the Magisk-modified boot_b already boots.
   If ABL refuses, flashing vbmeta with verification disabled is an owner decision.
4. Whether `fastboot boot` is useful: for header v4 it would only replace boot.img
   while the stock vendor_boot (vendor DTBs) is still used, so it cannot test the
   mainline DTB. Not used.
