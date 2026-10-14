#!/bin/sh
# Install Ubuntu on a Xiaomi 12T Pro (diting) from fastboot.
#
#   ./flash-diting.sh [--yes]
#
# Run in the unpacked release directory, with the phone in fastboot mode
# (power + volume down) and connected by USB. The bootloader must already be
# unlocked.
#
# What it does, on the slot the phone currently boots (fastboot getvar
# current-slot):
#   boot_<slot>         <- boot.img         (Linux kernel)
#   vendor_boot_<slot>  <- vendor_boot.img  (device tree, initramfs)
#   dtbo_<slot>         erased              (Android's overlays break the mainline DT)
#   userdata            <- rootfs.img       (Ubuntu; ERASES ALL ANDROID DATA)
#
# The other slot, super (system/vendor), modem, persist and the bootloader
# are not touched. The first boot reads the phone's firmware from those
# partitions (read-only). Going back to Android: flash boot, vendor_boot and
# dtbo of the same slot from the stock ROM's fastboot package, then
# `fastboot -w` (format userdata).
set -eu

cd "$(dirname "$0")"
for f in boot.img vendor_boot.img rootfs.img; do
	[ -f "$f" ] || { echo "missing $f (unpack the release first, see README)"; exit 1; }
done
if [ -f SHA256SUMS ]; then
	echo "checking SHA256SUMS ..."
	if command -v sha256sum >/dev/null; then sha256sum -c --ignore-missing SHA256SUMS
	else shasum -a 256 -c SHA256SUMS 2>/dev/null | grep -v ': FAILED open'; fi
fi
command -v fastboot >/dev/null || { echo "fastboot not found (Android platform-tools)"; exit 1; }

product="$(fastboot getvar product 2>&1 | awk '/^product:/ { print $2 }')"
[ "$product" = diting ] || { echo "connected device reports product '$product', not 'diting'"; exit 1; }
unlocked="$(fastboot getvar unlocked 2>&1 | awk '/^unlocked:/ { print $2 }')"
[ "$unlocked" = yes ] || { echo "the bootloader is not unlocked"; exit 1; }
slot="$(fastboot getvar current-slot 2>&1 | awk '/^current-slot:/ { print $2 }')"
case "$slot" in a|b) ;; *) echo "cannot read the current slot ('$slot')"; exit 1 ;; esac

echo
echo "Xiaomi 12T Pro found, active slot: $slot"
echo "This flashes boot_$slot, vendor_boot_$slot, erases dtbo_$slot and"
echo "OVERWRITES userdata: all Android apps, data, photos on the phone are lost."
if [ "${1:-}" != --yes ]; then
	printf 'Type "yes" to continue: '
	read -r answer
	[ "$answer" = yes ] || { echo "aborted"; exit 1; }
fi

fastboot flash "boot_$slot" boot.img
fastboot flash "vendor_boot_$slot" vendor_boot.img
fastboot erase "dtbo_$slot"
fastboot flash userdata rootfs.img
fastboot reboot
echo
echo "Done. The first boot extracts the phone's firmware (about 2 minutes,"
echo "text on screen) and reboots once by itself. Log in with PIN 147147."
