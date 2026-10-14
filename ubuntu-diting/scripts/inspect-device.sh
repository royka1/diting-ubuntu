#!/bin/bash
# READ-ONLY collection of boot images and system info from the connected
# Diting via adb + root (su). Writes to device-data/ (git-ignored: contains
# serials and other private data). Never writes to the phone's partitions.
. "$(dirname "$0")/lib.sh"
need adb dtc
adb get-state >/dev/null 2>&1 || die "no adb device"
[ "$(adb shell getprop ro.product.device | tr -d '\r')" = diting ] || die "connected device is not a diting"
adb shell su -c id | grep -q 'uid=0' || die "root (su) not available over adb"

img="$DEVICE_DATA/images" inf="$DEVICE_DATA/info"
mkdir -p "$img" "$inf"
slot="$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')"
log "active slot: $slot"
for p in boot_a boot_b vendor_boot_a vendor_boot_b dtbo_a dtbo_b vbmeta_a vbmeta_b vbmeta_system_a vbmeta_system_b recovery_a recovery_b; do
	[ -s "$img/$p.img" ] && continue
	log "reading $p"
	adb exec-out "su -c 'cat /dev/block/by-name/$p'" > "$img/$p.img"
done
(cd "$img" && sha256sum ./*.img > SHA256SUMS)
adb exec-out "su -c 'cat /sys/firmware/fdt'" > "$inf/live.dtb"
dtc -q -I dtb -O dts -o "$inf/live.dts" "$inf/live.dtb"
for f in iomem partitions interrupts cmdline bootconfig; do
	adb exec-out "su -c 'cat /proc/$f'" > "$inf/$f.txt"
done
adb exec-out "su -c dmesg" > "$inf/dmesg.txt"
adb exec-out "su -c 'ls -l /dev/block/by-name'" > "$inf/byname.txt"
adb exec-out "su -c 'cat /sys/devices/soc0/soc_id /sys/devices/soc0/revision /sys/devices/soc0/machine'" > "$inf/soc.txt"
adb exec-out getprop > "$inf/getprop.txt"
for i in "$img"/boot_b.img "$img"/vendor_boot_b.img; do python3 "$UD/scripts/bootimg_info.py" "$i"; done
log "saved to $DEVICE_DATA (private, git-ignored)"
