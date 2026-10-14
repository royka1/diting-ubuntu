# Audio: what the stock system does (reference for the mainline port)

Captured on 2026-10-11 from the owner's unit running stock HyperOS while audio
played on the loudspeaker. Raw data (private) in `device-data/audio/`:
`logcat-playback.txt`, `tinymix-*.txt`, `dumpsys-audio*.txt`, `audio-props.txt`,
`dmesg-after-playback.txt`; vendor configuration and calibration in
`device-data/firmware/{vendor_etc,vendor_firmware,odm_etc,mnt_vendor_persist}.tar`.

Status: **NOT STARTED** on mainline (needs ADSP remoteproc, q6apm/AudioReach,
LPASS macros and the amplifiers). Everything below is MEASURED on stock Android
unless marked INFERRED.

## Stack on Android

- ALSA card 0 `waipio-mtp-snd-card`, Qualcomm AGM/PAL (AudioReach) – the DSP owns
  the backends, so no PCM shows RUNNING in `/proc/asound` during playback.
- Configuration (INFERRED from card name + PAL naming):
  `/vendor/etc/audio/sku_cape/resourcemanager_waipio_mtp.xml`,
  `/vendor/etc/audio/sku_cape/mixer_paths_waipio_mtp.xml`, audio policy in
  `sku_cape/audio_policy_configuration.xml` and `/odm/etc/audio_policy_engine_*.xml`.
- Calibration: ACDB in `/vendor/etc/acdbdata/` (per-board directories).

## Loudspeaker path (measured)

| Item | Value |
| --- | --- |
| PAL device | `PAL_DEVICE_OUT_SPEAKER` (id 3), stream `PAL_STREAM_PCM_OFFLOAD` |
| Device config | 2 ch, 48 kHz, 24 bit, SndDev `speaker` |
| Backend (virtual) | `TDM-LPAIF-RX-TERTIARY-VIRT-0`: 48 kHz, 2 ch, fmt 6 |
| Backend (physical) | `TDM-LPAIF-RX-TERTIARY`: 96 kHz, 3 ch, fmt 6, slot mask 7 |
| ACDB graph keys | `0xa1000000=0xa100000f`, `0xa2000000=0xa2000001`, `0xab000000=0x1`, `0xac000000=0xac000002` |
| Amplifiers | 2× Cirrus Logic CS35L41 (HALO DSP), I2C bus 2 (QUP) at `0x40` and `0x42` |
| Amp firmware | `/vendor/firmware/cs35l41-dsp1-spk-prot.wmfw` + `{B,T}-cs35l41-dsp1-spk-prot.bin` (bottom/top tuning), `*-spk-cali.*` for calibration |
| Per-unit calibration | `/mnt/vendor/persist/audio/crus_calr.{bin,txt}` (speaker impedance calibration; unique to this phone — backed up, never share) |
| TDM clock | `get_tdm_clk_id: 516` in the vendor kernel log |

## Mainline plan (later stages)

1. ADSP remoteproc + firmware from `device-data` (local package only).
2. AudioReach (q6apm/q6prm) sound card for SM8450-class with a Diting
   `sound` node: tertiary TDM (`TERTIARY_TDM_RX_0`) → two `cirrus,cs35l41` on the
   I2C bus behind QUP bus 2, using upstream `cs35l41` + `wm_adsp` (firmware
   names mapped from the vendor files, `B`/`T` = `cirrus,…` channel suffixes).
3. UCM profile (alsa-ucm-conf style) for Ubuntu/PipeWire.

Other audio parts present (vendor DT/logs): fsa4480 USB-C audio switch (I2C5
`0x42`), WCD/VA/RX/TX LPASS macros for mics and headset – not analysed yet.
