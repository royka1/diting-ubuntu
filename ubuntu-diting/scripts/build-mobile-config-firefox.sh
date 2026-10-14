#!/bin/bash
# Build mobile-config-firefox (postmarketOS' Firefox configuration, not in
# Ubuntu) from the pinned upstream commit, in the arm64 buildd chroot.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-buildd.sh"
need git

UPSTREAM="$DITING_TOP/references/mobile-config-firefox"
git -C "$UPSTREAM" cat-file -e "$MOBILE_CONFIG_FIREFOX_COMMIT^{commit}" 2>/dev/null ||
	die "missing $UPSTREAM at $MOBILE_CONFIG_FIREFOX_COMMIT (make sources)"
src="$WORK/mobile-config-firefox-pkg"
rm -rf "$src" && mkdir -p "$src"
git -C "$UPSTREAM" archive "$MOBILE_CONFIG_FIREFOX_COMMIT" | tar -x -C "$src"
cp -a "$UD/packages/mobile-config-firefox/debian" "$src/debian"

buildd_setup
buildd_build "$src" mobile-config-firefox
