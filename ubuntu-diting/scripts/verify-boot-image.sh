#!/bin/bash
# Compare a generated boot/vendor_boot pair with the stock Diting images and
# check the embedded DTB. Read-only. Exits non-zero on any mismatch.
. "$(dirname "$0")/lib.sh"
boot="$1" vboot="$2"
stock="$DEVICE_DATA/images"
info() { python3 "$UD/scripts/bootimg_info.py" "$1" | grep -v '^#'; }
field() { grep "^$2=" <<<"$1" | cut -d= -f2-; }
fail=0
check() { # name expected actual
	if [ "$2" = "$3" ]; then echo "PASS $1 = $3"; else echo "FAIL $1: expected '$2', got '$3'"; fail=1; fi
}

sb="$(info "$stock/boot_b.img")"; gb="$(info "$boot")"
sv="$(info "$stock/vendor_boot_b.img")"; gv="$(info "$vboot")"

check boot.header_version "$(field "$sb" header_version)" "$(field "$gb" header_version)"
check boot.kernel_is_arm64_Image True "$(field "$gb" kernel_magic_arm64)"
for k in header_version page_size kernel_addr ramdisk_addr tags_addr dtb_addr; do
	check "vendor_boot.$k" "$(field "$sv" "$k")" "$(field "$gv" "$k")"
done
check vendor_boot.dtb_count 1 "$(field "$gv" dtb_count)"
fits() { # name file limit
	if [ "$(stat -c %s "$2")" -le "$3" ]; then echo "PASS $1 fits partition"; else echo "FAIL $1 too large"; fail=1; fi
}
fits boot "$boot" "$BOOT_PARTITION_SIZE"
fits vendor_boot "$vboot" "$VENDOR_BOOT_PARTITION_SIZE"

# Unpack and inspect the DTB that ABL will see.
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
unpack_bootimg --boot_img "$vboot" --out "$t" >/dev/null
check dtb.compatible "xiaomi,diting qcom,sm8475" "$(fdtget -ts "$t/dtb" / compatible | tr '\n' ' ' | sed 's/ $//')"
check dtb.qcom,msm-id "$ABL_MSM_ID" "$(fdtget -tu "$t/dtb" / qcom,msm-id)"
check dtb.qcom,board-id "$ABL_BOARD_ID" "$(fdtget -tu "$t/dtb" / qcom,board-id)"
echo "INFO vendor_cmdline: $(field "$gv" vendor_cmdline)"
echo "INFO sizes: boot=$(stat -c %s "$boot") vendor_boot=$(stat -c %s "$vboot") ramdisk=$(field "$gv" vendor_ramdisk_size)"
exit $fail
