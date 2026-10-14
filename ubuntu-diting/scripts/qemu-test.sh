#!/bin/bash
# Emulator smoke test (QEMU virt, TCG): boots the built kernel with the
# Ubuntu initramfs and the rootfs image (read-only snapshot), logs in over
# SSH with the configured key and records evidence. Proves the kernel,
# initramfs and Ubuntu userspace work in general -- NOT that the phone boots.
. "$(dirname "$0")/lib.sh"
need qemu-system-aarch64 ssh
img="$OUT/ubuntu-diting-rootfs-$UBUNTU_SUITE-arm64.img"
kernel="$OUT/kernel/Image-$KERNEL_RELEASE"
initrd="$WORK/rootfs/boot/initrd.img-$KERNEL_RELEASE"
for f in "$img" "$kernel" "$initrd"; do [ -r "$f" ] || die "missing $f"; done
port="${QEMU_SSH_PORT:-2222}"
ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -p "$port")

log "booting in QEMU (TCG, slow; console log: output/logs/qemu-test-console.log)"
qemu-system-aarch64 -M virt -cpu max,pauth-impdef=on -smp 4 -m 2048 -nographic -no-reboot \
	-netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-device,netdev=n0 \
	-kernel "$kernel" -initrd "$initrd" \
	-drive "file=$img,format=raw,if=virtio,snapshot=on" \
	-append "console=ttyAMA0 root=LABEL=diting-root rw panic=-1" \
	> "$OUT/logs/qemu-test-console.log" 2>&1 &
qpid=$!
trap 'kill $qpid 2>/dev/null || true' EXIT
for _ in $(seq 1 90); do
	ssh "${ssh_opts[@]}" "${ROOTFS_USER:-ubuntu}@127.0.0.1" true 2>/dev/null && break
	sleep 10
done
ssh "${ssh_opts[@]}" "${ROOTFS_USER:-ubuntu}@127.0.0.1" '
	grep -E "^(PRETTY_NAME|VERSION_CODENAME)=" /etc/os-release
	echo "uname: $(uname -r)"; echo "arch: $(dpkg --print-architecture)"; echo "pid1: $(ps -p 1 -o comm=)"
	echo "state: $(systemctl is-system-running --wait)"; systemctl --failed --no-legend
	sudo -n true && echo "sudo: ok"
	sudo poweroff' | tee "$OUT/logs/qemu-test-session.txt" || die "SSH login failed (see console log)"
wait "$qpid" || true
trap - EXIT
grep -q "^state: running" "$OUT/logs/qemu-test-session.txt" || die "system not in 'running' state"
log "QEMU test passed (emulator only)"
