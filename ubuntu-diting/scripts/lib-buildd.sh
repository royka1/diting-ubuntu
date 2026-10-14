# shellcheck shell=bash
# arm64 buildd chroot of the configured Ubuntu suite for building local
# Debian packages: natively on arm64, under qemu-user (binfmt) elsewhere.
# Source after lib.sh; needs sudo. Provides $CH, buildd_setup, inch.
command -v debootstrap >/dev/null || [ -x /usr/sbin/debootstrap ] || die "missing host tool: debootstrap"
CH="$WORK/build-chroot-$UBUNTU_SUITE-arm64"
if [ "$(uname -m)" != aarch64 ] && [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
	die "arm64 emulation (qemu-user binfmt) not registered; see docs/BUILD.md"
fi

buildd_cleanup() {
	for m in dev/pts dev proc sys; do sudo umount "$CH/$m" 2>/dev/null || true; done
}

buildd_setup() {
	trap buildd_cleanup EXIT
	if [ ! -x "$CH/usr/bin/dpkg-buildpackage" ]; then
		log "creating arm64 build chroot $CH"
		sudo rm -rf "$CH"
		sudo /usr/sbin/debootstrap --arch=arm64 --variant=buildd --keyring="$UBUNTU_KEYRING" \
			"$UBUNTU_SUITE" "$CH" "$UBUNTU_MIRROR"
	fi
	for m in proc sys dev dev/pts; do
		mountpoint -q "$CH/$m" || sudo mount --bind "/$m" "$CH/$m"
	done
	sudo cp /etc/resolv.conf "$CH/etc/resolv.conf"
	# debootstrap only enables main; build dependencies are in universe
	sudo rm -f "$CH/etc/apt/sources.list"
	sudo tee "$CH/etc/apt/sources.list.d/ubuntu.sources" > /dev/null <<S
Types: deb
URIs: $UBUNTU_MIRROR
Suites: $UBUNTU_SUITE $UBUNTU_SUITE-updates $UBUNTU_SUITE-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
S
	inch apt-get update -qq
}

inch() { sudo chroot "$CH" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
	LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"; }

# buildd_build <source dir> <log name> <build deps...>: dpkg-buildpackage -b
# in the chroot; the .debs land in $OUT/debs
buildd_build() {
	local src="$1" name="$2"; shift 2
	sudo rm -rf "$CH/build" && sudo mkdir -p "$CH/build"
	sudo cp -a "$src" "$CH/build/$name"
	inch apt-get -y -q install --no-install-recommends debhelper "$@" > /dev/null
	mkdir -p "$OUT/logs" "$OUT/debs"
	inch sh -ec "cd /build/$name && dpkg-buildpackage -b -us -uc" \
		> "$OUT/logs/$name-build.log" 2>&1 ||
		{ tail -30 "$OUT/logs/$name-build.log"; die "dpkg-buildpackage failed (log: $OUT/logs/$name-build.log)"; }
	cp "$CH"/build/*.deb "$OUT/debs/"
	log "wrote: $(cd "$CH/build" && ls ./*.deb | tr '\n' ' ')"
}
