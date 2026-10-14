#!/bin/bash
# Regenerate the Ubuntu initramfs for the Diting kernel inside the rootfs
# with initramfs-tools (also triggers the diting boot image hook there).
. "$(dirname "$0")/lib.sh"
[ "$(id -u)" = 0 ] || die "needs root"
ROOT="$WORK/rootfs"
[ -d "$ROOT/lib/modules/$KERNEL_RELEASE" ] || die "kernel not installed in rootfs; run 'make rootfs'"
for m in proc sys dev; do mount --bind "/$m" "$ROOT/$m"; done
trap 'for m in dev sys proc; do umount -l "$ROOT/$m" || true; done' EXIT
chroot "$ROOT" update-initramfs -u -k "$KERNEL_RELEASE"
