#!/bin/bash
# Build the sensor clients as local Debian packages: libssc-diting (QMI
# client library for the Qualcomm sensor core on the SLPI) and Ubuntu's
# iio-sensor-proxy packaging on upstream 3.9 with SSC support. Builds
# natively in a throwaway copy of the arm64 rootfs (as build-phoc.sh).
. "$(dirname "$0")/lib.sh"
need rsync git

ROOTFS="$WORK/rootfs"
CH="$WORK/sensors-chroot"
[ -x "$ROOTFS/usr/bin/apt-get" ] || die "no rootfs in $ROOTFS; run make rootfs first"
[ "$(uname -m)" = aarch64 ] || die "native arm64 build host required"
for r in libssc:$LIBSSC_COMMIT iio-sensor-proxy:$IIO_SENSOR_PROXY_COMMIT; do
	[ "$(git -C "$DITING_TOP/references/${r%%:*}" rev-parse HEAD 2>/dev/null)" = "${r#*:}" ] ||
		die "need references/${r%%:*} at ${r#*:} (make sources)"
done

cleanup() {
	for m in dev/pts dev proc sys; do sudo umount "$CH/$m" 2>/dev/null || true; done
}
trap cleanup EXIT

log "preparing build chroot $CH"
sudo rsync -a --delete "$ROOTFS/" "$CH/"
for m in proc sys dev dev/pts; do sudo mount --bind "/$m" "$CH/$m"; done
sudo cp /etc/resolv.conf "$CH/etc/resolv.conf"
sudo sed -i 's/^Types: deb$/Types: deb deb-src/' "$CH"/etc/apt/sources.list.d/ubuntu.sources
sudo rm -rf "$CH/build" && sudo mkdir -p "$CH/build/libssc" "$CH/build/iio-sensor-proxy-3.9"
git -C "$DITING_TOP/references/libssc" archive HEAD | sudo tar -x -C "$CH/build/libssc"
git -C "$DITING_TOP/references/iio-sensor-proxy" archive HEAD | sudo tar -x -C "$CH/build/iio-sensor-proxy-3.9"

