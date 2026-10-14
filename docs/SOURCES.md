# Sources

Retrieved 2026-10-11. All reference trees live under `references/` (git-ignored,
fetched by `make sources`) and are never modified.

Status vocabulary: **CONFIRMED FROM SOURCE** (read in the file), **MEASURED ON
DEVICE** (read from the owner's phone), **INFERRED**, **UNVERIFIED**.

## Production kernel

| Item | Value |
| --- | --- |
| Release | Linux **7.2.10** (stable), released 2026-10-11 |
| How selected | `https://www.kernel.org/releases.json` → `latest_stable = 7.2.10`; mainline was 7.3-rc6 (not used) |
| Git | `https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git` |
| Tag object | `v7.2.10` = `57eee103859fa039a1f2bf343c4453ef40661be8` |
| Commit | `7b20d05fd38de8e0be168956f6fd241d750c7d69` ("Linux 7.2.10") |
| Signature | `git verify-tag`: GOODSIG/VALIDSIG Greg Kroah-Hartman, primary key `647F28654894E3BD457199BE38DBBDC86092693E` (key fetched via WKD) |
| Tarball | `https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.10.tar.xz`, sha256 `2feaa70453e91f541be6a5c9078d8168e081af45a3d9718054850538cff2ebf3` (from `sha256sums.asc`; the build uses the signed git tag, not the tarball) |
| Lock file | `ubuntu-diting/config/kernel.lock` |

## Reference repositories

| Dir | URL | Branch | Commit (date) | Consulted | Establishes / does not establish |
| --- | --- | --- | --- | --- | --- |
| `sm8450-linux` | github.com/sm8450-mainline/linux | `next` | `a19585977c11` (2025-08-17), base 6.17-rc1 | `sm8475.dtsi`, `sm8475-xiaomi-diting.dts`, `sm8475-nothing-pong.dts`, history | Community SM8475 DT work (Danila Tikhonov, Jens Reidel). Diting DTS there has `&tlmm` **disabled**, UFS **commented out**, PCIe WIP and a "[hack]" GPU/UFS commit. Not a proven boot. Reference only. |
| `sm8450-fdt` | github.com/sm8450-mainline/fdt | `master` | `3e347601d9e9` (2024-11-27) | `diting.dts`, `pong.dts` | Extracted vendor DT, older firmware than the owner's phone. Superseded for this unit by the live DT read from the phone. |
| `sm8450-pmaports-archive` | github.com/sm8450-mainline/pmaports | `master` | `057851da99cf` (2025-08-24) | `device-xiaomi-diting/{APKBUILD,deviceinfo,*.post-install}`, `device-nothing-pong/deviceinfo`, `linux-postmarketos-qcom-sm8450/APKBUILD` | Old pmOS packaging: kernel 6.5 fork, header v4, offsets that match the stock image, `append_dtb`, openrc services (tqftpserv, pd-mapper, qbootctl). `deviceinfo_super_partitions="/dev/sda28 /dev/sda28"`: sda28 **is** `super` on the owner's phone (MEASURED), but it is irrelevant to Ubuntu and is not used. |
| `pmaports-current` | gitlab.postmarketos.org/postmarketOS/pmaports | `master` | `b48d67b2911e` (2026-10-11) | grep for header v4 devices | No Diting/SM8475 device in current pmaports. |
| `lineage-diting` | github.com/LineageOS/android_device_xiaomi_diting | default | `2eb240c46704` (2026-09-15) | BoardConfig | Partition sizes (boot 0x0C000000, vendor_boot 0x06000000, dtbo 0x01800000) – agree with measurements. |
| `lineage-sm8450-common` | github.com/LineageOS/android_device_xiaomi_sm8450-common | default | `67a471734b63` (2026-10-04) | BoardConfigCommon | Header v4, pagesize 4096, offsets kernel 0x8000 / ramdisk 0x1000000 / dtb 0x1f00000 – agree with measurements. |
| `xiaomi-sm8475-dev-diting` | github.com/Xiaomi-SM8475-Development/android_device_xiaomi_diting | default | `847a033293a1` (2023-10-02) | BoardConfig | Older Android tree, same values. |
| (patches only) | github.com/Xlie-Electronic-Customs/linux (XEC kernel, OnePlus 10 Pro `oneplus-negroni` port) | `7.2` | `99e0c83637f9` (branch head 2026-10-12); IPA commits `25c1e5f39be7`, `2408fc897517`, `d183904152fa`, `c68a69de9d0a`, `53b553477b4c`, `2d253d7ee5d5`, `98266fa08ea0`, `7701ff79a41d`, `8423b62bab6a`, `36e9b1bcae46`, `beddfc2e6762` (2026-03-02 … 2026-08-12) | commit `.patch` downloads, `sm8450-oneplus-negroni.dts` `&ipa` | IPA v5.1 driver data and SM8450 IPA node, carried as 0030–0040. Values cross-checked against the Diting vendor DT (`qcom,ipa-hw-ver = <22>`, IMEM 0x146a8000, regs 0x3e00000+0x140000); IRQ differs (vendor 654, XEC 655) and firmware region differs (vendor `ipa_gsi_mem`, XEC `ipa_fw_mem`): the vendor values are used. Owner tip: the OnePlus 10 Pro wiki says IPA v5.1 works there. |
| `hexagonrpc` | github.com/linux-msm/hexagonrpc | `main` | `da7a3742ab8d` (2026-09-15) | hexagonrpcd, rpcd_builder, apps_std | Base of `hexagonrpcd-diting` (pinned in `diting.conf`), the SLPI's file server, plus local patches 0004–0008 (error replies, >256 B inputs, writable persist mapping with real fwrite/fremove/frename). Ubuntu ships 0.4.0 without the sensor registry methods. |
| `hexagonrpc-z3ntu` | github.com/z3ntu/hexagonrpc | `apps_std_fwrite` | `9f987970f9bc` (2026-10-13) | WIP commits by Luca Weiss (sns_reg_version mapping, fwrite, fremove, fopen_with_env_fd, fclose_fd) | Ported onto upstream `da7a374` (interp4 method definitions) in `ubuntu-diting/packages/hexagonrpc/patches`; the debug message and >31-method commits are obsolete upstream, the sns_reg_version path bug is fixed. |
| `libssc` | codeberg.org/DylanVanAssche/libssc | `main` | `54dd13e36d65` (2026-09-09) | sensor discovery, mount matrix | Built as `libssc-diting` (pinned in `diting.conf`): QMI client for the SLPI sensor core. |
| `iio-sensor-proxy` | gitlab.freedesktop.org/hadess/iio-sensor-proxy | tag `3.9` | `0085ddf8ecb1` (2026-03-02) | drv-ssc-*, 80-iio-sensor-proxy.rules | First release with SSC support; built with Ubuntu's 3.8 packaging and `-Dssc-support=enabled`. Accel/proximity off by default upstream (libssc issue 98), enabled for diting by udev. |
| `sm-x800-linux` | github.com/aaronsb/sm-x800-linux | `main` | `6f32485` (2026-09-23) | `pmaports-overlay/device/testing/linux-postmarketos-qcom-sm8450/{sm8450-camss,camcc-sm8450-shared-rcg,camcc-sm8450-retain-ff}.patch`, issue #27 | Galaxy Tab S8+ (SM8450) mainline 7.2 camera work, GPL-2.0-only; carried unchanged as 0055–0057. Verified against the diting vendor DT (camera block registers, interrupts, SMMU SIDs, CSIPHY rail values; retain-regs). |
| `lineage-sm8450-modules` | github.com/LineageOS/android_kernel_xiaomi_sm8450-modules | default | (sparse: qcom/opensource/camera-kernel/drivers/cam_sensor_module/cam_csiphy) | `cam_csiphy_2_1_3_hwreg.h`, `cam_csiphy_core.c`, `cam_csiphy_soc.c` | GPL-2.0 vendor camera kernel: CSIPHY v2.1.3 C-PHY lane table and rate buckets (standard table for "qcom,csiphy-v2.1.3"; Xiaomi per-device tables exist for other models), C-PHY programming order. Not verified against a live register dump on diting. |
| (owner's Mi 10T kernel) | ~/linux (read-only) | — | `6be5aa3ba83c`, `417f0ecccc1c`, `e5bf80457204` | CAMSS C-PHY support | The owner's working SM8250 C-PHY implementation, carried as 0070–0072; its link frequency equals the symbol rate (V4L2 docs: half). |
| `qcom-cphy-series` | codeberg.org/sdm845/linux | `b4/qcom-cphy` | `f856703c0` | v8 "Add support for C-PHY configuration" | Upstream WIP, SDM845 table only; consulted, not used. |
| `libcamera-millicam` | gitlab.com/tui/libcamera | `millicam_af_6` | `4312a90` (2026-02-26) | `4ba0503` software ISP focus control, AF commits `684ec19`…`4312a90` | Focus control carried as packages/libcamera 0002 (also on the libcamera list as patch 26241); the AF prototype was the starting point for the own AF (0004), not carried. |

Not consulted yet (needed later): `LineageOS/android_kernel_xiaomi_sm8450` (panel/touch
drivers), `sm8450-mainline/firmware-nothing-pong` (only as layout reference, never as
Diting firmware), xiaomifirmwareupdater.com.

## Device measurements (owner's phone, read-only, 2026-10-11)

Collected with `scripts/inspect-device.sh`-equivalent commands over adb + Magisk root.
Raw data is in `device-data/` (git-ignored: contains serials and partition images).

- Model `22081212UG`, product `ditingp_eea`, fingerprint
  `Xiaomi/ditingp_eea/diting:15/AQ3A.250226.002/OS3.0.5.0.VLFEUXM:user/release-keys`
- Vendor kernel `5.10.236-android12-9`, `ro.board.platform=taro`, soc0 `soc_id=530` (SM8475), rev 1.0, `hw_platform=MTP`
- Bootloader unlocked (`verifiedbootstate=orange`), active slot `_b`, boot device `soc/1d84000.ufshc`
- Live DT: `/sys/firmware/fdt` → `device-data/info/live.dts`
- Stock images: `boot_{a,b}`, `vendor_boot_{a,b}`, `dtbo_{a,b}`, `vbmeta_b`, `vbmeta_system_b`, `recovery_b`

## Trust notes

- The community Diting DTS was used as a cross-check only. Every constant in our DTS
  was compared with the live vendor DT of this unit (see `docs/KERNEL_PORTING.md`).
- The Nothing Pong DTS was used for binding/driver usage, not for Diting values.
- Realme Senna-B / Motorola Bronco / xiaomi-unicorn/thor/mondrian: not used. No public
  code for Senna-B/Bronco was located in this session; not claimed to exist.
