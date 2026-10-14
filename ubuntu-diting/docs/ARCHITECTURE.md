# Architecture

```
kernel.lock ──► fetch-sources (signed tag) ──► prepare-kernel (git archive + patches)
                                                    │
diting.config ──────────────────────────────► build-kernel (defconfig+fragment,
                                                    │        Image/dtbs/modules, bindeb-pkg)
                                                    ▼
                         linux-image-7.2.10-diting.deb   device-xiaomi-diting.deb
                                                    │            │
                                                    ▼            ▼
                     build-rootfs: debootstrap resolute ─► apt install both debs
                         │   kernel postinst → initramfs-tools → /boot/initrd.img-<ver>
                         │                   → zz-diting-bootimg → /boot/diting/{boot,vendor_boot}-<ver>.img
                         ▼
             ubuntu-diting-rootfs-resolute-arm64.img (ext4, LABEL=diting-root)

build-boot-image (host): Image + DTB(+ABL ids) + rootfs initrd ─► boot/vendor_boot v4
verify: kernel/deb/rootfs/boot-image checks against stock dumps (device-data/)
```

Boot on the phone (expected, UNTESTED): ABL loads boot.img (Image) and
vendor_boot.img (DTB + initramfs + cmdline), selects our DTB by
`qcom,msm-id`/`qcom,board-id`, (dtbo erased → no overlay), starts the kernel.
Built-in UFS/USB drivers come up, initramfs-tools runs; with `diting.debug=*` it
starts the USB gadget before mounting root.

The same `diting-mkbootimg` script is used on the host and on the device so that
kernel updates on the phone produce images identical in structure to the
host-built ones.
