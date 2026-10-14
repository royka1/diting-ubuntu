# Hardware: Xiaomi 12T Pro (diting), owner's unit

Values marked **M** were measured on the owner's 22081212UG unit (2026-10-11).
**S** means confirmed from a source file only. **I** means inferred.

## Identity

| Item | Value | |
| --- | --- | --- |
| Variant | Xiaomi 12T Pro, 22081212UG, EEA (`ditingp_eea`) | M |
| SoC | SM8475 "Cape", soc_id 530, revision 1.0 | M |
| Platform | `taro` (Android), `hw_platform=MTP` | M |
| Android | 15, HyperOS OS3.0.5.0.VLFEUXM, vendor 12, kernel 5.10.236-android12-9 | M |
| Bootloader | unlocked, orange state, Magisk root | M |
| Panel | `qcom,mdss_dsi_l12_36_02_0b_dsc_cmd` "xiaomi 36 02 0b mp cmd mode dsc dsi panel", 1220x2712, 60 Hz in the selected timing, DSC (slice 610x12), 30 bpp, command mode | M |
| RAM | System RAM ranges up to 0xa7fffffff in `/proc/iomem` | M |

## Storage / partitions

- UFS host at 0x1d84000, UFS PHY at 0x1d80000 (0x2000, v6 layout), ICE at 0x1d88000 **M**
- LUNs sda..sdf. Selected by-name links (**M**):

| Partition | Device | Notes |
| --- | --- | --- |
| boot_a / boot_b | sde14 / sde43 | 192 MiB; identical contents |
| vendor_boot_a / vendor_boot_b | sde25 / sde54 | 96 MiB; **slot A is all zeros** |
| dtbo_a / dtbo_b | sde18 / sde47 | 24 MiB; **slot A is all zeros** |
| recovery_a / recovery_b | sde28 / sde56 | |
| vbmeta_a/_b, vbmeta_system_a/_b | sde17/sde46, sda29/sda30 | |
| super | sda28 | dynamic partitions (system, vendor, ...) |
| userdata | sda37 | Android data, encrypted |
| xbl/abl/tz/... | sdb*/sdc*/sde* | slot A and B **differ** (older firmware in A) |

No `init_boot` partition exists.

## Power (RPMh regulators, vendor DT constraints) — M

| PMIC id | Regulators described (min–max µV) |
| --- | --- |
| b (PM8350) | s10 1.8V, s11 0.382–1.17V, s12 1.224–2.04V, l1 0.83–0.92, l2 2.7–3.3, l3 0.87–0.97, l5 0.72–0.958, l6 1.2–1.216, l7 2.4–3.544, l9 1.2–1.304 |
| c (PM8350C) | s1 1.8–2.024, s10 1.052–1.17, bob 3.008–3.96, l1..l13 (see DTS); **l3 3.3V always-on** |
| h (PM8450) | s3 0.47–0.57, l2, l3, l4 |
| e (PMR735A) | s2, s3, l1–l7 |
| d (PM8350B) l1, f (PMR735B) l1/2/4/5/6 | present in vendor DT, **not described yet** |

## Board wiring used so far — M

| Function | Wiring |
| --- | --- |
| UFS | reset TLMM 210 active-low, VCC=L7B, VCCQ=L9B, PHY vdda-phy=L5B, vdda-pll=L10C |
| USB HS PHY | eUSB2 at 0x88e3000, vdd=L5B, vdda12=L10C |
| eUSB2 repeater | I2C5 (QUP0 SE5 @0x994000) addr 0x4f, vdd18=S10B, vdd3=L2B, reset=PM8350C GPIO7; vendor compatible `nxp,eusb2-repeater` (**I**: NXP PTN3222) |
| dwc3 | vendor uses `maximum-speed = "high-speed"` |
| Keys | power = PMK8350 PON pwrkey, vol-down = PMK8350 RESIN, vol-up = PM8350 GPIO6 active-low |
| TLMM reserved | GPIO 28–31, 36–39 (`qcom,gpios-reserved`) |
| Other I2C5 devices | fsa4480 @0x42, wl2866d @0x28 (camera PMIC); I2C bus 1: NFC sn-nci @0x28; bus 2: two cs35l41 amps @0x40/0x42 |

## Memory map (reserved, vendor DT) — M

Diting differs from upstream `sm8450.dtsi` in: `xbl_ramdump` (0xa6b80000, 0x280000),
`xbl_sc` (0xa6e00000), ADSP (0x9fd00000, 0x3100000). The SM8450 rmtfs location
(0x9fd00000) overlaps the Diting ADSP region; vendor rmtfs is dynamic. Continuous
splash at 0xb8000000 (0x2b00000). Ramoops at 0xa7000000 (4 MiB, console 2 MiB,
pmsg 2 MiB, no dmesg records, no ECC).
