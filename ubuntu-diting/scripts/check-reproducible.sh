#!/bin/bash
# Rebuild the kernel from scratch at the same object path (debug info and
# build-ids embed it) and compare the Image, DTB and every module with the
# main build, which is moved aside meanwhile and restored afterwards. Detects silent miscompiles on an
# unreliable build host (see docs/BUILD.md). Slow: a full second build.
. "$(dirname "$0")/lib.sh"
[ -f "$KERNEL_OBJ/arch/arm64/boot/Image" ] || die "run 'make kernel' first"
main="$WORK/kernel-obj.main"
check="$WORK/kernel-obj.check"
log="$OUT/logs/kernel-repro.log"
rm -rf "$check"
[ ! -e "$main" ] || die "$main exists (interrupted run?); restore it to $KERNEL_OBJ first"
mv "$KERNEL_OBJ" "$main"
restore() {
	[ -d "$main" ] || return 0
	[ -d "$KERNEL_OBJ" ] && mv "$KERNEL_OBJ" "$check"
	mv "$main" "$KERNEL_OBJ"
	rm -rf "$check"
}
trap restore EXIT
mkdir -p "$KERNEL_OBJ"
cp "$main/.config" "$KERNEL_OBJ/.config"
kmake olddefconfig > "$log" 2>&1
for attempt in 1 2 3 4 5; do
	mark=$(wc -l < "$log")
	if kmake Image modules dtbs >> "$log" 2>&1; then break; fi
	tail -n +"$mark" "$log" | grep -q 'internal compiler error' || { tail -30 "$log"; die "check build failed"; }
	warn "compiler crash during check build, retry $attempt"
	[ "$attempt" = 5 ] && die "check build kept crashing the compiler"
done

diffs=0 total=0
while IFS= read -r f; do
	total=$((total + 1))
	if ! cmp -s "$main/$f" "$KERNEL_OBJ/$f"; then
		echo "DIFFERS: $f"
		diffs=$((diffs + 1))
	fi
done < <(cd "$main" && { echo arch/arm64/boot/Image; echo "arch/arm64/boot/dts/$KERNEL_DTB"; find . -path ./debian -prune -o \( -name '*.ko' -o -name '*.o' \) -printf '%P\n'; } | sort)
echo "compared $total files, $diffs differ" | tee -a "$log"
if [ "$diffs" != 0 ]; then
	# Keep the second tree for analysis instead of deleting it.
	trap - EXIT
	mv "$KERNEL_OBJ" "$WORK/kernel-obj.check-kept"
	mv "$main" "$KERNEL_OBJ"
	die "builds differ (second tree kept in work/kernel-obj.check-kept): do not use these binaries"
fi
log "reproducible: Image, DTB, all modules and objects identical in two independent builds"
