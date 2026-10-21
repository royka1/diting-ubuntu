# Known issues and risks

State as of 2026-10-21 (kernel 7.2.10-diting r46, device-xiaomi-diting 0.7.17,
firmware-xiaomi-diting 0.9.5, phosh 0.54.0-1diting1, diting-firmware-setup
0.1.1). Device evidence is
in `docs/BRINGUP_STATUS.md`.

## Open, device-confirmed

- **Charging state** (r44, patch 0091): the firmware reports the battery
  current as negative while charging, and upower 1.91 calls any battery with
  a negative `current_now` "discharging". The phone then showed discharging
  on the charger, and on 2026-10-15 at 2 % upower powered it off while it was
  plugged in. 0091 negates the value; DEVICE-TESTED on the stock fast charger:
  upower now reports charging, and unplugged discharging (-180 mA at 99 %).
  Not yet measured: charging from a low level (on 9 V / 1.16 A at 96 % the firmware reported
  USB type SDP, current_max 2 A).
- **GPU faults** still happen now and then: GMU HFI messages time out
  (`HFI_H2F_MSG_GX_BW_PERF_VOTE ... timed out`, a few per hour) and once,
  during a phone call, the GPU faulted (CP read of iova 0) and hangcheck
  started recovery. Before r44 (0090) recovery and the SMMU fault handler
  deadlocked on `gpu->lock`: phoc stayed in D state, the screen stayed dark
  and the power key did nothing until a reboot. With 0090 the GMU wait gives
  up after 1 s so recovery can finish; that path has not yet run on the
  phone. A second hang (under Waydroid) showed that recovery does run with
  0090 but the GMU never initialises again, so the screen still stays dark.
  Both hangs started when the GPU resumed from idle. r44 (0092) keeps the
  A730 powered for 1 s after it goes idle instead of 66 ms, as an
  experiment to make resumes rarer; whether it helps is not yet known.
- **Call audio** works in both directions on 3G calls, with Fluence echo and
  noise cancellation; calls start on the earpiece, the Calls app's speaker
  and mute buttons work (diting-callaudio replaces callaudiod, whose port
  switching cannot work here: PipeWire makes earpiece and loudspeaker, which
  share a PCM, exclusive profiles). Call volume is fixed: VCPM step 4 with
  volume boost (the calibration has steps 0..4; step 5 silences RX), and
  speakerphone calls run the amplifiers at Android's level (digital 0 dB,
  analog gain 17) while media keeps the -6 dB/minimum-gain setup; the
  owner finds speakerphone "enough, not very loud". During calls the volume
  keys set the amplifier level (earpiece up to +6 dB at minimum analog gain,
  loudspeaker up to +6 dB at analog gain 17 with the protection running); call and media volume are kept apart. Limits: the TX rate converters are fixed at 16 kHz (wideband) because VCPM
  does not apply the per-rate calibration entries, so narrowband (8 kHz)
  calls are untested; calls fall back to 3G (no VoLTE/IMS). The voice
  topology and ADSP modules come from the local firmware package; without
  it (or without fastrpc-diting) calls have no audio.
- While a call runs, media playback (MultiMedia1) is taken off the
  loudspeaker; media that is playing at the very moment a call starts can
  keep the speaker graph from attaching to the call.
- Ubuntu's `q6voiced` (qcom-phone-utils) and `wys` (phosh-phone) are for
  other platforms (q6voice); device-xiaomi-diting masks them.
- The ADSP audio PD can be created once per ADSP boot: diting-audiopd.service
  is started by udev and not restarted automatically.
- **Microphones** work (two analog mics, device package 0.5.1); the earpiece
  (top amplifier switched by gpio52) is not used yet.
