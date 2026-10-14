#!/bin/bash
# Build firmware-xiaomi-diting from the owner's own phone backups
# (device-data/, never committed) with tools/firmware/diting-build-firmware,
# the same builder that diting-firmware-setup runs on a phone. The resulting
# .deb is for local use only.
. "$(dirname "$0")/lib.sh"
need gcc m4 alsatplg dpkg-deb

ART="$DITING_TOP/references/audioreach-topology"
[ "$(git -C "$ART" rev-parse HEAD 2>/dev/null)" = "$AUDIOREACH_TOPOLOGY_COMMIT" ] ||
	die "need $ART at $AUDIOREACH_TOPOLOGY_COMMIT (make sources)"
[ "$(git -C "$DITING_TOP/references/ar-audioreach-graphservices" rev-parse HEAD 2>/dev/null)" = "$AUDIOREACH_GRAPHSERVICES_COMMIT" ] ||
	die "need references/ar-audioreach-graphservices at $AUDIOREACH_GRAPHSERVICES_COMMIT (make sources)"
mkdir -p "$OUT/logs" "$OUT/debs"
bash "$DITING_TOP/tools/acdb/build.sh" "$WORK/acdb" > "$OUT/logs/acdb-query-build.log" 2>&1 ||
	{ tail -20 "$OUT/logs/acdb-query-build.log"; die "acdb-query build failed"; }

FW_SRC="${FW_SRC:-$DITING_TOP/device-data/firmware}" \
CAM_SRC="${CAM_SRC:-$DITING_TOP/device-data/camera}" \
ACDB_QUERY="$WORK/acdb/acdb-query" ART_DIR="$ART" \
FIRMWARE_MTIME="$KERNEL_RELEASE_DATE" \
	"$DITING_TOP/tools/firmware/diting-build-firmware" "$OUT/debs"
