#!/bin/bash
# Build only the Diting DTB (fast iteration). --check adds dtbs_check and
# dt_binding_check for the touched schemas using tools/venv dtschema.
. "$(dirname "$0")/lib.sh"
"$UD/scripts/prepare-kernel.sh"
mkdir -p "$KERNEL_OBJ" "$OUT/logs"
[ -f "$KERNEL_OBJ/.config" ] || kmake defconfig >/dev/null
if [ "${1:-}" = --check ]; then
	export PATH="$DITING_TOP/tools/venv/bin:$PATH"
	need dt-validate
	log="$OUT/logs/dtbs-check.log"
	kmake CHECK_DTBS=y W=1 "$KERNEL_DTB" > "$log" 2>&1
	kmake dt_binding_check DT_SCHEMA_FILES="arm/qcom.yaml:phy/qcom,snps-eusb2-phy.yaml:input/touchscreen/st,ftm5-spi.yaml:display/panel/xiaomi,l12-36-02-0b.yaml" >> "$log" 2>&1
	# sm8450.dtsi carries two known upstream W=1 warnings (dsi #address-cells)
	issues="$(grep -E 'warning|Warning|error|from schema' "$log" | grep -v 'sm8450.dtsi.*avoid_unnecessary_addr_size' || true)"
	if [ -n "$issues" ]; then echo "$issues"; die "dtbs_check reported issues (log: $log)"; fi
	log "dtbs_check/dt_binding_check clean (log: $log)"
else
	kmake "$KERNEL_DTB"
fi