- **Camera**: only the rear ultrawide (S5K4H7) works so far: raw capture and
  libcamera (simple pipeline, software ISP, 30 fps, patched libcamera with an
  S5K4H7 sensor helper). No colour tuning (CCM) yet, and auto exposure stops at
  one frame time (33 ms), so dim rooms stay dark. Its register tables come from the phone's vendor partition
  (`device-data/camera`, see tools/camera) into the local firmware package.
  The main camera (S5KHP1, 200 MP, MIPI C-PHY) streams too (libcamera camera
  2, 30 fps at 4096x3072) with contrast autofocus in the patched libcamera
  (continuous by default, about 3 s per scan; LensPosition is a 0..100
  scale, not dioptres). No colour matrix (CCM) yet. The video codec (iris/venus) has no SM8450/SM8475
  support in mainline: no hardware HEVC encode/decode; AV1 is not in this
  SoC's hardware. Front (IMX596) and macro
  (GC02M1) have no driver yet. The login screen's PipeWire also opens the
  cameras.
- **Sensors**: accelerometer (rotation), gyroscope, magnetometer/compass,
  light and proximity work through the SLPI (libssc + iio-sensor-proxy 3.9);
  the screen turns off at the ear during calls (owner-tested). The
  SLPI's `sns_registry` remote interface is not provided (answered with an
  error, harmless). Debugging: `adsp_diag --base 192` reads the SLPI's log.
- **Suspend efficiency**: suspend/resume works, but `qcom_stats` never shows
  CXSD/AOSD/DDR residency (counter layout on SM8475 unverified) and the drain
  test was inconclusive. While charging, ADSP glink notifications wake the phone
  after a few seconds. On battery the modem's QMI indications (network
  status) wake it every now and then (ftrace: ipcc/glink-smem as the first
  interrupt after resume); in 60 s RTC tests it slept the full period in about
  half of the cycles. ModemManager does not ask the modem to suppress them
  while the screen is off (Android does).
- **Phone stayed awake after a wake-up from sleep** (fixed in device package
  0.7.15, kernel r45): the ADSP charger firmware sends a Xiaomi status
  message (opcode 0x50) every 480 s, and it ends deep sleep (5 of 5 traced
  wakes on 2026-10-15). GNOME turns the screen on for a minute after every
  resume and then does not suspend again until the phone is used, so the
  phone stayed awake with the screen off for 20-80 minutes and got warm.
  `diting-resuspend` (a system-sleep hook and service) suspends again 20 s
  after a resume unless a key was pressed, any input device reported an
  event, something inhibits sleep, or a call is active. Switch it off with
  `sudo systemctl mask diting-resuspend.service`. Kernel patch 0093 drops
  the 0x50 message (it used to complete the ack of a pending battery
  request); the message still wakes the phone.
- **Screen lit up at every automatic wake-up** (fixed in device package
  0.7.16 + patched phosh, `make phosh`): phosh and gnome-settings-daemon
  turned the screen on at every resume, so it lit up for 20 s every
  8 minutes. The system-sleep hook now creates `/run/diting-resuspend.dark`
  when no power or volume key was pressed during suspend; the patched phosh
  then keeps the outputs off. The power key, an incoming call or a
  notification that wakes the screen still turn it on. Input while the
  screen stays off (a touch in a pocket) no longer keeps the phone awake.
  DEVICE-TESTED 2026-10-21 with an RTC wake: screen off (DSI `dpms` Off)
  for the whole wake, suspended again after 21 s. Power-key wake from sleep
  not yet owner-tested. An archive phosh with a higher version replaces the
  patched one; then the screen lights up again.
- **SLPI handover messages**: `qcom_q6v5_pas 2400000.remoteproc: Handover
  signaled, but it already happened` floods the log (rate-limited) in bursts
  of about 90 s at ~8/s, after boot and after some resumes: the sensor DSP
  toggles its smp2p ready and handover bits. Sensors keep working. The
  smp2p sleep state entry that the vendor kernel exports to the SLPI (r46,
  0095/0096) does not stop it; cause unknown.
- **Fixed in device package 0.7.10/0.7.11**: calls had no audio since kernel
  r30 (libadsprpc used the system dma-buf heap; the audio PD now uses the
  fastrpc allocator); mobile data was lost after every suspend (ModemManager
  removed the modem; now quick suspend/resume) and ModemManager 1.25.95
  crashed re-creating the data link after a resume (local rebuild with the
  upstream fix, pinned). Kernel r40 (patch 0085): the fastrpc driver lost
  one DSP request per suspend (the freezer interrupted adsprpcd's listener
  wait), so the first voice-graph opens after N suspends failed and calls
  had no audio; owner-tested call after 3 suspends with audio. Kernel r41
  (patch 0086): the bottom speaker was silent whenever the speaker
  protection firmware ran (its second receive slot repeated its own channel;
  the vendor layout gives RX2 the other channel).
