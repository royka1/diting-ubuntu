#!/bin/bash
# Rebuild Ubuntu's ModemManager with the patches in packages/modemmanager/
# (upstream fixes not yet in the archive version) as a local Debian package,
# in the arm64 buildd chroot (lib-buildd.sh). The source comes from the
# Ubuntu archive with apt-get source, verified against the signed Sources
# index. Needs sudo.
#
#   0001: netlink use-after-free (upstream 9317cbc4); ModemManager crashed
#         with SIGSEGV when it re-created the data link after a resume.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-buildd.sh"

MM_VERSION="${MODEMMANAGER_VERSION:-1.25.95-1ubuntu1}"
LOCAL_SUFFIX="diting1"
PKG="$UD/packages/modemmanager"

buildd_setup
# source packages for apt-get source
sudo sed -i 's/^Types: deb$/Types: deb deb-src/' "$CH/etc/apt/sources.list.d/ubuntu.sources"
inch apt-get update -qq
inch apt-get -y -q install --no-install-recommends dpkg-dev devscripts quilt > /dev/null

log "fetching modemmanager $MM_VERSION source"
sudo rm -rf "$CH/build" && sudo mkdir -p "$CH/build"
inch sh -ec "cd /build && apt-get source -q --only-source modemmanager=$MM_VERSION" > /dev/null
src=$(cd "$CH/build" && ls -d modemmanager-*/)
src="/build/${src%/}"

log "adding $(ls "$PKG"/*.patch | wc -l) patch(es)"
sudo mkdir -p "$CH$src/debian/patches"
for p in "$PKG"/*.patch; do
	sudo cp "$p" "$CH$src/debian/patches/"
	basename "$p" | sudo tee -a "$CH$src/debian/patches/series" > /dev/null
done
inch sh -ec "cd $src && QUILT_PATCHES=debian/patches quilt push -a -q > /dev/null && quilt pop -a -q > /dev/null"
inch sh -ec "cd $src && DEBFULLNAME='ubuntu-diting local build' DEBEMAIL=ubuntu-diting@localhost \
	dch -v ${MM_VERSION}${LOCAL_SUFFIX} -D $UBUNTU_SUITE --force-distribution \
	'Local Diting build: upstream netlink use-after-free fix (9317cbc4).'"

log "installing build dependencies"
inch sh -ec "cd $src && apt-get -y -q build-dep --no-install-recommends ." > /dev/null
mkdir -p "$OUT/logs" "$OUT/debs"
log "building (log: $OUT/logs/modemmanager-build.log)"
inch sh -ec "cd $src && DEB_BUILD_OPTIONS='nocheck noddebs parallel=$(nproc)' dpkg-buildpackage -b -us -uc" \
	> "$OUT/logs/modemmanager-build.log" 2>&1 ||
	{ tail -30 "$OUT/logs/modemmanager-build.log"; die "dpkg-buildpackage failed"; }
cp "$CH"/build/*.deb "$OUT/debs/"
log "wrote: $(cd "$CH/build" && ls ./*.deb | tr '\n' ' ')"