inch() { sudo chroot "$CH" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
	LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"; }

inch apt-get update -qq
inch apt-get -y build-dep iio-sensor-proxy
inch apt-get -y install --no-install-recommends dpkg-dev devscripts meson ninja-build \
	pkgconf libqmi-glib-dev libprotobuf-c-dev protobuf-c-compiler protobuf-compiler \
	python3-protobuf python3-dev

# libssc: runtime library package with shlibs, headers only in the chroot
LIBSSC_VERSION="0.4.4+git$(git -C "$DITING_TOP/references/libssc" show -s --format=%cd --date=format:%Y%m%d HEAD).$(git -C "$DITING_TOP/references/libssc" rev-parse --short=7 HEAD)-1"
log "building libssc $LIBSSC_COMMIT"
inch sh -ec "
	cd /build/libssc
	meson setup --prefix=/usr --libdir=lib/aarch64-linux-gnu --buildtype=release build
	ninja -C build
	DESTDIR=/build/libssc-root meson install -C build
	cd /build/libssc-root
	so=\$(cd usr/lib/aarch64-linux-gnu && ls libssc.so.* | sort | head -1)
	soname=\$(objdump -p usr/lib/aarch64-linux-gnu/\$so | awk '/SONAME/ {print \$2}')
	mkdir -p /build/pkg/DEBIAN /build/pkg/usr/lib/aarch64-linux-gnu /build/pkg/usr/share/doc/libssc-diting
	cp -a usr/lib/aarch64-linux-gnu/libssc.so.* /build/pkg/usr/lib/aarch64-linux-gnu/
	[ ! -d usr/bin ] || cp -a usr/bin /build/pkg/usr/
	cp /build/libssc/LICENSE /build/pkg/usr/share/doc/libssc-diting/copyright
	echo '$LIBSSC_URL $LIBSSC_COMMIT' > /build/pkg/usr/share/doc/libssc-diting/SOURCE
	echo \"libssc \${soname#libssc.so.} libssc-diting (>= $LIBSSC_VERSION)\" > /build/pkg/DEBIAN/shlibs
	printf 'activate-noawait ldconfig\n' > /build/pkg/DEBIAN/triggers
	mkdir -p /build/shl/debian
	printf 'Source: libssc\\n\\nPackage: libssc-diting\\nArchitecture: arm64\\n' > /build/shl/debian/control
	deps=\$(cd /build/shl && dpkg-shlibdeps -O -xlibssc-diting /build/pkg/usr/lib/aarch64-linux-gnu/libssc.so.* /build/pkg/usr/bin/* | sed 's/^shlibs:Depends=//')
	[ -n \"\$deps\" ]
	cat > /build/pkg/DEBIAN/control <<C
Package: libssc-diting
Version: $LIBSSC_VERSION
Architecture: arm64
Maintainer: ubuntu-diting local build <ubuntu-diting@localhost>
Depends: \$deps
Provides: libssc
Section: libs
Priority: optional
Homepage: $LIBSSC_URL
Description: Qualcomm Snapdragon Sensor Core client library (local build)
 libssc at commit ${LIBSSC_COMMIT:0:12}: talks QMI over QRTR to the sensor
 core on the SLPI (accelerometer, compass, light, proximity, ...). Used by
 iio-sensor-proxy on the Xiaomi diting.
C
	mkdir -p /build/debs
	dpkg-deb --root-owner-group -Zxz --build /build/pkg /build/debs/libssc-diting_${LIBSSC_VERSION}_arm64.deb
	dpkg -i /build/debs/libssc-diting_${LIBSSC_VERSION}_arm64.deb
	cp -a usr/include/. /usr/include/
	ln -sf \$soname /usr/lib/aarch64-linux-gnu/libssc.so
	cp -a usr/lib/aarch64-linux-gnu/pkgconfig/. /usr/lib/aarch64-linux-gnu/pkgconfig/
"

# iio-sensor-proxy: Ubuntu's packaging on upstream 3.9, with SSC support
log "building iio-sensor-proxy 3.9 with SSC support"
# shellcheck disable=SC2016 # expanded inside the chroot
inch sh -ec '
	cd /build
	apt-get source --download-only iio-sensor-proxy
	mkdir ubuntu && tar -xf iio-sensor-proxy_*.debian.tar.* -C ubuntu
	cp -a ubuntu/debian iio-sensor-proxy-3.9/
	cd iio-sensor-proxy-3.9
	# patches of the Ubuntu 3.8 package that 3.9 does not need
	if [ -s debian/patches/series ]; then
		for p in $(cat debian/patches/series); do
			patch -p1 -N --dry-run -s < debian/patches/$p >/dev/null 2>&1 || {
				echo "dropping debian/patches/$p"; sed -i "\|^$p\$|d" debian/patches/series; }
		done
	fi
	grep -q "ssc-support" debian/rules || printf "\noverride_dh_auto_configure:\n\tdh_auto_configure -- -Dssc-support=enabled\n" >> debian/rules
	sed -i "s/^Build-Depends:/Build-Depends: libssc-diting,/" debian/control
	DEBFULLNAME="ubuntu-diting local build" DEBEMAIL="ubuntu-diting@localhost" \
		dch -v 3.9-0diting1 -D resolute "Upstream 3.9 with Qualcomm SSC (libssc) support."
	dpkg-buildpackage -b -us -uc -d
'
mkdir -p "$OUT/debs"
rm -f "$OUT"/debs/libssc-diting_*.deb "$OUT"/debs/iio-sensor-proxy_*diting*.deb
cp "$CH"/build/debs/libssc-diting_*_arm64.deb "$CH"/build/iio-sensor-proxy_*diting1_arm64.deb "$OUT/debs/"
log "wrote $OUT/debs/libssc-diting_${LIBSSC_VERSION}_arm64.deb and iio-sensor-proxy_3.9-0diting1_arm64.deb"
