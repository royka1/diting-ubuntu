#!/bin/bash
# Check host tools needed by the build (see docs/BUILD.md for packages).
. "$(dirname "$0")/lib.sh"
missing=()
for t in git gpg make gcc ld bc flex bison perl python3 dtc fdtput fdtget \
	mkbootimg unpack_bootimg dpkg-deb dpkg-buildpackage dh fakeroot \
	debootstrap chroot mkfs.ext4 e2fsck zstd lz4 cpio curl rsync; do
	command -v "$t" >/dev/null 2>&1 || [ -x "/usr/sbin/$t" ] || missing+=("$t")
done
[ -f "$UBUNTU_KEYRING" ] || missing+=("ubuntu-keyring ($UBUNTU_KEYRING)")
[ -x "$DITING_TOP/tools/venv/bin/dt-validate" ] || warn "dtschema venv missing (only needed for 'make dtbs-check'): python3 -m venv tools/venv && tools/venv/bin/pip install dtschema"
command -v shellcheck >/dev/null || warn "shellcheck missing (only needed for 'make lint')"
command -v adb >/dev/null || warn "adb missing (only needed for 'make inspect-device')"
if [ ${#missing[@]} -gt 0 ]; then
	die "missing: ${missing[*]}"
fi
log "host OK: $(uname -m), $(gcc --version | head -1), $(debootstrap --version 2>/dev/null || /usr/sbin/debootstrap --version)"
