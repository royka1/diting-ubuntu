#!/bin/bash
# Rebuild Ubuntu's phoc with the patches in packages/phoc/ as a local Debian
# package. Builds natively in a throwaway copy of the arm64 rootfs (the build
# host must be arm64; no emulation). Needs sudo for the chroot.
. "$(dirname "$0")/lib.sh"
need rsync

ROOTFS="$WORK/rootfs"
CH="$WORK/phoc-chroot"
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
sudo cp "$UD"/packages/phoc/*.patch "$CH/build/patches/"

inch() { sudo chroot "$CH" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
	LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"; }

inch apt-get update -qq
inch apt-get -y build-dep phoc
inch apt-get -y install --no-install-recommends dpkg-dev devscripts quilt
inch sh -ec '
	cd /build
	apt-get source phoc
	cd phoc-*/
	for p in /build/patches/*.patch; do
		cp "$p" debian/patches/
		echo "$(basename "$p")" >> debian/patches/series
	done
	QUILT_PATCHES=debian/patches quilt push -a
	ver="$(dpkg-parsechangelog -S Version)diting1"
	DEBFULLNAME="ubuntu-diting local build" DEBEMAIL="ubuntu-diting@localhost" \
		dch -v "$ver" -D resolute "Honor non-preferred modes from output-management (refresh-rate switching)."
	dpkg-buildpackage -b -us -uc
'
mkdir -p "$OUT/debs"
cp "$CH"/build/phoc_*diting1_arm64.deb "$OUT/debs/"
log "wrote $(ls "$OUT"/debs/phoc_*diting1_arm64.deb)"