- **Wi-Fi 5 GHz** (fixed in r42 / firmware 0.9.4): ath11k used the generic
  board-id-255 entry of Ubuntu's board-2.bin (another design's RF setup):
  no 5 GHz networks at all and one stream on 2.4 GHz. Ubuntu's default
  WCN6855 firmware rejects the phone's own board data. Kernel r42 (patch
  0087) loads WCN6855 firmware from the nfa765 directory on this phone;
  firmware-xiaomi-diting puts the firmware Android uses there under
  updates/ (amss20.bin, WLAN.HSP.2.0.c2, with m3.bin), plus a board-2.bin
  with bd_l12gl.elf (the file Android loads) and this phone's MAC from
  persist (the Xiaomi board data has none). Without the firmware package
  Ubuntu's nfa765 firmware runs with the generic board data (2.4 GHz).
  After a clean boot: both chains receive (5 GHz [-57, -66] dBm), TX
  866 Mbit/s, no lost frames; owner speed test on the vendor firmware
  (before the reloads) over 400 Mbit/s.
  Repeated ath11k module reloads (about 20 in one boot, with PCIe AER
  timeouts) left the chip with one deaf chain per band and 80-90 %
  transmit failures until a reboot: do not judge Wi-Fi after reloads.
- **Wi-Fi band choice** (device pkg 0.7.13): wpa_supplicant roams within a
  network only to a stronger access point (background scan every 300 s
  while the signal is above -65 dBm), so after a room with weak 5 GHz the
  phone stayed on 2.4 GHz next to the router. diting-wifi-band-steer scans
  once a minute while on 2.4 GHz and roams to the same network's 5/6 GHz
  access point at -72 dBm or better; device-tested 2.4 GHz -> 5180 MHz,
  link 1921/1441 Mbit/s (160 MHz, 2 streams).
- **Wi-Fi throughput** (r43, patch 0089): all ath11k data path interrupts
  arrive on CPU 0 (multiplexed PCIe MSI, affinity fixed), so receive
  processing ran in softirq on that little core (ksoftirqd/0 91 %) and
  TCP downloads reached about 210 Mbit/s on a 1921 Mbit/s link (657 with
  Wi-Fi power save off). Threaded NAPI moves the rings to kthreads on
  other cores: 888 Mbit/s from a gigabit-wired PC with power save on
  (857 off), i.e. the wired side's limit.
- **Speaker protection** runs: the CS35L41 protection firmware (Cirrus CSPL)
  with this unit's factory calibration from persist/audio/crus_calr.bin
  (top 5.90 ohm, bottom 7.12 ohm), set up by diting-speaker-protection at
  boot (needs firmware-xiaomi-diting >= 0.7.3, otherwise the plain ASP path).
  With it running, media plays at Android's level (digital 0 dB, analog gain
  17; owner listening test: correct); without calibration the speakers stay
  6 dB lower at minimum analog gain.
- **phoc mode switching** needs the patched phoc (`make phoc`, pinned); with
  Ubuntu's phoc every refresh-rate change reverts to 60 Hz.
- **Shutdown**: `gnome-session-init-worker` ignores SIGTERM; session scopes get a
  5 s stop timeout (device package) instead of the 90 s default.
- `disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration` warning at
  boot (harmless so far).
- `systemd-networkd` runs next to NetworkManager.

### Video encoder resets the phone (SM8475 iris, r35)

The hardware encoder is disabled in r36 (only `/dev/video0`, the decoder, is
registered). With the encoder enabled, starting the raw input port hangs the
video firmware and the next command the driver writes resets the whole SoC.
No pstore record survives (on this phone pstore is empty even after a normal
warm reboot), so debugging needs a live `dmesg -w` over the network with
`printk_delay`, and the firmware's own log (`HFI_PROP_DEBUG_LOG_LEVEL`).

