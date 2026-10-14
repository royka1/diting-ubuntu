#!/bin/bash
# Compare the locked kernel with kernel.org's current stable release.
# Read-only: prints the result, never changes kernel.lock.
. "$(dirname "$0")/lib.sh"
need curl python3 git
latest="$(curl -fsS https://www.kernel.org/releases.json |
	python3 -c 'import json,sys; print(json.load(sys.stdin)["latest_stable"]["version"])')"
tag="$(git ls-remote --tags "$KERNEL_GIT_URL" "refs/tags/v$latest" | head -1 | cut -f1)"
echo "locked:          $KERNEL_VERSION ($KERNEL_COMMIT)"
echo "kernel.org says: $latest (stable git tag object: ${tag:-NOT FOUND, mirror may lag})"
if [ "$latest" = "$KERNEL_VERSION" ]; then
	echo "up to date"
else
	echo "newer stable available; review and run 'make update-kernel'"
	exit 3
fi
