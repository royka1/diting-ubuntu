#!/bin/bash
# Build Image, DTBs, modules and Debian packages (bindeb-pkg) for Diting.
. "$(dirname "$0")/lib.sh"
need make gcc bc flex bison dpkg-deb

"$UD/scripts/prepare-kernel.sh"
mkdir -p "$KERNEL_OBJ" "$OUT/kernel" "$OUT/debs" "$OUT/logs"
log="$OUT/logs/kernel-build.log"

{
	echo "# kernel build $(date -u +%FT%TZ)"
	echo "# $("${CROSS_COMPILE:-}gcc" --version | head -1)"
	echo "# $(ld --version | head -1)"
} > "$log"

kmake defconfig >> "$log" 2>&1
"$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -O "$KERNEL_OBJ" \
	"$KERNEL_OBJ/.config" "$KERNEL_FRAGMENT" >> "$log" 2>&1
kmake olddefconfig >> "$log" 2>&1

# Every option of the fragment must survive olddefconfig.
missing=0
while IFS= read -r line; do
	case "$line" in
	CONFIG_*=*) grep -qxF "$line" "$KERNEL_OBJ/.config" || { warn "fragment option lost: $line"; missing=1; } ;;
	"# CONFIG_"*" is not set") grep -qxF "$line" "$KERNEL_OBJ/.config" || { warn "fragment option lost: $line"; missing=1; } ;;
	esac
done < "$KERNEL_FRAGMENT"
[ "$missing" = 0 ] || die "config fragment not fully applied"

kmake prepare >> "$log" 2>&1
release="$(kmake -s kernelrelease)"
[ "$release" = "$KERNEL_RELEASE" ] || die "kernelrelease '$release' != expected '$KERNEL_RELEASE'"
log "building $release (log: $log)"

# The build host showed sporadic, non-reproducible GCC internal compiler
# errors under load (docs/BUILD.md). Make only rebuilds failed objects, so
# retry a few times when, and only when, the failure is an ICE.
for attempt in 1 2 3 4 5; do
	mark=$(wc -l < "$log")
	if kmake Image modules dtbs >> "$log" 2>&1; then break; fi
	if ! tail -n +"$mark" "$log" | grep -q 'internal compiler error'; then
		tail -40 "$log"; die "kernel build failed"
	fi
	warn "compiler crash (host instability), retry $attempt"
	echo "# retry after ICE: $(tail -n +"$mark" "$log" | grep 'internal compiler error' | head -3)" >> "$OUT/logs/kernel-ice.log"
	[ "$attempt" = 5 ] && die "kernel build kept crashing the compiler"
done
[ -f "$KERNEL_OBJ/arch/arm64/boot/dts/$KERNEL_DTB" ] || die "$KERNEL_DTB was not built"

log "packaging (bindeb-pkg)"
rm -f "$WORK"/linux-*.deb "$WORK"/linux-upstream_* "$WORK"/linux-*.buildinfo "$WORK"/linux-*.changes
# Non-Debian build hosts (e.g. openSUSE) have no dpkg database for
# dpkg-checkbuilddeps; the tools the build needs are checked above.
dpkg_flags=()
# An empty admin dir lets dpkg-genbuildinfo run (it lists no installed
# packages then).
if [ ! -f /var/lib/dpkg/status ]; then
	mkdir -p "$WORK/tools/dpkg-admin/updates"
	: > "$WORK/tools/dpkg-admin/status"
	dpkg_flags=(DPKG_FLAGS="-d --admindir=$WORK/tools/dpkg-admin")
fi
# Cross builds: the headers package compiles its scripts for arm64, which
# needs an arm64 libc that kernel-only cross compilers lack. The phone only
# installs linux-image, so skip linux-headers there.
if [ -n "${CROSS_COMPILE:-}" ]; then
	export DEB_BUILD_PROFILES="${DEB_BUILD_PROFILES:+$DEB_BUILD_PROFILES }pkg.linux-diting.nokernelheaders"
	log "cross build: linux-headers package skipped"
fi
# The package keeps modules in /lib/modules (as all earlier revisions did).
# A host kmod built for /usr/lib/modules (openSUSE) needs -m for that.
depmod_var=()
if [ "$(pkg-config --variable=module_directory kmod 2>/dev/null || echo /lib/modules)" != /lib/modules ]; then
	mkdir -p "$WORK/tools"
	printf '#!/bin/sh\nexec depmod -m /lib/modules "$@"\n' > "$WORK/tools/depmod-lib-modules"
	chmod +x "$WORK/tools/depmod-lib-modules"
	depmod_var=(DEPMOD="$WORK/tools/depmod-lib-modules")
fi
kmake bindeb-pkg "${dpkg_flags[@]}" "${depmod_var[@]}" KDEB_PKGVERSION="$KERNEL_VERSION-$KERNEL_DEB_REVISION" \
	KDEB_SOURCENAME=linux-diting KDEB_CHANGELOG_DIST="$UBUNTU_SUITE" \
	DEBEMAIL="ubuntu-diting@localhost" DEBFULLNAME="ubuntu-diting build" >> "$log" 2>&1 ||
	{ tail -40 "$log"; die "bindeb-pkg failed"; }

rm -f "$OUT"/debs/linux-*.deb
mv "$WORK"/linux-*.deb "$OUT/debs/"
cp "$KERNEL_OBJ/arch/arm64/boot/Image" "$OUT/kernel/Image-$release"
cp "$KERNEL_OBJ/arch/arm64/boot/dts/$KERNEL_DTB" "$OUT/kernel/"
cp "$KERNEL_OBJ/.config" "$OUT/kernel/config-$release"
cp "$KERNEL_OBJ/System.map" "$OUT/kernel/System.map-$release"
log "kernel $release done:"
for d in "$OUT"/debs/linux-*.deb; do log "  $(basename "$d")"; done
