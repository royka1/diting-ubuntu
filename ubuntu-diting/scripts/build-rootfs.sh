#!/bin/bash
# Build a genuine Ubuntu (default 26.04 "resolute") arm64 root filesystem
# with debootstrap from the official ports archive, install the Diting
# kernel and device packages, and pack it into an ext4 image file.
#
# Must run as root (debootstrap/chroot). Only writes below work/ and output/.
. "$(dirname "$0")/lib.sh"
need debootstrap chroot mkfs.ext4 e2fsck
[ "$(id -u)" = 0 ] || die "build-rootfs.sh must run as root (make rootfs uses sudo)"

# separate trees: a public image must never have seen the local firmware
if [ "$ROOTFS_PROFILE" = public ]; then
	ROOT="$WORK/rootfs-public"
	IMG_SUFFIX=-public
else
	ROOT="$WORK/rootfs"
	IMG_SUFFIX=
fi
IMG="$OUT/ubuntu-diting-rootfs-$UBUNTU_SUITE-arm64$IMG_SUFFIX.img"
case "$ROOTFS_PROFILE" in owner|public) ;; *) die "ROOTFS_PROFILE must be owner or public" ;; esac
# newest version of a local package (several revisions pile up in output/debs)
latest() { local f; f="$(ls "$OUT"/debs/$1 2>/dev/null | sort -V | tail -1)"; echo "${f:-$OUT/debs/$1}"; }
DEBS=("$OUT"/debs/linux-image-"$KERNEL_RELEASE"_*-"$KERNEL_DEB_REVISION"_arm64.deb
	"$(latest 'device-xiaomi-diting_*_all.deb')"
	"$(latest 'diting-firmware-setup_*_arm64.deb')"
	"$(latest 'libva-v4l2-stateful_*_arm64.deb')")
for d in "${DEBS[@]}"; do [ -f "$d" ] || die "missing $d; run 'make kernel packages' first"; done
# Device-signed firmware built locally by 'make firmware': owner images only.
# Public images get it on the phone itself (diting-firmware-setup).
FW_DEBS=("$(latest 'firmware-xiaomi-diting_*_all.deb')")
if [ "$ROOTFS_PROFILE" = public ]; then
	FW_DEBS=()
elif [ ! -f "${FW_DEBS[0]}" ]; then
	warn "no firmware-xiaomi-diting package (make firmware): extracted at first boot instead"
	FW_DEBS=()
fi
RPC_DEBS=("$OUT"/debs/fastrpc-diting_*_arm64.deb)
[ -f "${RPC_DEBS[0]}" ] || { warn "no fastrpc-diting package (make packages): calls without echo/noise cancellation modules"; RPC_DEBS=(); }
HRPC_DEBS=("$OUT"/debs/hexagonrpcd-diting_*_arm64.deb)
[ -f "${HRPC_DEBS[0]}" ] || { warn "no hexagonrpcd-diting package (make packages): no sensors"; HRPC_DEBS=(); }
SSC_DEBS=("$OUT"/debs/libssc-diting_*_arm64.deb "$OUT"/debs/iio-sensor-proxy_*diting*_arm64.deb)
if [ ! -f "${SSC_DEBS[0]}" ] || [ ! -f "${SSC_DEBS[1]}" ]; then
	warn "no libssc-diting/iio-sensor-proxy packages (make sensors): no sensor clients"
	SSC_DEBS=()
fi
# Optional: phoc with the refresh-rate fix (scripts/build-phoc.sh).
PHOC_DEBS=("$OUT"/debs/phoc_*diting*_arm64.deb)
[ -f "${PHOC_DEBS[0]}" ] || { warn "no patched phoc (scripts/build-phoc.sh): refresh-rate switching reverts"; PHOC_DEBS=(); }
# Optional: phosh that keeps the screen off on automatic wake-ups (scripts/build-phosh.sh)
PHOSH_DEBS=("$(latest 'phosh_*diting*_arm64.deb')" "$(latest 'phosh-common_*diting*_all.deb')"
	"$(latest 'libphosh-0.45-0_*diting*_arm64.deb')" "$(latest 'phosh-plugins_*diting*_arm64.deb')"
	"$(latest 'phosh-mobile-tweaks_*diting*_all.deb')")