### Browser video decoding (VA-API over V4L2)

Firefox and Chromium decode H.264, HEVC and VP9 on the iris decoder through
the `libva-v4l2-stateful` package (patched VA-API driver, also installed as
`msm_drv_video.so`, so no `LIBVA_DRIVER_NAME` is needed). Limits:

- **Snap Chromium** cannot read host libraries. A systemd user service
  (`diting-chromium-vaapi`) copies the driver into
  `~/snap/chromium/common/dri` at login and writes `~/.chromium-browser.init`
  (VA-API feature flags) if there is none. After a package upgrade the copy
  is refreshed at the next login, or by running `diting-chromium-vaapi`.
- **Chromium path**: Chromium never calls `vaSyncSurface`, so the driver
  finishes each picture in `vaEndPicture`, and decodes straight into
  Chromium's buffers with only one CAPTURE buffer queued at a time (the
  firmware returns empty buffers for hidden VP9 frames out of order).
  Decoding is serialised per frame; 4K VP9 plays smoothly.
- **10-bit** (HEVC Main10, VP9 profile 2) is advertised but only NV12
  output is implemented: untested and expected to fail.
- No AV1: the decoder lists only H.264, HEVC and VP9 (`VIDIOC_ENUM_FMT`).
- Kernel r38 or later is required: earlier iris read past its timestamp
  metadata (0084) and could end decoding with a spurious EOS.

### Reboot can hang after the video codec was used

Several reboots hung at the end of `systemd-shutdown` after iris sessions;
the owner had to hold the power key. Removing the iris module while the
core is initialised deadlocks (`iris_core_deinit` holds `core->lock` and
calls `disable_irq()`, while the IRQ thread waits for that lock); the
shutdown hang may be the same path. Not yet confirmed.

### Char-device use-after-free at boot (oops in `kobj_lookup`)

Seen twice on r35/r36: `v4l_id` (udev) oopses in `chrdev_open` ->
`kobj_lookup` at virtual address `0x2400000000`/`0x2400000008`, i.e. a
stale entry in the char-device map from a driver that freed its cdev
without unregistering it. With `kernel.panic=0` the boot hangs. Driver not
identified yet. A KASAN build (generic, inline) boots too slowly for the
default `deferred_probe_timeout`: GPU SMMU and CCI probes time out and
the boot hangs in PCIe probing at ~20 s, so the KASAN run needs a longer
timeout. That KASAN run did find a global out-of-bounds read in
`qcom_spmi_temp_alarm` (fixed by patch 0082).

### Compute DSP (CDSP) and FastRPC

