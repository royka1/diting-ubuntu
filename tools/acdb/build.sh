#!/bin/bash
# Build acdb-query against Qualcomm's AudioReach graph services ACDB library
# (references/ar-audioreach-graphservices, BSD-3-Clause-Clear) and generate
# the ID name table used by apm-decode.py.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
top="$(cd "$here/../.." && pwd)"
G="$top/references/ar-audioreach-graphservices"
out="${1:-$here/out}"
mkdir -p "$out"
gcc -O1 -w -Wno-incompatible-pointer-types -D'__unused=__attribute__((unused))' \
	-o "$out/acdb-query" "$here/acdb-query.c" "$here/logstub.c" "$G"/acdb/src/*.c \
	"$G"/ar_osal/src/linux/ar_osal_{file_io,heap,mem_op,mutex,string}.c \
	-I"$G/acdb/inc" -I"$G/acdb/api" -I"$G/ar_osal/api"
grep -rhoE "#define\s+(MODULE_ID_[A-Za-z0-9_]+|PARAM_ID_[A-Za-z0-9_]+|[A-Z0-9_]*_PARAM_ID_[A-Za-z0-9_]+)\s+\(?0x[0-9A-Fa-f]+" \
	"$top/references/ar-audioreach-engine" "$G" 2>/dev/null |
	awk '{gsub(/\(/,"",$3); print tolower($3), $2}' | sort -u > "$out/ids.txt"
echo "built $out/acdb-query"
