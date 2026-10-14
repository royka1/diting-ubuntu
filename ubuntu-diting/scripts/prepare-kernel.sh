#!/bin/bash
# Export the locked stable commit (no .git, so no SCM suffix in the release
# string) and apply kernel/patches into work/kernel-src.
#
# Incremental: the patched tree is built in a scratch directory and synced
# into work/kernel-src by checksum, so only files whose content changed get
# a new mtime and make rebuilds just what they affect. Kernel objects are
# wiped only when kernel.lock changes. ('make repro-check' verifies that an
# incremental result equals a from-scratch build.)
. "$(dirname "$0")/lib.sh"
need git patch rsync

[ -d "$KERNEL_GIT/.git" ] || die "no kernel checkout; run 'make sources'"
git -C "$KERNEL_GIT" cat-file -e "$KERNEL_COMMIT^{commit}" ||
	die "locked commit $KERNEL_COMMIT missing; run 'make sources'"

digest="$(patches_digest)"
if [ -f "$KERNEL_SRC/.diting-stamp" ] && [ "$(cat "$KERNEL_SRC/.diting-stamp")" = "$digest" ]; then
	log "kernel source up to date ($KERNEL_VERSION + $(find "$KERNEL_PATCHES" -name '*.patch' | wc -l) patches)"
	exit 0
fi

lock_digest="$(sha256_of "$UD/config/kernel.lock")"
if [ -f "$KERNEL_OBJ/.diting-lock-stamp" ] && [ "$(cat "$KERNEL_OBJ/.diting-lock-stamp")" != "$lock_digest" ]; then
	log "kernel.lock changed: discarding old kernel objects"
	rm -rf "$KERNEL_OBJ"
fi

new="$WORK/kernel-src.new"
rm -rf "$new"
mkdir -p "$new"
log "exporting $KERNEL_TAG ($KERNEL_COMMIT)"
git -C "$KERNEL_GIT" archive --format=tar "$KERNEL_COMMIT" | tar -x -C "$new"
for p in "$KERNEL_PATCHES"/*.patch; do
	log "applying $(basename "$p")"
	patch -d "$new" -p1 --quiet --no-backup-if-mismatch < "$p"
done

mkdir -p "$KERNEL_SRC"
changed="$(rsync -rlpc --delete --exclude=/.diting-stamp --out-format='%n' "$new/" "$KERNEL_SRC/" | grep -v '/$' || true)"
rm -rf "$new"
[ -z "$changed" ] || log "changed source files: $(echo "$changed" | wc -l) ($(echo "$changed" | head -5 | tr '\n' ' '))"
echo "$digest" > "$KERNEL_SRC/.diting-stamp"
mkdir -p "$KERNEL_OBJ"
echo "$lock_digest" > "$KERNEL_OBJ/.diting-lock-stamp"
