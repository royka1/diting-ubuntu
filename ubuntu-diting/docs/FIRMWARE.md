# Firmware

| Component | Needed for | Linux path (expected) | Source | Status |
| --- | --- | --- | --- | --- |
| none | stages C–F (kernel, initramfs, UFS, USB, Ubuntu headless) | – | – | not needed |
| GPU A730 (`a730_sqe.fw`, `gmu_gen70000.bin`, zap shader) | stage G | `qcom/a730_sqe.fw.zst`, `qcom/gmu_gen70000.bin.zst` (Ubuntu `linux-firmware-qualcomm-graphics`) + `qcom/sm8475/xiaomi/diting/a730_zap.mbn` (`firmware-xiaomi-diting`, local) | sqe/gmu: Ubuntu linux-firmware 20260319 (distributable); zap: owner's `/vendor/firmware/a730_zap.mbn`, sha256 `1cc7c7f4…6310` (differs from linux-firmware's sm8450 zap) | DEVICE-TESTED 2026-10-12 (FD730/Turnip, phoc on GPU) |
| ADSP | audio, battery via pmic_glink | `qcom/sm8475/xiaomi/diting/adsp.mbn` | owner's firmware_mnt `adsp.mdt`+`bNN`, squashed by `tools/mdt-squash.py` (sha256 in package MANIFEST) | DEVICE-TESTED (running) |
| CS35L41 amplifiers | loudspeakers | `cirrus/cs35l41-dsp1-spk-prot-diting{.wmfw,-b.bin,-t.bin}` | owner's `/vendor/firmware` | packaged; DSP protection not yet used |
| MPSS (modem) | cellular | `qcom/sm8475/xiaomi/diting/modem.mbn` + `modem_pr/` (carrier MBNs, served by tqftpserv) | owner's firmware_mnt `modem.mdt`+`bNN` (squashed), `modem_pr/` tree | DEVICE-TESTED (registers, SMS) |
| IPA GSI (`ipa_fws`, PAS 15) | mobile data | `qcom/sm8475/xiaomi/diting/ipa_fws.mbn` | owner's firmware_mnt `ipa_fws.mdt`+`b00..b04` (squashed), sha256 `47e8a3d1…a6b9`; loaded into `ipa_gsi_mem` like the vendor DT | DEVICE-TESTED (IPA setup completed, data flows) |
| Video codec IRIS2 (`vpu20_4v`, PAS 9) | video decode | `qcom/sm8475/xiaomi/diting/vpu20_4v.mbn` (`firmware-xiaomi-diting` 0.9.2, local) | owner's `/vendor/firmware/vpu20_4v.mbn` (the file Android loads; same video-firmware.2.4 build as the split `.mdt`), sha256 `fbae62c0…f473` | DEVICE-TESTED 2026-10-13 (HEVC/H.264 decode); encoder not working |
| WLAN (QCA6490 = WCN6855 hw2.1) / BT | Wi-Fi/BT | `ath11k/WCN6855/hw2.1/*` (Ubuntu linux-firmware-qualcomm-wireless) + `updates/ath11k/WCN6855/hw2.*/board.bin` (owner's `bd_l12gl.elf`, inferred); `qca/diting/hpbtfw21.tlv`, `qca/diting/hpnv21*` (owner's bt_firmware) | Ubuntu + owner's phone | DEVICE-TESTED (Wi-Fi scan, BT up); vendor `amss.bin` does not boot under ath11k |

Rules: Diting blobs come only from the owner's own phone (or a verified Diting
firmware for the same region), with path, sha256 and version recorded; nothing from
Nothing/Motorola/Realme. Blobs are never committed (`device-data/` is git-ignored);
`make firmware` builds the local-only `firmware-xiaomi-diting` package (manifest with sha256 in `/usr/share/doc/firmware-xiaomi-diting/MANIFEST`). The listing of the vendor firmware
directories is in `device-data/info/firmware-listing.txt`.

## First-boot extraction (public images)

Public images (`make release`) contain none of the device firmware. The
`diting-firmware-setup` package (first boot, `diting-firmware-setup.service`,
before the login screen) builds `firmware-xiaomi-diting` on the phone from
its own Android partitions of the active slot (`diting-mark-boot-successful
--print-slot`), all read-only:

| Android path | Source on the phone |
| --- | --- |
| `/vendor/firmware_mnt` | `modem_<slot>` (vfat, `shortname=lower` as on Android) |
| `/vendor/bt_firmware` | `bluetooth_<slot>` (vfat) |
| `/vendor/dsp` | `dsp_<slot>` (ext4, `ro,noload`) |
| `/mnt/vendor/persist` | `persist` (ext4, `ro,noload`) |
| `/vendor/{firmware,etc/acdbdata/ukee_mtp,etc/sensors,lib64/camera}` | `vendor_<slot>` in `super`: extents from the liblp metadata (`tools/lpmeta.py`, metadata slot = A/B slot), read-only dm-linear map, extracted with `fsck.erofs --extract --path` |

The tree is passed to `tools/firmware/diting-build-firmware` (`FW_TREE`), the
same builder `make firmware` runs on the tar backups (`FW_SRC`). Validated on
the owner's phone (2026-10-14, HyperOS OS3.0.5.0.VLFEUXM, slot b): all 875
files byte-identical to the package built from the Android-side backups,
including the voice topology and the vendor modification times of the
sensor configuration; about 2 minutes. The service then installs the package
and reboots once. On failure it leaves `/var/lib/diting-firmware-setup/failed`
and the system boots without firmware (software rendering, no audio/modem).

alsa-lib 1.2.16 accepts at most 16 KiB per `bytes` list, so `voice-tplg.py`
splits the calibration blobs into several data sections (alsatplg
concatenates them; the topology binary is unchanged).
