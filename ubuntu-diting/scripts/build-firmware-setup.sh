#!/bin/bash
# Build diting-firmware-setup (first-boot firmware extraction, see
# packages/diting-firmware-setup) in the arm64 buildd chroot. Needs sudo.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-buildd.sh"
need git

R="$DITING_TOP/references"
[ "$(git -C "$R/audioreach-topology" rev-parse HEAD 2>/dev/null)" = "$AUDIOREACH_TOPOLOGY_COMMIT" ] ||
	die "need references/audioreach-topology at $AUDIOREACH_TOPOLOGY_COMMIT (make sources)"
[ "$(git -C "$R/ar-audioreach-graphservices" rev-parse HEAD 2>/dev/null)" = "$AUDIOREACH_GRAPHSERVICES_COMMIT" ] ||
	die "need references/ar-audioreach-graphservices at $AUDIOREACH_GRAPHSERVICES_COMMIT (make sources)"

src="$WORK/diting-firmware-setup-pkg"
rm -rf "$src" && mkdir -p "$src/tools/camera" "$src/tools/acdb" "$src/audioreach-topology" "$src/graphservices"
P="$UD/packages/diting-firmware-setup"
cp -a "$P/debian" "$P/diting-firmware-setup" "$src/"
T="$DITING_TOP/tools"
cp "$T/firmware/diting-build-firmware" "$T/lpmeta.py" "$T/mdt-squash.py" "$src/tools/"
cp "$T/camera/chromatix-to-camregs.py" "$T/camera/chromatix_regs.py" "$src/tools/camera/"
cp "$T/acdb/build-voice-tplg.sh" "$T/acdb/voice-tplg.py" "$T/acdb/acdb-query.c" "$T/acdb/logstub.c" "$src/tools/acdb/"
git -C "$R/audioreach-topology" archive HEAD | tar -x -C "$src/audioreach-topology"
git -C "$R/ar-audioreach-graphservices" archive HEAD acdb ar_osal LICENSE | tar -x -C "$src/graphservices"
cp -a "$UD/packages/audio-topology" "$src/audio-topology"

buildd_setup
buildd_build "$src" diting-firmware-setup gcc
