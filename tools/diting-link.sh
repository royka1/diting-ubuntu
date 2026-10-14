#!/bin/bash
# Host side of the Diting USB network: find the cdc_ncm interface of the
# phone's gadget, keep NetworkManager off it and give it 172.16.42.2/24.
# Runtime-only changes; nothing persistent on the host.
set -euo pipefail
for _ in $(seq 1 15); do
	for n in /sys/class/net/*; do
		[ "$(basename "$(readlink -f "$n/device/driver" 2>/dev/null)")" = cdc_ncm ] && IF="$(basename "$n")"
	done
	[ -n "${IF:-}" ] && break
	sleep 1
done
[ -n "${IF:-}" ] || { echo "no cdc_ncm interface (phone gadget not up)" >&2; exit 1; }
sudo nmcli dev set "$IF" managed no
ip -4 addr show dev "$IF" | grep -q 172.16.42.2 || sudo ip addr add 172.16.42.2/24 dev "$IF"
sudo ip link set "$IF" up
ping -c1 -W2 -I "$IF" 172.16.42.1 >/dev/null && echo "link up: $IF" || { echo "no ping reply on $IF" >&2; exit 1; }
