#!/bin/bash
# Rebuild Ubuntu's phosh with the patches in packages/phosh/
# in the arm64 buildd chroot (lib-buildd.sh). The source comes from the
# Ubuntu archive with apt-get source, verified against the signed Sources
# index. Needs sudo.
#
#   0001: keep the screen off after a wake-up without user input
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-buildd.sh"

PH_VERSION="${PHOSH_VERSION:-0.54.0-1}"
LOCAL_SUFFIX="diting1"
PKG="$UD/packages/phosh"

buildd_setup
# source packages for apt-get source
sudo sed -i 's/^Types: deb$/Types: deb deb-src/' "$CH/etc/apt/sources.list.d/ubuntu.sources"
inch apt-get update -qq
inch apt-get -y -q install --no-install-recommends dpkg-dev devscripts quilt > /dev/null

log "fetching phosh $PH_VERSION source"
sudo rm -rf "$CH/build" && sudo mkdir -p "$CH/build"
inch sh -ec "cd /build && apt-get source -q --only-source phosh=$PH_VERSION" > /dev/null
src=$(cd "$CH/build" && ls -d phosh-*/)
src="/build/${src%/}"

log "adding $(ls "$PKG"/*.patch | wc -l) patch(es)"
sudo mkdir -p "$CH$src/debian/patches"
for p in "$PKG"/*.patch; do
	sudo cp "$p" "$CH$src/debian/patches/"
	basename "$p" | sudo tee -a "$CH$src/debian/patches/series" > /dev/null
done
inch sh -ec "cd $src && QUILT_PATCHES=debian/patches quilt push -a -q > /dev/null && quilt pop -a -q > /dev/null"
inch sh -ec "cd $src && DEBFULLNAME='ubuntu-diting local build' DEBEMAIL=ubuntu-diting@localhost \
	dch -v ${PH_VERSION}${LOCAL_SUFFIX} -D $UBUNTU_SUITE --force-distribution \
	'Local Diting build: keep the screen off after a wake-up without user input.'"

log "installing build dependencies"
inch sh -ec "cd $src && apt-get -y -q build-dep --no-install-recommends ." > /dev/null
mkdir -p "$OUT/logs" "$OUT/debs"
log "building (log: $OUT/logs/phosh-build.log)"
inch sh -ec "cd $src && DEB_BUILD_OPTIONS='nocheck noddebs parallel=$(nproc)' dpkg-buildpackage -b -us -uc" \
	> "$OUT/logs/phosh-build.log" 2>&1 ||
	{ tail -30 "$OUT/logs/phosh-build.log"; die "dpkg-buildpackage failed"; }
cp "$CH"/build/*.deb "$OUT/debs/"
log "wrote: $(cd "$CH/build" && ls ./*.deb | tr '\n' ' ')"
