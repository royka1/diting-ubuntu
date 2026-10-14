#!/bin/bash
# Fetch the locked upstream stable kernel and the read-only reference trees.
# Never resets or modifies an existing checkout.
. "$(dirname "$0")/lib.sh"
need git gpg

fetch_kernel() {
	if [ ! -d "$KERNEL_GIT/.git" ]; then
		log "cloning $KERNEL_TAG from $KERNEL_GIT_URL"
		git clone --depth 1 -b "$KERNEL_TAG" "$KERNEL_GIT_URL" "$KERNEL_GIT"
	fi
	git -C "$KERNEL_GIT" cat-file -e "$KERNEL_TAG_OBJECT" 2>/dev/null ||
		git -C "$KERNEL_GIT" fetch --depth 1 origin tag "$KERNEL_TAG"
	[ "$(git -C "$KERNEL_GIT" rev-parse "$KERNEL_TAG")" = "$KERNEL_TAG_OBJECT" ] ||
		die "tag $KERNEL_TAG does not resolve to locked tag object $KERNEL_TAG_OBJECT"
	[ "$(git -C "$KERNEL_GIT" rev-parse "$KERNEL_TAG^{commit}")" = "$KERNEL_COMMIT" ] ||
		die "tag $KERNEL_TAG does not point to locked commit $KERNEL_COMMIT"

	# Verify the signed tag with a private keyring holding the signer key.
	export GNUPGHOME="$KERNEL_DIR/.gnupg"
	mkdir -p "$KERNEL_DIR"
	[ -d "$GNUPGHOME" ] || mkdir -m 700 "$GNUPGHOME"
	gpg --list-keys "$KERNEL_TAG_SIGNER_FPR" >/dev/null 2>&1 ||
		gpg --auto-key-locate clear,wkd --locate-keys gregkh@kernel.org torvalds@kernel.org >/dev/null
	local status
	status="$(LC_ALL=C git -C "$KERNEL_GIT" verify-tag --raw "$KERNEL_TAG" 2>&1 || true)"
	grep -q "^\[GNUPG:\] VALIDSIG $KERNEL_TAG_SIGNER_FPR " <<<"$status" ||
		die "signature verification of $KERNEL_TAG failed:\n$status"
	log "kernel $KERNEL_TAG: signature by $KERNEL_TAG_SIGNER_FPR verified"
}

fetch_ref() { # dir url [branch]
	local dir="$DITING_TOP/references/$1"
	if [ -d "$dir/.git" ]; then
		log "reference $1 present at $(git -C "$dir" rev-parse --short HEAD) (not updated)"
	else
		log "cloning reference $1"
		git clone -q ${3:+-b "$3"} --filter=blob:none "$2" "$dir"
	fi
}

fetch_kernel
if [ "${1:-}" != "--kernel-only" ]; then
	fetch_ref sm8450-linux https://github.com/sm8450-mainline/linux next
	fetch_ref sm8450-fdt https://github.com/sm8450-mainline/fdt
	fetch_ref sm8450-pmaports-archive https://github.com/sm8450-mainline/pmaports
	fetch_ref pmaports-current https://gitlab.postmarketos.org/postmarketOS/pmaports.git
	fetch_ref lineage-diting https://github.com/LineageOS/android_device_xiaomi_diting
	fetch_ref lineage-sm8450-common https://github.com/LineageOS/android_device_xiaomi_sm8450-common
	fetch_ref xiaomi-sm8475-dev-diting https://github.com/Xiaomi-SM8475-Development/android_device_xiaomi_diting
fi
# Build input (not just reference): topology macros at the pinned commit.
fetch_ref audioreach-topology "$AUDIOREACH_TOPOLOGY_URL"
git -C "$DITING_TOP/references/audioreach-topology" checkout -q "$AUDIOREACH_TOPOLOGY_COMMIT" ||
	die "audioreach-topology: cannot check out $AUDIOREACH_TOPOLOGY_COMMIT"
# Build inputs: ACDB parser (voice topology), FastRPC userspace (audio PD),
# hexagonrpcd (sensor DSP file server), libssc and iio-sensor-proxy (sensors).
fetch_ref ar-audioreach-graphservices "$AUDIOREACH_GRAPHSERVICES_URL"
git -C "$DITING_TOP/references/ar-audioreach-graphservices" checkout -q "$AUDIOREACH_GRAPHSERVICES_COMMIT" ||
	die "ar-audioreach-graphservices: cannot check out $AUDIOREACH_GRAPHSERVICES_COMMIT"
fetch_ref fastrpc "$FASTRPC_URL"
git -C "$DITING_TOP/references/fastrpc" checkout -q "$FASTRPC_COMMIT" ||
	die "fastrpc: cannot check out $FASTRPC_COMMIT"
fetch_ref hexagonrpc "$HEXAGONRPC_URL"
git -C "$DITING_TOP/references/hexagonrpc" checkout -q "$HEXAGONRPC_COMMIT" ||
	die "hexagonrpc: cannot check out $HEXAGONRPC_COMMIT"
fetch_ref libssc "$LIBSSC_URL"
git -C "$DITING_TOP/references/libssc" checkout -q "$LIBSSC_COMMIT" ||
	die "libssc: cannot check out $LIBSSC_COMMIT"
fetch_ref iio-sensor-proxy "$IIO_SENSOR_PROXY_URL"
git -C "$DITING_TOP/references/iio-sensor-proxy" checkout -q "$IIO_SENSOR_PROXY_COMMIT" ||
	die "iio-sensor-proxy: cannot check out $IIO_SENSOR_PROXY_COMMIT"
# VA-API driver for the iris decoder (packages/libva-v4l2-stateful patches it)
fetch_ref libva-v4l2-stateful "$LIBVA_V4L2_URL"
git -C "$DITING_TOP/references/libva-v4l2-stateful" cat-file -e "$LIBVA_V4L2_COMMIT^{commit}" ||
	die "libva-v4l2-stateful: commit $LIBVA_V4L2_COMMIT missing"
# Firefox mobile configuration (packages/mobile-config-firefox)
fetch_ref mobile-config-firefox "$MOBILE_CONFIG_FIREFOX_URL"
git -C "$DITING_TOP/references/mobile-config-firefox" cat-file -e "$MOBILE_CONFIG_FIREFOX_COMMIT^{commit}" ||
	die "mobile-config-firefox: commit $MOBILE_CONFIG_FIREFOX_COMMIT missing"
