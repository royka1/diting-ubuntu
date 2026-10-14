#!/bin/bash
# Shared helpers for the Diting build scripts. Source, do not execute.
# shellcheck disable=SC2034

set -euo pipefail

DITING_TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UD="$DITING_TOP/ubuntu-diting"
WORK="${WORK:-$UD/work}"
OUT="${OUT:-$UD/output}"
KERNEL_DIR="$DITING_TOP/kernel"
KERNEL_GIT="$KERNEL_DIR/upstream"
KERNEL_PATCHES="$KERNEL_DIR/patches"
KERNEL_FRAGMENT="$KERNEL_DIR/config/diting.config"
DEVICE_DATA="$DITING_TOP/device-data"

# shellcheck source=../config/diting.conf
. "$UD/config/diting.conf"
# shellcheck source=../config/kernel.lock
. "$UD/config/kernel.lock"

KERNEL_SRC="$WORK/kernel-src"
KERNEL_OBJ="$WORK/kernel-obj"
KERNEL_RELEASE="${KERNEL_VERSION}${KERNEL_LOCALVERSION}"
JOBS="${JOBS:-$(nproc)}"
# depmod and friends live in sbin, which is not in a user PATH on some hosts
case ":$PATH:" in *:/usr/sbin:*) ;; *) PATH="$PATH:/usr/sbin:/sbin" ;; esac
if [ "$(uname -m)" != aarch64 ] && [ -z "${CROSS_COMPILE:-}" ]; then
	# Debian/Ubuntu name first, then openSUSE's cross-aarch64-gcc*
	for p in aarch64-linux-gnu- aarch64-suse-linux-; do
		if command -v "${p}gcc" >/dev/null; then CROSS_COMPILE=$p; break; fi
	done
	CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
fi

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
	local t
	for t in "$@"; do
		command -v "$t" >/dev/null 2>&1 || die "missing host tool: $t (see docs/BUILD.md)"
	done
}

# The CIX P1 build host (edge kernel 7.1.8) corrupts compiler memory under
# parallel load when transparent huge pages are used: 6/72 vs 0/72 crashing
# parallel compiles (docs/BUILD.md). Run builds with THP disabled per
# process via prctl; this does not change any host setting.
NOTHP=""
if [ "${DITING_NOTHP:-1}" = 1 ]; then
	NOTHP="$WORK/tools/nothp-$(uname -m)"
	if [ ! -x "$NOTHP" ] || [ "$DITING_TOP/tools/src/nothp.c" -nt "$NOTHP" ]; then
		mkdir -p "$WORK/tools"
		cc -O2 -Wall -o "$NOTHP" "$DITING_TOP/tools/src/nothp.c"
	fi
fi

# Re-run the calling script under nothp so that all its children (make,
# gcc, dpkg, debootstrap in the chroot) run without THP.
# Only for real script files; when sourced from an interactive or "bash -c"
# shell, $0 is the shell itself (wrap such calls with work/tools/nothp).
if [ -n "$NOTHP" ] && [ -f "$0" ] && [ "${0##*.}" = sh ] &&
	grep -q '^THP_enabled:[[:space:]]*1' /proc/self/status 2>/dev/null; then
	exec "$NOTHP" "$0" "$@"
fi

# Run make for the kernel with a fixed, reproducible environment.
kmake() {
	make -C "$KERNEL_SRC" O="$KERNEL_OBJ" ARCH=arm64 \
		${CROSS_COMPILE:+CROSS_COMPILE="$CROSS_COMPILE"} \
		KBUILD_BUILD_USER=diting KBUILD_BUILD_HOST=ubuntu-diting \
		KBUILD_BUILD_TIMESTAMP="$KERNEL_RELEASE_DATE" \
		KBUILD_BUILD_VERSION="$KERNEL_DEB_REVISION" \
		LOCALVERSION= -j"$JOBS" "$@"
}

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

# Patch-series fingerprint, used to detect stale kernel source/objects.
patches_digest() {
	cat "$KERNEL_PATCHES"/*.patch "$KERNEL_FRAGMENT" "$UD/config/kernel.lock" | sha256sum | cut -d' ' -f1
}

# Write the boot layout subset of diting.conf used by diting-mkbootimg.
write_bootimg_conf() {
	local v
	{
		echo "# Generated from ubuntu-diting/config/diting.conf"
		for v in BOOT_HEADER_VERSION BOOT_PAGESIZE BOOT_OS_VERSION BOOT_OS_PATCH_LEVEL \
			VENDOR_BOOT_BASE VENDOR_BOOT_KERNEL_OFFSET VENDOR_BOOT_RAMDISK_OFFSET \
			VENDOR_BOOT_TAGS_OFFSET VENDOR_BOOT_DTB_OFFSET BOOT_PARTITION_SIZE \
			VENDOR_BOOT_PARTITION_SIZE ABL_MSM_ID ABL_BOARD_ID ABL_SPLASH_ADDR BOOT_CMDLINE_BASE KERNEL_DTB; do
			printf '%s="%s"\n' "$v" "${!v}"
		done
	} > "$1"
}
