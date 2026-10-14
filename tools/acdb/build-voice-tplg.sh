#!/bin/bash
# Build the Diting topology with the vendor voice call graph (local use only:
# the result contains calibration from the phone's ACDB).
#
#   build-voice-tplg.sh OUT.bin [--no-devpp]
#
# Needs the phone's ACDB directory (ACDB_DIR, default: extracted from
# device-data/firmware/vendor_etc.tar) and acdb-query (ACDB_QUERY, default
# from tools/acdb/build.sh). ART_DIR/ATOP_DIR: audioreach-topology checkout
# and packages/audio-topology.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
top="$(cd "$here/../.." && pwd)"
out="$1"; shift
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
q="${ACDB_QUERY:-$here/out/acdb-query}"
art="${ART_DIR:-$top/references/audioreach-topology}"
atop="${ATOP_DIR:-$top/ubuntu-diting/packages/audio-topology}"
if [ -z "${ACDB_DIR:-}" ]; then
	tar -xf "$top/device-data/firmware/vendor_etc.tar" -C "$tmp" vendor/etc/acdbdata/ukee_mtp
	ACDB_DIR="$tmp/vendor/etc/acdbdata/ukee_mtp"
fi
acdb="$ACDB_DIR/MTP_ukee_acdb_cal.acdb"
mkdir -p "$tmp/rx" "$tmp/tx"
# voice call RX (handset) and TX (handset mic, Fluence endfire), VSID default
(cd "$tmp/rx" && "$q" "$acdb" graph a1000000=a1000010 a2000000=a2000004 ac000000=ac000005 af000000=af000001 b3000000=b3000001 >/dev/null 2>&1 &&
	"$q" "$acdb" cal a1000000=a1000010 a2000000=a2000004 ac000000=ac000005 af000000=af000001 b3000000=b3000001 >/dev/null 2>&1)
(cd "$tmp/tx" && "$q" "$acdb" graph a3000000=a3000004 ad000000=ad000009 b1000000=b1000007 b3000000=b3000001 >/dev/null 2>&1 &&
	"$q" "$acdb" cal a3000000=a3000004 ad000000=ad000009 b1000000=b1000007 b3000000=b3000001 >/dev/null 2>&1)
m4 -I "$art" -I "$atop" "$atop/XIAOMI-DITING.m4" |
	# the speaker device mixer also takes the voice front end
	sed '/SectionWidget."TERTIARY_TDM_RX_0 Audio Mixer"/,/^}/ s/^\(\s*\)MultiMedia1$/\1MultiMedia1\n\1MultiMedia3/' > "$tmp/base.conf"
python3 -I "$here/voice-tplg.py" "$@" "$tmp/rx" "$tmp/tx" > "$tmp/voice.conf"
cat "$tmp/base.conf" "$tmp/voice.conf" > "$tmp/full.conf"
alsatplg -c "$tmp/full.conf" -o "$out" 2>&1 | grep -v "undefined sink widget/stream\|undefined source widget/stream" || true
echo "wrote $out"
