#!/bin/bash
# Build the device-xiaomi-diting Debian package (arch all).
. "$(dirname "$0")/lib.sh"
need dpkg-buildpackage dh fakeroot

PKG_VERSION="${DEVICE_PKG_VERSION:-0.7.13}"
src="$UD/packages/device-xiaomi-diting"
bld="$WORK/pkg/device-xiaomi-diting-$PKG_VERSION"

rm -rf "$WORK/pkg"
mkdir -p "$bld" "$OUT/debs" "$OUT/logs"
cp -a "$src/." "$bld/"

# On-device copy of the verified boot layout (subset of diting.conf).
write_bootimg_conf "$bld/bootimg.conf"

# AudioReach topology for the loudspeakers, from packages/audio-topology and
# the linux-msm/audioreach-topology macros at a pinned commit (make sources).
need m4 alsatplg
ART="$DITING_TOP/references/audioreach-topology"
[ "$(git -C "$ART" rev-parse HEAD 2>/dev/null)" = "$AUDIOREACH_TOPOLOGY_COMMIT" ] ||
	die "need $ART at $AUDIOREACH_TOPOLOGY_COMMIT (make sources)"
mkdir -p "$bld/tplg"
m4 -I "$ART" -I "$UD/packages/audio-topology" "$UD/packages/audio-topology/XIAOMI-DITING.m4" > "$bld/tplg/XIAOMI-DITING.conf"
alsatplg -c "$bld/tplg/XIAOMI-DITING.conf" -o "$bld/tplg/XIAOMI-DITING-tplg.bin" 2>"$OUT/logs/tplg.log" ||
	{ cat "$OUT/logs/tplg.log"; die "alsatplg failed"; }
echo "tplg/XIAOMI-DITING-tplg.bin usr/lib/firmware/qcom/sm8450" >> "$bld/debian/install"

cat > "$bld/debian/changelog" <<C
device-xiaomi-diting ($PKG_VERSION) $UBUNTU_SUITE; urgency=medium

  * Local build for kernel $KERNEL_RELEASE.

 -- ubuntu-diting local build <ubuntu-diting@localhost>  $(date -R -d "$KERNEL_RELEASE_DATE")
C

log "building device-xiaomi-diting $PKG_VERSION"
# hosts without a dpkg database (openSUSE): empty one, no build-dependency check
nodeps=()
if [ ! -f /var/lib/dpkg/status ]; then
	mkdir -p "$WORK/dpkg-admin" && : > "$WORK/dpkg-admin/status"
	nodeps=(-d --admindir="$WORK/dpkg-admin")
fi
(cd "$bld" && dpkg-buildpackage -b -us -uc "${nodeps[@]}" > "$OUT/logs/device-pkg-build.log" 2>&1) ||
	{ tail -30 "$OUT/logs/device-pkg-build.log"; die "dpkg-buildpackage failed"; }
mv "$WORK/pkg/device-xiaomi-diting_${PKG_VERSION}_all.deb" "$OUT/debs/"
log "wrote $OUT/debs/device-xiaomi-diting_${PKG_VERSION}_all.deb"
