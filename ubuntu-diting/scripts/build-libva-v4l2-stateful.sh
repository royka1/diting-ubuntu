#!/bin/bash
# Build the VA-API driver for the iris video decoder (libva-v4l2-stateful,
# upstream commit below plus packages/libva-v4l2-stateful/*.patch) as a local
# Debian package, in the arm64 buildd chroot (lib-buildd.sh). Needs sudo.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-buildd.sh"
need git rsync

UPSTREAM="$DITING_TOP/references/libva-v4l2-stateful"
UPSTREAM_COMMIT="$LIBVA_V4L2_COMMIT"
PKG="$UD/packages/libva-v4l2-stateful"

[ -d "$UPSTREAM/.git" ] || die "missing $UPSTREAM (make sources)"
git -C "$UPSTREAM" cat-file -e "$UPSTREAM_COMMIT^{commit}" ||
	die "upstream commit $UPSTREAM_COMMIT not in $UPSTREAM"

log "preparing source (upstream ${UPSTREAM_COMMIT:0:7} + $(ls "$PKG"/*.patch | wc -l) patch(es))"
src="$WORK/libva-v4l2-stateful-pkg"
rm -rf "$src" && mkdir -p "$src"
git -C "$UPSTREAM" archive --format=tar "$UPSTREAM_COMMIT" | tar -x -C "$src"
rm -rf "$src/debian"
cp -a "$PKG/debian" "$src/debian"
mkdir -p "$src/debian/patches"
for p in "$PKG"/*.patch; do
	cp "$p" "$src/debian/patches/"
	basename "$p" >> "$src/debian/patches/series"
done

buildd_setup
buildd_build "$src" libva-v4l2-stateful meson pkgconf libva-dev libdrm-dev libgbm-dev quilt
