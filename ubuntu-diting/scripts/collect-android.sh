#!/bin/bash
# READ-ONLY collection of everything useful from the stock Android system on
# the connected Diting before it is ever flashed: raw partition backups
# (firmware, EFS/IMEI, persist, bootloader chain), firmware files, vendor
# configuration and runtime logs. Uses adb + su; only reads from the phone.
# Output: device-data/ (git-ignored, contains private data: IMEI/EFS, MACs,
# calibration, serials). Never commit or upload it.
. "$(dirname "$0")/lib.sh"
need adb tar
adb get-state >/dev/null 2>&1 || die "no adb device"
[ "$(adb shell getprop ro.product.device | tr -d '\r')" = diting ] || die "not a diting"
adb shell su -c id | grep -q 'uid=0' || die "adb root (su) not available"
sux() { adb exec-out "su -c '$1'"; }

D="$DEVICE_DATA"
mkdir -p "$D/partitions" "$D/firmware" "$D/vendor" "$D/logs"

# 1. Raw partitions: everything except Android data/system and huge dumps.
skip=' userdata super cust rawdump minidump sda sdb sdc sdd sde sdf '
for p in $(sux 'ls /dev/block/by-name' | tr -d '\r'); do
	case "$skip" in *" $p "*) continue ;; esac
	[ -s "$D/partitions/$p.img" ] && continue
	log "partition $p"
	sux "cat /dev/block/by-name/$p" > "$D/partitions/$p.img.part" && mv "$D/partitions/$p.img.part" "$D/partitions/$p.img"
done
sux 'cd /dev/block/by-name && for p in *; do echo "$p $(readlink $p) $(cat /sys/class/block/$(basename $(readlink $p))/size)"; done' > "$D/partitions/BYNAME-SECTORS.txt"
log "verifying partition dumps against the phone"
sux 'cd /dev/block/by-name && for p in *; do case " userdata super cust rawdump minidump sda sdb sdc sdd sde sdf " in *" $p "*) continue;; esac; echo "$(sha256sum < $p | cut -d" " -f1)  $p.img"; done' > "$D/partitions/SHA256SUMS.device"
(cd "$D/partitions" && sha256sum -c --quiet SHA256SUMS.device) || die "partition dump mismatch"

# 2. Firmware and vendor configuration as files (owner, permissions kept).
for dir in /vendor/firmware /vendor/firmware_mnt /vendor/dsp /vendor/bt_firmware /odm/firmware /odm/etc /vendor/etc /mnt/vendor/persist; do
	name="$(echo "${dir#/}" | tr / _)"
	log "files $dir"
	sux "tar -cf - $dir 2>/dev/null" > "$D/firmware/$name.tar" || warn "tar $dir incomplete"
done
sux 'ls -l /vendor/lib/modules; for m in /vendor/lib/modules/*.ko; do echo "== $m"; modinfo $m 2>/dev/null | grep -E "^(description|author|alias|firmware):"; done' > "$D/vendor/vendor-modules.txt"
sux 'find /vendor /odm -name "*.xml" -path "*audio*" -o -name "mixer_paths*" -o -name "*acdb*" -o -name "*thermal*"' > "$D/vendor/interesting-config-paths.txt"

# 3. Runtime state and logs.
L="$D/logs"
sux 'dmesg' > "$L/dmesg.txt"
adb logcat -d -b all > "$L/logcat-all.txt" 2>/dev/null || true
for f in cmdline bootconfig iomem interrupts partitions modules cpuinfo meminfo devices; do sux "cat /proc/$f" > "$L/proc-$f.txt"; done
sux 'cat /proc/bus/input/devices' > "$L/input-devices.txt"
sux 'getevent -lp' > "$L/getevent-lp.txt" 2>/dev/null || true
sux 'for d in /sys/bus/i2c/devices/*; do echo "$d $(cat $d/name 2>/dev/null) $(readlink $d/driver)"; done' > "$L/i2c-devices.txt"
sux 'for d in /sys/bus/spi/devices/*; do echo "$d $(cat $d/modalias 2>/dev/null) $(readlink $d/driver)"; done' > "$L/spi-devices.txt"
sux 'for d in /sys/bus/platform/devices/*; do echo "$(basename $d) $(readlink $d/driver | xargs basename 2>/dev/null)"; done' > "$L/platform-devices.txt"
sux 'for z in /sys/class/thermal/thermal_zone*; do echo "$z $(cat $z/type) $(cat $z/temp)"; done' > "$L/thermal.txt"
sux 'for p in /sys/class/power_supply/*; do echo "== $p"; cat $p/uevent; done' > "$L/power-supply.txt"
sux 'for r in /sys/class/regulator/*; do echo "$(cat $r/name 2>/dev/null) $(cat $r/microvolts 2>/dev/null) $(cat $r/state 2>/dev/null) $(cat $r/num_users 2>/dev/null)"; done' > "$L/regulators.txt"
sux 'cat /sys/kernel/debug/gpio /sys/kernel/debug/pinctrl/*/pinmux-pins 2>/dev/null' > "$L/gpio-pinmux.txt" || true
sux 'cat /sys/kernel/debug/clk/clk_summary 2>/dev/null' > "$L/clk-summary.txt" || true
sux 'cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null' > "$L/regulator-summary.txt" || true
sux 'lspci -nnk 2>/dev/null; ls -l /sys/bus/pci/devices/' > "$L/pci.txt" || true
sux 'for u in /sys/bus/usb/devices/*; do echo "$u $(cat $u/idVendor 2>/dev/null):$(cat $u/idProduct 2>/dev/null) $(cat $u/product 2>/dev/null)"; done' > "$L/usb.txt"
sux 'dumpsys SurfaceFlinger --display-id; dumpsys display | grep -iE "mode|density|DisplayDeviceInfo"' > "$L/display.txt" 2>/dev/null || true
sux 'cat /sys/class/drm/*/modes 2>/dev/null; ls -l /sys/class/drm' >> "$L/display.txt"
sux 'cat /sys/devices/soc0/*' > "$L/soc0.txt" 2>/dev/null || true
sux 'cat /sys/fs/pstore/* 2>/dev/null' > "$L/pstore-android.txt" || true
adb shell getprop > "$L/getprop.txt"
sux 'cat /sys/firmware/fdt' > "$L/live.dtb"
dtc -q -I dtb -O dts -o "$L/live.dts" "$L/live.dtb" || true

(cd "$D" && find firmware vendor logs -type f -print0 | xargs -0 sha256sum > SHA256SUMS-collect.txt)
log "collected into $D ($(du -sh "$D" | cut -f1)); PRIVATE, keep a copy off this PC"
