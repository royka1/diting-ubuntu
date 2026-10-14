# Decisions

| # | Decision | Status | Reason |
| --- | --- | --- | --- |
| D1 | Workspace root is `~/linux-diting` (owner's existing dir with CLAUDE.md), not `~/diting-ubuntu` | accepted | CLAUDE.md: preserve the owner's workspace |
| D2 | Kernel base: signed stable tag v7.2.10 + local patches; community `next` (6.17-rc1) is reference only | accepted | kernel policy |
| D3 | Kernel source exported with `git archive` + `patch`, built out-of-tree in `work/` | accepted | no `.git` → no SCM suffix, `kernelrelease` = `7.2.10-diting` exactly; stale-tree detection via a digest of lock+patches+fragment |
| D4 | Write a reduced `sm8475.dtsi` instead of copying the community one | accepted | community file has PCIe WIP, a "[hack]" GPU/UFS commit and a non-upstream TLMM compatible |
| D5 | TLMM enabled with `gpio-reserved-ranges` instead of disabled | accepted (UNTESTED) | vendor DT lists the secure GPIOs; UFS reset needs TLMM 210 |
| D6 | eUSB2 repeater as `nxp,ptn3222` (upstream driver) | accepted (INFERRED chip) | same I2C address/supplies/reset; vendor tuning sequence not supported upstream |
| D7 | `qcom,msm-id`/`qcom,board-id` added with `fdtput` at image time, not in DTS | accepted | upstream schema forbids them on SM8450-class; ABL needs them |
| D8 | Boot image = header v4 boot.img (kernel only) + vendor_boot.img (DTB, initramfs, cmdline) | accepted | measured stock layout; same as pmOS boot-deploy for v3/v4 |
| D9 | Vendor dtbo is cleared by the owner with `fastboot erase dtbo` (after backup); no placeholder dtbo generated | accepted (owner instruction) | ABL would otherwise apply vendor overlays to the mainline DTB |
| D10 | No slot switching for tests | accepted | slot A has empty vendor_boot/dtbo and older bootloader firmware |
| D11 | Uncompressed `Image` in boot.img, no appended DTB | accepted | stock kernel is an uncompressed Image; DTB lives in vendor_boot for v4 |
| D12 | Kernel debs via upstream `make bindeb-pkg` (`linux-image-7.2.10-diting`, headers, libc-dev); DTBs shipped inside linux-image | accepted | standard Debian/Ubuntu kernel layout; no separate dtb package needed |
| D13 | `device-xiaomi-diting` builds boot images on the device in `/boot/diting/` from kernel postinst / initramfs post-update hooks; never flashes | accepted | Ubuntu-native kernel updates without pmOS tooling; flashing stays manual |
| D14 | Ubuntu initramfs-tools with `MODULES=list` and built-in storage/USB drivers | accepted | keeps vendor_boot ≤ 96 MiB; root mount does not depend on module loading |
| D15 | Debug: `diting.debug=hold/usb` → USB NCM + ACM root shell + dmesg to pstore pmsg; ramoops identical to vendor layout | accepted | logs readable from Android `/sys/fs/pstore` after a warm reboot; no UART available |
| D16 | rootfs via `debootstrap` (gutsy script) from ports.ubuntu.com, deb822 sources with Signed-By | accepted | Debian trixie debootstrap has no `resolute` script; all Ubuntu suites share gutsy |
| D17 | No root partition chosen; rootfs is an image file only | accepted | no safe partition approved by the owner yet |
| D18 | Locked user, key-only SSH, NOPASSWD sudo for that user, host keys generated on first boot | accepted | no passwords baked in; access only over local USB |
| D19 | `pmbootstrap` not used | accepted | layout is fully known; mkbootimg + fdtput suffice |
| D20 | Docker not used | accepted | native arm64 host |
| R1 | Copy downstream DT nodes / vendor drivers | rejected | policy |
| R2 | Use `/dev/sda28` (super) or any raw path for root | rejected | unverified, destructive |
| R3 | Use community 6.17-rc1 kernel as deliverable | rejected | kernel policy |