The CDSP runs since r46 (0094, firmware 0.9.5 with `cdsp.mbn` and the
vendor's `dsp/cdsp` libraries, including `fastrpc_shell_unsigned_3`).
libcdsprpc finds the process shells through
`/usr/share/qcom/conf.d/xiaomi-diting.yaml` (device package 0.7.17), and the
logged-in user can open `/dev/fastrpc-cdsp` (udev `uaccess`).
DEVICE-TESTED 2026-10-21: Qualcomm's `fastrpc_test -d 3 -U 1 -a v68`
(calculator, multithreading, HAP memory) passes in an unsigned PD, 3 of 3
runs. Limits:

- **No dma-buf heap**: when libcdsprpc can open `/dev/dma_heap/system` it
  allocates its shared buffers there; those are CPU-cached and the fastrpc
  driver does no cache maintenance on them, so the DSP reads stale data and
  dynamic loading fails at random ("bad elf magic", "mmap hdrs failed",
  "lseek failed"). Users without access to the heap (the default; only root
  and the `fastrpc` group have it) get the driver's own buffers and work.
  Do not add users to the `fastrpc` group; run root clients with
  `InaccessiblePaths=/dev/dma_heap` like `diting-audiopd.service`.
- Only unsigned PDs: signed PDs would need Xiaomi's test signatures.
- Machine learning on the HTP (Qualcomm AI Engine Direct / QNN, Hexagon
  v69) not yet tried.

### Rare early-boot oops while fastrpc probes (seen once)

One boot oopsed at 6.8 s (`paging request at 0000002400000000`) while the
CDSP fastrpc context banks were probing; the call trace was lost. With
`kernel.panic=0` the phone then hangs; `/etc/sysctl.d/90-diting-panic.conf`
on the test phone now sets 10 s (applies only after systemd-sysctl).

## Fixed, kept here for context

- **ADSP services late or missing after boot** (device package 0.7.14):
  udev loaded `qcom_pd_mapper` in parallel with `qcom_q6v5_pas`; when the
  ADSP (started first, ~7 s) found no PD mapper it retried only after 50 s,
  300 s or not at all. Until then the battery read 0 % (`-EAGAIN`), charging
  was not reported, speaker protection failed and there was no sound card.
  `/etc/modprobe.d/diting-dsp.conf` now loads the PD mapper first: ADSP
  services at ~13 s, sound card and speaker protection at ~15 s.
- **GPU GMU resume** (0027): the A730v3 GMU needs up to 12 ms to leave reset;
  upstream waited 10 ms. Now 100 ms like downstream.
- **A/B retry counter**: `diting-boot-successful.service` marks the slot
  successful, else ABL marks it unbootable after 7 boots.
- **Mobile data** (0030–0043, firmware 0.6.0): IPA v5.1 from the XEC kernel.
  The ModemManager TUN placeholder port of device package 0.4.x is gone.

- **Waydroid** (2026-10-15): Android had no internet (kernel lacked policy
  routing; fixed in r44) and no shared storage (the MAINLINE vendor image
  declares an OMX codec service it does not ship, so MediaProvider hangs).
  Steps for users: `docs/WAYDROID.md`.

## Configuration the owner sets per phone (not packaged)

- Mobile data APN: a NetworkManager `gsm` connection, e.g.
  `nmcli c add type gsm ifname '*' con-name mobile gsm.apn <apn>`. Odido uses
  `smartsites.t-mobile`. Wi-Fi keeps the lower route metric.
- rmtfs runs read-only (`-r`): modem EFS changes do not persist, which is why
  `diting-modem-setup` re-applies the USIM session and RAT preference each boot.

## Public images

- Tested on one unit only (EEA, HyperOS OS3.0.5.0.VLFEUXM). Other
  HyperOS/MIUI versions give other firmware builds (ADSP, modem, ACDB); the
  audio topology and the IPA data were only checked against this one.
- The vendor partition carries a second main camera (Samsung HM6); units
  with it have no main camera.
- Bluetooth runs with the controller's own address, apparently a firmware
  default that may be the same on every phone; the DT `local-bd-address`
  written by diting-mkbootimg does not take effect. `btmgmt public-addr`
  can set another one.
- The default PIN 147147 is public; users must change it (`passwd`). sudo
  asks for it (owner images: no password, key-only SSH).
- The full image has not been flashed on a phone by the owner; its parts
  (kernel, packages, firmware extraction) were tested separately.

## Risks / not verified

- eUSB2 repeater: upstream `nxp,ptn3222` driver does not apply the vendor tuning
  values.
- UFS limited to the SM8450 300 MHz clock table (vendor: 850 MHz); performance only.
- Regulator supply parents (`vdd-*-supply`) are not described. PM8350B L1 and
  PMR735B regulators not described.
- `fw_devlink.sync_state=timeout` is on the cmdline because gcc/gpucc wait for
  the GMU forever otherwise.
- GPU identity: the A730v3 (chip id 0x07030002) runs with the upstream A730
  (0x07030001) catalog entry, which Mesa knows as FD730.
- IPA: the XEC v5.1 data was written for SM8450 (OnePlus 10 Pro); SM8475 values
  were only cross-checked against the vendor DT, not against vendor `ipa3`
  resource tables. Throughput, tethering and IPv6 untested.
- Build host: GCC crashes with THP on the edge host kernel; worked around with
  `nothp` (BUILD.md).
- CoreSight/QDSS nodes inherited from `sm8450.dtsi` stay blacklisted
  (`/etc/modprobe.d/diting-bringup.conf`).
