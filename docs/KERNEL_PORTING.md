# Kernel porting: Diting on Linux 7.2.10

Base: signed stable tag `v7.2.10`. Local branch `diting/v7.2.10` in `kernel/upstream`,
exported to `kernel/patches/` (applied with `patch -p1` onto a `git archive` export
by `scripts/prepare-kernel.sh`). Config: arm64 `defconfig` + `kernel/config/diting.config`.

## Gap analysis: upstream 7.2.10 vs. what Diting needs

| Area | Upstream 7.2.10 | Community `next` (6.17-rc1) | Diting need | Action |
| --- | --- | --- | --- | --- |
| SoC DT | `sm8450.dtsi` only, no `sm8475.dtsi` | `sm8475.dtsi` (compat overrides, eUSB2, UFS PHY, PCIe WIP, GPU hack) | SM8475 deltas | **Patch 0003**: new `sm8475.dtsi` with only binding-valid deltas (clock controllers, eUSB2 PHY, v6 UFS PHY). PCIe/GPU deltas left out. |
| Clock controllers | `qcom,sm8475-{gcc,dispcc,gpucc,camcc,videocc}` supported | same | yes | used as-is |
| TLMM | `qcom,sm8450-tlmm`, 211 GPIOs; no sm8475 compatible | `qcom,sm8475-tlmm` (not in upstream driver) | reserved GPIOs 28–31, 36–39 | use sm8450 TLMM + `gpio-reserved-ranges` (vendor `qcom,gpios-reserved`). Community DTS had TLMM **disabled** — most likely because of missing reserved ranges (accessing secure GPIOs faults). UNTESTED. |
| UFS PHY | `qcom,sm8475-qmp-ufs-phy` supported (v6 offsets, G4) | node at 0x1d80000 | yes | node in `sm8475.dtsi` |
| UFS host | `qcom,sm8450-ufshc`, freq table max 300 MHz | commented out in Diting DTS | rootfs | enabled with vendor supplies; kept the 300 MHz table (vendor uses 850 MHz; higher rates later) |
| USB HS PHY | `phy-snps-eusb2` (sm8550 compatible); no sm8475 compat in binding | `qcom,sm8475-snps-eusb2-phy` | debug USB | **Patch 0001** adds compatible to binding (falls back to sm8550) |
| eUSB2 repeater | `nxp,ptn3222` driver (simple: supplies + reset) | out-of-tree `nxp,eusb2-repeater` with tuning sequences | debug USB | use `nxp,ptn3222` at 0x4f. Vendor tuning (`qcom,param-override-seq`) not applied — may matter for signal quality. INFERRED chip identity. |
| dwc3 | flattened `qcom,sm8450-dwc3` | legacy glue + `select-utmi-as-pipe-clk` | USB2 peripheral | `dr_mode=peripheral`, `maximum-speed=high-speed`, only usb2 phy, `qcom,select-utmi-as-pipe-clk` |
| SoC match tables | `qcom,sm8450` in cpufreq-dt blocklist, UBWC, pd-mapper | n/a | avoid cpufreq-dt conflicting with cpufreq-hw | **Patch 0002** adds `qcom,sm8475` |
| PMICs | pm8350/b/c, pm8450, pmk8350, pmr735a dtsi | same | regulators/keys | included; regulators from vendor constraints. PM8350B L1 and PMR735B not described. |
| Reserved memory | SM8450 reference map | partial Diting fixes | must match board | Diting overrides for xbl_ramdump, xbl_sc, ADSP; rmtfs removed; ramoops at vendor location |
| Display | simplefb/simpledrm; MSM DRM supports SM8450 | simple-framebuffer only | early console | simple-framebuffer on splash. Command-mode DSC panel: **may show nothing** after ABL handoff (no autorefresh). No panel driver yet. |
| GPU (A730) | adreno 730 for SM8450 | sm8475 OPP table WIP, "hack" disabling | later | not enabled |
| PCIe0 (WLAN) | SM8450 PCIe0 description | SM8475 uses SM8550-style PCIe, WIP | WLAN | not enabled; SM8450 node stays disabled |
| Remoteprocs | ADSP/CDSP/SLPI/MPSS for SM8450 | – | audio/modem/sensors | ADSP (0016) and MPSS (0029) enabled; CDSP/SLPI not |
| IPA | none for SM8450 in 7.2 (v5.0/v5.2/v5.5 only) | vendor `ipa3` v5.1 (`qcom,ipa-hw-ver = <22>`) | mobile data | v5.1 data + SM8450 node from the XEC kernel (0030–0040, author ZXlieC, kept as-is), plus local binding compatible (0041), IRQ SPI 654 per vendor DT (0042, XEC used 655 from SM8350) and Diting enablement with `ipa_gsi_mem` (0043) |

## Patch series (`kernel/patches/`)

1. `0001 dt-bindings: arm: qcom: phy: Add SM8475 and Xiaomi Diting compatibles`
2. `0002 soc: qcom: cpufreq: Treat SM8475 like SM8450 in SoC match tables`
3. `0003 arm64: dts: qcom: Add SM8475 SoC dtsi`
4. `0004 arm64: dts: qcom: Add Xiaomi 12T Pro / Redmi K50 Ultra (diting)`

These are local experiment patches, generated with AI assistance; they are **not**
suitable for submission to Linux/postmarketOS/Nura without independent review
and re-authoring according to those projects' policies.

## Provenance of DTS constants

All from the owner's live vendor DT (`device-data/info/live.dts`), cross-checked with
the community DTS:

- regulators: `qcom,resource-name` + `regulator-min/max-microvolt` of `rpmh-regulator-*` nodes
- UFS: `ufshc@1d84000` (`reset-gpios <&tlmm 0xd2 1>`, vcc/vccq supplies, max currents), `ufsphy_mem@1d80000`
- USB: `hsphy@88e3000`, `i2c@994000/eusb2_repeater@4f`, `ssusb@a600000`
- keys: `gpio_keys/vol_up`, `pon resin`
- reserved memory: `reserved-memory` node; ramoops layout also cross-checked with
  `/sys/module/ramoops/parameters/*` on Android
- framebuffer: `splash_region` + panel timing `qcom,mdss-dsi-panel-width/height` (0x4c4 x 0xa98)
- TLMM reserved: `pinctrl@f000000 qcom,gpios-reserved`

## ABL DTB selection ids

The vendor_boot DTB section contains 14 SoC base DTBs (board-id `0 0`) and the board
data comes from `dtbo` overlays (board-id `0x10008`). ABL needs `qcom,msm-id` and
`qcom,board-id` on our DTB, but upstream bindings forbid them for SM8450-class SoCs.
They are therefore added to a copy of the DTB at boot-image time by `diting-mkbootimg`
(`fdtput`), values from the live DT: msm-id `531/540/530 0x10000`, board-id `0x10008 0`.
Whether ABL selects our DTB with these ids is **UNTESTED**.

## Build checks done (host)

- `make dtbs` W=1: no new warnings (two pre-existing `sm8450.dtsi` DSI warnings also
  appear for `sm8450-hdk`)
- `dtbs_check` (dtschema 2026.9): clean for `sm8475-xiaomi-diting.dtb`
- `dt_binding_check` for `arm/qcom.yaml`, `phy/qcom,snps-eusb2-phy.yaml`: clean
- kernelrelease check: `7.2.10-diting`