for d in "${PHOSH_DEBS[@]}"; do
	[ -f "$d" ] || { warn "no patched phosh (scripts/build-phosh.sh): the screen lights up at every wake-up"; PHOSH_DEBS=(); break; }
done
# ModemManager with the netlink use-after-free fix (scripts/build-modemmanager.sh)
MM_DEBS=("$OUT"/debs/modemmanager_*diting*_arm64.deb "$OUT"/debs/libmm-glib0_*diting*_arm64.deb)
if [ ! -f "${MM_DEBS[0]}" ] || [ ! -f "${MM_DEBS[1]}" ]; then
	warn "no patched ModemManager (scripts/build-modemmanager.sh): it crashes reconnecting after suspend"
	MM_DEBS=()
fi
# libcamera with the diting sensor support: the runtime packages only
LIBCAMERA_DEBS=()
for p in libcamera0.7 libcamera-ipa libcamera-tools libcamera-v4l2 gstreamer1.0-libcamera; do
	for f in "$OUT"/debs/libcamera/"$p"_*diting*_arm64.deb; do
		[ -f "$f" ] && LIBCAMERA_DEBS+=("$f")
	done
done
[ ${#LIBCAMERA_DEBS[@]} -gt 0 ] || warn "no patched libcamera (scripts/build-libcamera.sh): cameras without sensor helpers"

mounts=()
cleanup() {
	local m
	for ((i = ${#mounts[@]} - 1; i >= 0; i--)); do
		m="${mounts[$i]}"
		if mountpoint -q "$m"; then umount -l "$m" || true; fi
	done
}
trap cleanup EXIT
bind() { mount --bind "$1" "$2"; mounts+=("$2"); }
in_root() { chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
	LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"; }

# debootstrap has no "resolute" script yet in Debian trixie; all Ubuntu
# releases since gutsy share the same script, so pass it explicitly.
script=/usr/share/debootstrap/scripts/$UBUNTU_SUITE
[ -e "$script" ] || script=/usr/share/debootstrap/scripts/gutsy

if [ "${FORCE_ROOTFS:-0}" = 1 ] || [ ! -f "$ROOT/.debootstrap-done" ]; then
	rm -rf "$ROOT"
	mkdir -p "$ROOT"
	log "debootstrap $UBUNTU_SUITE arm64 from $UBUNTU_MIRROR"
	foreign=()
	[ "$(uname -m)" = aarch64 ] || foreign=(--foreign)
	debootstrap --arch=arm64 --variant=minbase --components="$UBUNTU_COMPONENTS" \
		--keyring="$UBUNTU_KEYRING" "${foreign[@]}" \
		"$UBUNTU_SUITE" "$ROOT" "$UBUNTU_MIRROR" "$script"
	if [ ${#foreign[@]} -gt 0 ]; then
		# a binfmt entry with the F flag works in the chroot as it is;
		# otherwise the static interpreter has to be inside
		if ! grep -q '^flags:.*F' /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
			need qemu-aarch64-static
			cp /usr/bin/qemu-aarch64-static "$ROOT/usr/bin/"
		fi
		chroot "$ROOT" /debootstrap/debootstrap --second-stage
	fi
	touch "$ROOT/.debootstrap-done"
fi

for m in proc sys dev dev/pts; do bind "/$m" "$ROOT/$m"; done
cp /etc/resolv.conf "$ROOT/etc/resolv.conf.build"
mount --bind "$ROOT/etc/resolv.conf.build" "$ROOT/etc/resolv.conf" 2>/dev/null ||
	{ rm -f "$ROOT/etc/resolv.conf"; cp /etc/resolv.conf "$ROOT/etc/resolv.conf"; }
mounts+=("$ROOT/etc/resolv.conf")

log "configuring apt sources (deb822, signed official archive)"
rm -f "$ROOT/etc/apt/sources.list"
cat > "$ROOT/etc/apt/sources.list.d/ubuntu.sources" <<S
Types: deb
URIs: $UBUNTU_MIRROR
Suites: $UBUNTU_SUITE $UBUNTU_SUITE-updates $UBUNTU_SUITE-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
S
# Keep systemd services from starting inside the build chroot.
printf '#!/bin/sh\nexit 101\n' > "$ROOT/usr/sbin/policy-rc.d"
chmod 755 "$ROOT/usr/sbin/policy-rc.d"

mapfile -t pkgs < <(grep -v '^\s*#' "$UD/config/packages.list" | sed '/^\s*$/d')
in_root apt-get update
in_root apt-get -y full-upgrade
in_root apt-get -y install --no-install-recommends "${pkgs[@]}"

log "installing local Diting packages"
# Kernel command line for the on-device boot image hook (zz-diting-bootimg);
# written before the kernel package so its postinst already uses it.
# Public images: no diting.debug (its initramfs USB serial shell has no login).
if [ "$ROOTFS_PROFILE" = public ]; then
	DITING_ROOT_CMDLINE="$(echo "$DITING_ROOT_CMDLINE" | sed 's/ *diting\.debug=[^ ]*//')"
fi
if [ -n "${DITING_ROOT_CMDLINE:-}" ]; then
	mkdir -p "$ROOT/etc/diting"
	echo "$DITING_ROOT_CMDLINE" > "$ROOT/etc/diting/cmdline"
else
	rm -f "$ROOT/etc/diting/cmdline"
fi

mkdir -p "$ROOT/tmp/debs"
cp "${DEBS[@]}" "${FW_DEBS[@]}" "${RPC_DEBS[@]}" "${HRPC_DEBS[@]}" "${SSC_DEBS[@]}" "${PHOC_DEBS[@]}" "${MM_DEBS[@]}" "${LIBCAMERA_DEBS[@]}" "$ROOT/tmp/debs/"
# Device package first, so its initramfs config and hooks are in place
# when the kernel postinst runs update-initramfs.
in_root apt-get -y install --reinstall --no-install-recommends "/tmp/debs/${DEBS[1]##*/}"
in_root apt-get -y install --reinstall --no-install-recommends "/tmp/debs/${DEBS[0]##*/}"
in_root apt-get -y install --reinstall --no-install-recommends "/tmp/debs/${DEBS[2]##*/}" "/tmp/debs/${DEBS[3]##*/}"
[ ${#FW_DEBS[@]} -eq 0 ] ||
	in_root apt-get -y install --reinstall --no-install-recommends "/tmp/debs/${FW_DEBS[0]##*/}"
[ ${#RPC_DEBS[@]} -eq 0 ] ||
	in_root sh -c 'apt-get -y install --reinstall --no-install-recommends /tmp/debs/fastrpc-diting_*_arm64.deb'
[ ${#HRPC_DEBS[@]} -eq 0 ] ||
	in_root sh -c 'apt-get -y install --reinstall --no-install-recommends /tmp/debs/hexagonrpcd-diting_*_arm64.deb'
[ ${#SSC_DEBS[@]} -eq 0 ] ||
	in_root sh -c 'apt-get -y install --reinstall --allow-downgrades --no-install-recommends /tmp/debs/libssc-diting_*_arm64.deb /tmp/debs/iio-sensor-proxy_*diting*_arm64.deb'
if [ ${#LIBCAMERA_DEBS[@]} -gt 0 ]; then
	lc=()
	for f in "${LIBCAMERA_DEBS[@]}"; do lc+=("/tmp/debs/${f##*/}"); done
	in_root apt-get -y install --allow-downgrades --no-install-recommends "${lc[@]}"
fi
[ ${#PHOC_DEBS[@]} -eq 0 ] || [ "${ROOTFS_DESKTOP:-none}" = none ] ||
	in_root sh -c 'apt-get -y install --reinstall --allow-downgrades --no-install-recommends /tmp/debs/phoc_*diting*_arm64.deb'
[ ${#MM_DEBS[@]} -eq 0 ] ||
	in_root sh -c 'apt-get -y install --allow-downgrades --no-install-recommends /tmp/debs/modemmanager_*diting*_arm64.deb /tmp/debs/libmm-glib0_*diting*_arm64.deb'
rm -rf "$ROOT/tmp/debs"

# Optional desktop stage (needs display/touch; GPU-less software rendering
# is configured by device-xiaomi-diting).
case "${ROOTFS_DESKTOP:-}" in
"") ;;
phosh)
	log "installing Phosh (phosh-core: greetd + phrog login)"
	in_root apt-get -y install phosh-core
	;;
phosh-full)
	log "installing the phone desktop (config/packages-desktop.list)"
	install -d "$ROOT/etc/apt/keyrings"
	install -m 644 "$UD/config/apt/packages.mozilla.org.asc" "$ROOT/etc/apt/keyrings/"
	install -m 644 "$UD/config/apt/mozilla.sources" "$ROOT/etc/apt/sources.list.d/"
	install -m 644 "$UD/config/apt/mozilla.pref" "$ROOT/etc/apt/preferences.d/mozilla"
	in_root apt-get update
	mapfile -t dpkgs < <(grep -v '^\s*#' "$UD/config/packages-desktop.list" | sed '/^\s*$/d')
	in_root apt-get -y install "${dpkgs[@]}"
	# postmarketOS' mobile Firefox UI, not in Ubuntu (make mobile-config-firefox)
	mcf="$(latest 'mobile-config-firefox_*_all.deb')"
	[ -f "$mcf" ] || die "missing $mcf (scripts/build-mobile-config-firefox.sh)"
	cp "$mcf" "$ROOT/tmp/"
	in_root apt-get -y install --reinstall "/tmp/${mcf##*/}"
	rm -f "$ROOT/tmp/${mcf##*/}"
	[ "$(in_root dpkg-query -W -f '${Version}' firefox)" != "${MOZ_FIREFOX_BAD:-1:1snap1}" ] ||
		die "firefox came from Ubuntu (snap wrapper), not from packages.mozilla.org"
	log "preseeding snap Chromium (installed by snapd at first boot)"
	# The generic classic model and its signature come from the snap store;
	# prepare-image adds the snaps' assertions. Bases and content snaps
	# must be listed explicitly.
	in_root sh -ec 'snap known --remote model series=16 brand-id=generic model=generic-classic > /tmp/generic-classic.model
		rm -rf /tmp/seedroot /var/lib/snapd/seed && mkdir /tmp/seedroot
		cd /tmp && snap prepare-image --classic --arch=arm64 \
			--snap=snapd --snap=bare --snap=core24 --snap=core26 --snap=chromium \
			--snap=gnome-46-2404 --snap=gtk-common-themes --snap=mesa-2404 --snap=cups \
			generic-classic.model /tmp/seedroot
		mv /tmp/seedroot/var/lib/snapd/seed /var/lib/snapd/seed
		rm -rf /tmp/seedroot /tmp/generic-classic.model'
	in_root sh -c 'grep "^  file:" /var/lib/snapd/seed/seed.yaml'
	;;
*) die "unknown ROOTFS_DESKTOP '$ROOTFS_DESKTOP' (supported: phosh, phosh-full)" ;;
esac
if [ -n "${ROOTFS_DESKTOP:-}" ] && [ ${#PHOSH_DEBS[@]} -gt 0 ]; then
	ph=()
	for f in "${PHOSH_DEBS[@]}"; do cp "$f" "$ROOT/tmp/"; ph+=("/tmp/${f##*/}"); done
	in_root apt-get -y install --allow-downgrades --no-install-recommends "${ph[@]}"
	rm -f "${ph[@]/#/$ROOT}"
fi

log "integrity check of all installed files (dpkg --verify)"
# Only conffiles may differ from the packaged md5sums.
if bad="$(in_root dpkg --verify 2>&1 | grep -v ' c /' || true)" && [ -n "$bad" ]; then
	echo "$bad" | head -20
	die "dpkg --verify found modified packaged files (host corruption?)"
fi

log "system configuration"
echo "$ROOTFS_HOSTNAME" > "$ROOT/etc/hostname"
cat > "$ROOT/etc/hosts" <<H
127.0.0.1	localhost
127.0.1.1	$ROOTFS_HOSTNAME
::1		localhost ip6-localhost ip6-loopback
H
sed -i "s/^# *\($ROOTFS_LOCALE\)/\1/" "$ROOT/etc/locale.gen"
in_root locale-gen
echo "LANG=$ROOTFS_LOCALE" > "$ROOT/etc/default/locale"
ln -sf "/usr/share/zoneinfo/$ROOTFS_TIMEZONE" "$ROOT/etc/localtime"
echo "$ROOTFS_TIMEZONE" > "$ROOT/etc/timezone"
cat > "$ROOT/etc/fstab" <<F
# Root is selected by the kernel command line (root=PARTLABEL=... or
# root=LABEL=...), see docs/SAFE_TESTING.md.
LABEL=diting-root	/	ext4	defaults,noatime,x-systemd.growfs	0	1
F
mkdir -p "$ROOT/var/log/journal"   # persistent journal for post-mortem logs

# The usb0 NetworkManager profile comes with device-xiaomi-diting.

# User: no password (locked); key-based SSH only. Keys come from the build
# host (ROOTFS_SSH_PUBKEYS, default ~/.ssh/id_*.pub of the invoking user).
user="${ROOTFS_USER:-ubuntu}"
# video/render: cameras (media/video/v4l-subdev nodes, udmabuf) and the GPU
# at login already; the session's uaccess ACLs arrive too late for
# WirePlumber's libcamera monitor, which then finds no camera.
in_root id "$user" >/dev/null 2>&1 || in_root useradd -m -s /bin/bash -G sudo,adm,video,render "$user"
in_root usermod -aG video,render "$user"
if [ "$ROOTFS_PROFILE" = public ]; then
	# A known default password (the phosh lock screen PIN), documented for
	# users to change with passwd. sshd accepts keys only, so it is not
	# usable over the network.
	echo "$user:${ROOTFS_PASSWORD:-147147}" | in_root chpasswd
else
	in_root passwd -l "$user" >/dev/null
fi
in_root passwd -l root >/dev/null
if [ "$ROOTFS_PROFILE" = owner ]; then
	# the account has no password, so sudo cannot ask for one
	echo "$user ALL=(ALL) NOPASSWD:ALL" > "$ROOT/etc/sudoers.d/90-diting-user"
	chmod 440 "$ROOT/etc/sudoers.d/90-diting-user"
else
	rm -f "$ROOT/etc/sudoers.d/90-diting-user"
fi
keys="${ROOTFS_SSH_PUBKEYS:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)/.ssh/id_ed25519.pub}"
[ "$ROOTFS_PROFILE" = owner ] || keys=""
install -d -m 700 "$ROOT/home/$user/.ssh"
: > "$ROOT/home/$user/.ssh/authorized_keys"
for k in $keys; do
	[ -f "$k" ] && grep -E '^(ssh-|ecdsa-)' "$k" >> "$ROOT/home/$user/.ssh/authorized_keys"
done
[ -s "$ROOT/home/$user/.ssh/authorized_keys" ] || [ "$ROOTFS_PROFILE" = public ] ||
	warn "no SSH public key installed; set ROOTFS_SSH_PUBKEYS"
in_root chown -R "$user:$user" "/home/$user/.ssh"
chmod 600 "$ROOT/home/$user/.ssh/authorized_keys"
cat > "$ROOT/etc/ssh/sshd_config.d/10-diting.conf" <<C
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
C
# No build-time SSH host keys: Ubuntu's sshd-keygen.service creates them on
# first boot (empty machine-id). sshd itself is socket-activated (ssh.socket,
# Ubuntu default); do not also enable ssh.service (both would bind port 22).
rm -f "$ROOT"/etc/ssh/ssh_host_*
in_root systemctl enable ssh.socket >/dev/null
in_root systemctl disable ssh.service >/dev/null 2>&1 || true
rm -rf "$ROOT/etc/systemd/system/ssh.service.d"
# All accounts are password-locked, so a getty on the USB ACM port is useless;
# access is SSH over the NCM gadget (diting-usb-gadget.service, via udev).
in_root systemctl disable serial-getty@ttyGS0.service >/dev/null 2>&1 || true

# Build metadata
cat > "$ROOT/etc/diting-build" <<B
BUILD_DATE=$(date -u +%FT%TZ)
UBUNTU_SUITE=$UBUNTU_SUITE
KERNEL_RELEASE=$KERNEL_RELEASE
KERNEL_COMMIT=$KERNEL_COMMIT
PATCHES_DIGEST=$(patches_digest)
STATUS=UNTESTED ON DEVICE
B

log "cleanup"
rm -f "$ROOT/usr/sbin/policy-rc.d"
in_root apt-get clean
rm -rf "$ROOT"/var/lib/apt/lists/* "$ROOT"/tmp/* "$ROOT/etc/resolv.conf.build"
# First boot must be detected (sshd-keygen.service, presets): "uninitialized"
# is systemd's explicit marker; the D-Bus copy must not seed an old ID.
echo uninitialized > "$ROOT/etc/machine-id"
rm -f "$ROOT/var/lib/dbus/machine-id"
ln -s /etc/machine-id "$ROOT/var/lib/dbus/machine-id"
cleanup
mounts=()
ln -sf ../run/systemd/resolve/stub-resolv.conf "$ROOT/etc/resolv.conf"

# shellcheck disable=SC2016 # dpkg-query format string
in_root_pkglist() { chroot "$ROOT" dpkg-query -W -f '${Package}\t${Version}\t${Architecture}\n'; }
in_root_pkglist > "$OUT/rootfs-packages-$UBUNTU_SUITE$IMG_SUFFIX.tsv"

if [ "$ROOTFS_PROFILE" = public ]; then
	log "checking that no device firmware or private data is in the public tree"
	# (a Recommends makes dpkg list the name as "un", not installed)
	[ "$(chroot "$ROOT" dpkg-query -W -f '${db:Status-Abbrev}' firmware-xiaomi-diting 2>/dev/null)" != "ii " ] ||
		die "firmware-xiaomi-diting is installed in the public tree"
	leaks="$(cd "$ROOT" && find usr/lib/firmware/qcom/sm8475 usr/lib/firmware/qca/diting \
		usr/lib/firmware/cirrus/*diting* usr/lib/firmware/updates \
		usr/share/qcom/sm8475 -type f 2>/dev/null || true)"
	[ -z "$leaks" ] || { echo "$leaks" | head; die "device firmware files in the public tree"; }
	[ ! -s "$ROOT/home/$user/.ssh/authorized_keys" ] || die "SSH keys in the public tree"
	! ls "$ROOT"/etc/NetworkManager/system-connections/* >/dev/null 2>&1 ||
		die "NetworkManager connections in the public tree"
fi

log "creating ext4 image $IMG ($ROOTFS_IMAGE_SIZE)"
rm -f "$IMG"
truncate -s "$ROOTFS_IMAGE_SIZE" "$IMG"
mkfs.ext4 -q -L diting-root -b 4096 -d "$ROOT" "$IMG"
e2fsck -fn "$IMG" >/dev/null
[ -n "${SUDO_UID:-}" ] && chown "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$IMG" "$OUT/rootfs-packages-$UBUNTU_SUITE$IMG_SUFFIX.tsv"
log "rootfs image: $IMG (UNTESTED ON DEVICE)"
