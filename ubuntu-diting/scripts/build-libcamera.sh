#!/bin/bash
# Rebuild Ubuntu's libcamera with the patches in packages/libcamera/ (sensor
# support for the diting cameras) as local Debian packages. Builds natively
# in a throwaway copy of the arm64 rootfs (as build-phoc.sh). The IPA
# modules are signed at build time, so all libcamera binary packages of one
# build belong together.
#
# On the CIX build host this C++ build crashed gcc three times in a row
# (internal compiler errors, 2026-10-13) even with THP disabled; the same
# source/patches built cleanly natively on the phone (dpkg-source -x,
# mk-build-deps, dpkg-buildpackage -b, ~10 min), see docs/BUILD.md.
. "$(dirname "$0")/lib.sh"
need rsync

ROOTFS="$WORK/rootfs"
CH="$WORK/libcamera-chroot"
[ -x "$ROOTFS/usr/bin/apt-get" ] || die "no rootfs in $ROOTFS; run make rootfs first"
[ "$(uname -m)" = aarch64 ] || die "native arm64 build host required"

cleanup() {
	for m in dev/pts dev proc sys; do sudo umount "$CH/$m" 2>/dev/null || true; done
}
trap cleanup EXIT

log "preparing build chroot $CH"
sudo rsync -a --delete "$ROOTFS/" "$CH/"
for m in proc sys dev dev/pts; do sudo mount --bind "/$m" "$CH/$m"; done
sudo cp /etc/resolv.conf "$CH/etc/resolv.conf"
sudo sed -i 's/^Types: deb$/Types: deb deb-src/' "$CH"/etc/apt/sources.list.d/ubuntu.sources
sudo rm -rf "$CH/build" && sudo mkdir -p "$CH/build/patches"
sudo cp "$UD"/packages/libcamera/*.patch "$CH/build/patches/"

inch() { sudo chroot "$CH" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
	LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"; }

inch apt-get update -qq
inch apt-get -y build-dep libcamera
inch apt-get -y install --no-install-recommends dpkg-dev devscripts quilt
# shellcheck disable=SC2016 # expanded inside the chroot
inch sh -ec '
	cd /build
	apt-get source libcamera
	cd libcamera-*/
	for p in /build/patches/*.patch; do
		cp "$p" debian/patches/
		echo "$(basename "$p")" >> debian/patches/series
	done
	QUILT_PATCHES=debian/patches quilt push -a
	ver="$(dpkg-parsechangelog -S Version)diting${LIBCAMERA_DITING_REV:-2}"
	DEBFULLNAME="ubuntu-diting local build" DEBEMAIL="ubuntu-diting@localhost" \
		dch -v "$ver" -D resolute "Diting camera support: S5K4H7 and S5KHP1 sensor helpers, software ISP focus control and contrast autofocus."
	DEB_BUILD_OPTIONS="nocheck parallel=${LIBCAMERA_JOBS:-6}" dpkg-buildpackage -b -us -uc
'
mkdir -p "$OUT/debs/libcamera"
rm -f "$OUT"/debs/libcamera/*.deb
cp "$CH"/build/*diting*_*.deb "$OUT/debs/libcamera/"
log "wrote $(find "$OUT/debs/libcamera" -name '*.deb' | wc -l) packages to $OUT/debs/libcamera"
