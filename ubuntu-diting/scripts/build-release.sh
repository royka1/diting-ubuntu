#!/bin/bash
# Pack a public release from the public rootfs (ROOTFS_PROFILE=public
# build-rootfs.sh): the boot images that the kernel package generated inside
# it, the root filesystem as an Android sparse image, the flash script and
# checksums, compressed and split into parts small enough for GitHub
# release assets.
#
#   build-release.sh [NAME]     (default ubuntu-diting-<date>)
. "$(dirname "$0")/lib.sh"
need img2simg xz sha256sum split

ROOT="$WORK/rootfs-public"
IMG="$OUT/ubuntu-diting-rootfs-$UBUNTU_SUITE-arm64-public.img"
NAME="${1:-ubuntu-diting-$(date -u +%Y%m%d)}"
REL="$OUT/release"
DIR="$REL/$NAME"
PART_SIZE="${RELEASE_PART_SIZE:-1900M}"

[ -f "$IMG" ] || die "missing $IMG (ROOTFS_PROFILE=public make rootfs)"
[ -f "$ROOT/etc/diting-build" ] || die "missing $ROOT (public rootfs tree)"
boot="$ROOT/boot/diting/boot-$KERNEL_RELEASE.img"
vboot="$ROOT/boot/diting/vendor_boot-$KERNEL_RELEASE.img"
[ -f "$boot" ] && [ -f "$vboot" ] || die "no boot images for $KERNEL_RELEASE in $ROOT/boot/diting"

log "checking the boot images"
if [ -d "$DEVICE_DATA/images" ]; then
	"$UD/scripts/verify-boot-image.sh" "$boot" "$vboot" || die "boot image check failed"
else
	warn "no stock images in $DEVICE_DATA/images: header comparison skipped"
fi
grep -q "root=PARTLABEL=userdata" <<<"$(python3 "$UD/scripts/bootimg_info.py" "$vboot")" ||
	die "vendor_boot command line does not mount userdata"

rm -rf "$DIR" && mkdir -p "$DIR"
cp "$boot" "$DIR/boot.img"
cp "$vboot" "$DIR/vendor_boot.img"
log "sparse image of $IMG"
img2simg "$IMG" "$DIR/rootfs.img"
cp "$UD/release/flash-diting.sh" "$UD/release/INSTALL.md" "$DIR/"
cp "$ROOT/etc/diting-build" "$DIR/BUILD-INFO"
cp "$OUT/rootfs-packages-$UBUNTU_SUITE-public.tsv" "$DIR/PACKAGES.tsv"
(cd "$DIR" && sha256sum boot.img vendor_boot.img rootfs.img flash-diting.sh > SHA256SUMS)

log "compressing (xz) and splitting into $PART_SIZE parts"
rm -f "$REL/$NAME".tar.xz*
tar -C "$REL" -cf - "$NAME" | xz -T0 -6 | split -b "$PART_SIZE" -d -a 3 - "$REL/$NAME.tar.xz."
parts=("$REL/$NAME".tar.xz.*)
if [ ${#parts[@]} -eq 1 ]; then mv "${parts[0]}" "$REL/$NAME.tar.xz"; fi
(cd "$REL" && sha256sum "$NAME".tar.xz* > "$NAME.SHA256SUMS")
ls -la "$REL/$NAME".tar.xz* "$REL/$NAME.SHA256SUMS"
log "release in $REL (directory $NAME, archive $NAME.tar.xz*)"
