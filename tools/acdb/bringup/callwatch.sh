#!/bin/bash
# bring-up: start the voice path while ModemManager reports an active call,
# and put the media routing back afterwards
end=$((SECONDS + ${1:-900}))
pid=
restore() {
	amixer -q -c0 cset name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia3' 0
	amixer -q -c0 cset name='MultiMedia4 Mixer TX_CODEC_DMA_TX_3' 0
	amixer -q -c0 cset name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' 1
}
trap 'restore' EXIT
while [ $SECONDS -lt $end ]; do
	active=$(mmcli -m any --voice-list-calls 2>/dev/null | grep -c "(active)")
	if [ "$active" -gt 0 ] && [ -z "$pid" ]; then
		echo "$(date +%T) call active: starting voice path"
		bash /tmp/voicetest-mixer.sh
		python3 -I /tmp/diting-voice-pcm >> /tmp/callwatch.log 2>&1 &
		pid=$!
		( sleep 3; for sg in 0xb0000040 0xb000003f 0xb0000044 0xb00000b1; do python3 -I /tmp/apmget.py 4 0x080011C1 76 $sg 8 0; done ) >> /tmp/callwatch.log 2>&1 &
	elif [ "$active" -eq 0 ] && [ -n "$pid" ]; then
		echo "$(date +%T) call ended: stopping voice path"
		kill -INT $pid; wait $pid; pid=
		restore
	fi
	sleep 1
done
[ -n "$pid" ] && { kill -INT $pid; wait $pid; }
