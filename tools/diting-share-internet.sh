#!/bin/bash
# Share the host's internet with the Diting over the USB NCM link (NAT).
# Runtime-only host changes; "off" removes them again.
#   diting-share-internet.sh on|off [uplink-interface]
set -euo pipefail
action="${1:-on}"
up="${2:-$(ip route show default | awk '{print $5; exit}')}"
net=172.16.42.0/24
ipt=/usr/sbin/iptables
rules=(
	"-t nat POSTROUTING -s $net -o $up -j MASQUERADE"
	"FORWARD -s $net -o $up -j ACCEPT"
	"FORWARD -d $net -i $up -m state --state RELATED,ESTABLISHED -j ACCEPT"
)
case "$action" in
on)
	sudo /usr/sbin/sysctl -q -w net.ipv4.ip_forward=1
	for r in "${rules[@]}"; do
		# shellcheck disable=SC2086
		if [[ $r == "-t nat "* ]]; then
			# shellcheck disable=SC2086
			sudo $ipt -t nat -C ${r#-t nat } 2>/dev/null || sudo $ipt -t nat -A ${r#-t nat }
		else
			# shellcheck disable=SC2086
			sudo $ipt -C $r 2>/dev/null || sudo $ipt -A $r
		fi
	done
	echo "sharing $up with $net"
	;;
off)
	for r in "${rules[@]}"; do
		if [[ $r == "-t nat "* ]]; then
			# shellcheck disable=SC2086
			sudo $ipt -t nat -D ${r#-t nat } 2>/dev/null || true
		else
			# shellcheck disable=SC2086
			sudo $ipt -D $r 2>/dev/null || true
		fi
	done
	sudo /usr/sbin/sysctl -q -w net.ipv4.ip_forward=0
	echo "sharing off"
	;;
*) echo "usage: $0 on|off [uplink]" >&2; exit 2 ;;
esac
