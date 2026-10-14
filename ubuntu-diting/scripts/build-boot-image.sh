#!/bin/bash
# Build Diting boot.img + vendor_boot.img from the
# built kernel, DTB and the Ubuntu initramfs generated inside the rootfs.
# Writes files under output/boot only; never flashes or boots the phone.
# The vendor dtbo must not be applied to the mainline DTB: the owner clears
# it with "fastboot erase dtbo" (see docs/SAFE_TESTING.md).
#
#   BOOT_MODE=debug   initramfs-only test, "diting.debug=hold": USB NCM +
#                     ACM root shell, dmesg to pstore; no root mount (default)
#   BOOT_MODE=rootfs  boot Ubuntu from ROOT_SPEC, e.g.
#                     ROOT_SPEC="root=PARTLABEL=<verified partition>"
. "$(dirname "$0")/lib.sh"
need mkbootimg fdtput fdtget python3

BOOT_MODE="${BOOT_MODE:-debug}"
kernel="$OUT/kernel/Image-$KERNEL_RELEASE"
dtb="$OUT/kernel/$(basename "$KERNEL_DTB")"
initrd="$WORK/rootfs/boot/initrd.img-$KERNEL_RELEASE"
for f in "$kernel" "$dtb"; do [ -f "$f" ] || die "missing $f; run 'make kernel'"; done
[ -f "$initrd" ] || die "missing $initrd; run 'make rootfs' (initramfs-tools builds it)"

# Boot layout must have been measured on the phone, not assumed.
stock="$DEVICE_DATA/images"
[ -f "$stock/boot_b.img" ] && [ -f "$stock/vendor_boot_b.img" ] ||
	die "stock boot images not found in $stock; run 'make inspect-device' (read-only adb) first"

case "$BOOT_MODE" in
debug) cmdline="diting.debug=hold" ;;
rootfs)
	# ROOT_SPEC overrides the approved deployment cmdline from diting.conf.
	if [ -n "${ROOT_SPEC:-}" ]; then
		cmdline="$ROOT_SPEC rw rootwait diting.debug=usb"
	else
		cmdline="$DITING_ROOT_CMDLINE"
	fi
	[ -n "$cmdline" ] || die "BOOT_MODE=rootfs needs DITING_ROOT_CMDLINE (diting.conf) or ROOT_SPEC; see docs/SAFE_TESTING.md"
	;;
*) die "unknown BOOT_MODE '$BOOT_MODE'" ;;
esac

dir="$OUT/boot"
mkdir -p "$dir" "$WORK/boot"
conf="$WORK/boot/bootimg.conf"
write_bootimg_conf "$conf"
name="diting-ubuntu-$KERNEL_RELEASE-$BOOT_MODE"

"$UD/packages/device-xiaomi-diting/src/diting-mkbootimg" --conf "$conf" \
	--kernel "$kernel" --initrd "$initrd" --dtb "$dtb" \
	--cmdline "$cmdline" --out "$dir" --name "$name"

"$UD/scripts/verify-boot-image.sh" "$dir/boot-$name.img" "$dir/vendor_boot-$name.img" |
	tee "$dir/verify-$name.txt"
(cd "$dir" && sha256sum "boot-$name.img" "vendor_boot-$name.img" > "SHA256SUMS-$name")
log "boot artifacts in $dir (UNTESTED ON DEVICE, not flashed)"
