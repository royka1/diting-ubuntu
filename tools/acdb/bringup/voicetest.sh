c() { sudo -n amixer -q -c 0 cset name="$1" "$2" || echo "FAILED: $1 = $2"; }
c 'TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' 0
c 'TERTIARY_TDM_RX_0 Audio Mixer MultiMedia3' 1
c 'MultiMedia4 Mixer TX_CODEC_DMA_TX_3' 1
c 'ADC1_MIXER Switch' 1; c 'ADC1 Switch' 1; c 'TX0 MODE' ADC_NORMAL; c 'ADC1 Volume' 8
c 'ADC4_MIXER Switch' 1; c 'HDR34 MUX' NO_HDR34; c 'ADC4 MUX' INP5; c 'ADC4 Switch' 1; c 'TX3 MODE' ADC_NORMAL; c 'ADC4 Volume' 8
c 'TX DEC0 MUX' SWR_MIC; c 'TX SMIC MUX0' SWR_MIC0; c 'TX_AIF1_CAP Mixer DEC0' 1; c 'TX_DEC0 Volume' 84
c 'TX DEC1 MUX' SWR_MIC; c 'TX SMIC MUX1' SWR_MIC1; c 'TX_AIF1_CAP Mixer DEC1' 1; c 'TX_DEC1 Volume' 84
sudo -n dmesg -C
timeout -s INT ${1:-5} python3 -I /tmp/diting-voice-pcm; echo "rc=$?"
sudo -n dmesg | grep -v audit | tail -20
sudo -n cat "/sys/kernel/debug/asoc/XIAOMI-DITING/MultiMedia3 Voice/state" 2>/dev/null | head -12
# put the media routing back
sudo -n amixer -q -c0 cset name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia3' 0
sudo -n amixer -q -c0 cset name='MultiMedia4 Mixer TX_CODEC_DMA_TX_3' 0
sudo -n amixer -q -c0 cset name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' 1
