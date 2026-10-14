# Xiaomi Diting: Ubuntu arm64 on upstream stable Linux.
# See README.md. Nothing in here flashes or boots the phone.

S := scripts
SUDO ?= sudo -E

.PHONY: help check-host sources check-latest-kernel update-kernel kernel dtbs phoc sensors libcamera \
	dtbs-check packages vaapi firmware-setup firmware rootfs release initramfs boot image verify repro-check qemu-test \
	inspect-device lint clean distclean

help:
	@sed -n 's/^## //p' $(MAKEFILE_LIST)

## check-host           verify host tools
check-host:
	$(S)/check-host.sh
## sources              fetch locked kernel (signature-checked) and references
sources:
	$(S)/fetch-sources.sh
## check-latest-kernel  compare kernel.lock with kernel.org (read-only)
check-latest-kernel:
	$(S)/check-latest-kernel.sh
## update-kernel        deliberately move kernel.lock to the newest stable
update-kernel:
	$(S)/update-kernel.sh
## kernel               Image, DTBs, modules and linux-*.deb (bindeb-pkg)
kernel:
	$(S)/build-kernel.sh
## dtbs                 build only the Diting DTB
dtbs:
	$(S)/build-dtbs.sh
## dtbs-check           dtbs_check/dt_binding_check for the Diting DTB
dtbs-check:
	$(S)/build-dtbs.sh --check
## packages             device-xiaomi-diting, fastrpc-diting, hexagonrpcd-diting debs (arm64 host)
packages:
	$(S)/build-packages.sh
	$(S)/build-fastrpc.sh
	$(S)/build-hexagonrpc.sh
## vaapi                libva-v4l2-stateful (VA-API driver for the iris decoder; arm64 buildd chroot)
vaapi:
	$(S)/build-libva-v4l2-stateful.sh
## firmware-setup       diting-firmware-setup (first-boot firmware extraction; arm64 buildd chroot)
firmware-setup:
	$(S)/build-firmware-setup.sh
## firmware             firmware package from owner-supplied blobs (local only)
firmware:
	$(S)/build-firmware.sh
## sensors              libssc-diting + iio-sensor-proxy 3.9 with SSC (needs an existing rootfs, arm64 host)
sensors:
	$(S)/build-sensors.sh
## libcamera            Ubuntu libcamera + diting sensor support (needs an existing rootfs, arm64 host)
libcamera:
	$(S)/build-libcamera.sh
## phoc                 Ubuntu phoc + refresh-rate fix (needs an existing rootfs, arm64 host)
phoc:
	$(S)/build-phoc.sh
## rootfs               Ubuntu rootfs + ext4 image (needs root, uses sudo; ROOTFS_PROFILE=owner|public)
rootfs: kernel packages vaapi firmware-setup
	$(SUDO) $(S)/build-rootfs.sh
## initramfs            regenerate the initramfs inside the rootfs (initramfs-tools)
initramfs:
	$(SUDO) $(S)/build-initramfs.sh
## boot                 boot/vendor_boot/dtbo images (BOOT_MODE=debug|rootfs)
boot:
	$(S)/build-boot-image.sh
## image                full chain: kernel packages rootfs boot
image: rootfs
	$(S)/build-boot-image.sh
	$(S)/verify.sh
## release              public image (no firmware, default PIN) + boot images, packed for download
release:
	ROOTFS_PROFILE=public $(SUDO) $(S)/build-rootfs.sh
	$(S)/build-release.sh
## repro-check          second full kernel build, compare bit for bit (slow)
repro-check:
	$(S)/check-reproducible.sh
## qemu-test            boot kernel + rootfs image in QEMU (emulator only, not the phone)
qemu-test:
	$(S)/qemu-test.sh
## verify               non-destructive checks of all generated artifacts
verify:
	$(S)/verify.sh
## inspect-device       read-only adb dump of boot images/partition info
inspect-device:
	$(S)/inspect-device.sh
## lint                 shellcheck + git diff --check
lint:
	shellcheck -x $(S)/*.sh packages/device-xiaomi-diting/src/* \
		packages/device-xiaomi-diting/initramfs-tools/hooks/* \
		packages/device-xiaomi-diting/initramfs-tools/scripts/init-top/* \
		packages/device-xiaomi-diting/etc/zz-diting-bootimg
	cd .. && git diff --check
## clean                remove work/ (keeps output/ and downloads)
clean:
	$(SUDO) rm -rf work
## distclean            remove work/ and output/
distclean: clean
	rm -rf output
