# Debugging

No UART is known on this phone (vendor cmdline has `msm_geni_serial.con_enabled=0`;
no documented test points). Debug channels, in order of usefulness:

1. **USB gadget** (`diting.debug=usb|hold`): NCM network 172.16.42.1 ↔ host
   172.16.42.2, ACM serial `/dev/ttyACM0` with a root shell. Requires dwc3 +
   eUSB2 PHY + PTN3222 to work.
2. **pstore/ramoops** at the vendor location and layout: `console-ramoops-0` (kernel
   console) and `pmsg-ramoops-0` (dmesg snapshots from the initramfs). Readable from
   Android after a warm reset (`/sys/fs/pstore`), see SAFE_TESTING.md.
3. **Screen** via simpledrm on the ABL splash buffer (`console=tty0`). The panel is a
   DSC command-mode panel; without a panel driver the image may freeze at the last
   splash frame. A black or frozen screen is *not* evidence of a hang.
4. Once Ubuntu runs: persistent journal (`/var/log/journal`) and `systemd-pstore`.

Useful kernel args for experiments (add via `--cmdline`/`ROOT_SPEC`):
`ignore_loglevel`, `initcall_debug`, `printk.devkmsg=on`, `panic=0` (keep a panic on
screen), `rd.debug`-style output: `debug`.
