# Waydroid on the Xiaomi 12T Pro (diting)

Waydroid runs Android apps in a container on the Ubuntu image. It is not
preinstalled. This page covers installing it and the two problems that
Waydroid's own images have on this phone, with the fixes.

Tested on 2026-10-15 with Waydroid 1.6.2 from repo.waydro.id, the
`arm64_only` LineageOS 20 (Android 13) GAPPS system image and the MAINLINE
vendor image.

## Requirements

- **Kernel r44 or later.** Check with `uname -v`: it must show `#44` or a
  higher number. Android's network daemon needs policy routing (multiple
  routing tables) and a set of iptables matches. Earlier kernels lack them,
  so Android inside Waydroid has no internet. Policy routing is built into the
  kernel image, so installing the kernel package is not enough: the new boot
  image must also be flashed (or use a release image built with r44 or later).
- About 3 GB free for the Waydroid images.

## Install

Waydroid is not in Ubuntu's own archive, so first add Waydroid's repository.
Its official script detects Ubuntu 26.04 (`resolute`) and sets it up:

```bash
sudo apt install curl ca-certificates
curl -s https://repo.waydro.id | sudo bash
```

That creates `/etc/apt/sources.list.d/waydroid.list` with
`deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://repo.waydro.id/ resolute main`
and the signing key `/usr/share/keyrings/waydroid.gpg`. To do the same by
hand instead:

```bash
sudo curl -fsSo /usr/share/keyrings/waydroid.gpg https://repo.waydro.id/waydroid.gpg
echo 'deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://repo.waydro.id/ resolute main' |
    sudo tee /etc/apt/sources.list.d/waydroid.list
sudo apt update
```

Then install Waydroid and initialise it, for example with Google apps:

```bash
sudo apt install waydroid
sudo waydroid init -s GAPPS
```

More options: https://docs.waydro.id

Start it once from the app grid ("Waydroid") so that the container and the
user session are set up, then close it again.

## Fix 1: "No storage space available"

**Symptom:** Android apps report that there is no storage, the Play Store
cannot download, and *Settings > Storage* shows no internal shared storage.
Changing ownership or permissions of `/data/media/0` does not help.

**Cause:** the MAINLINE vendor image declares the old OMX video codec
service (`android.hardware.media.omx`) in its manifest but does not contain
it. `mediaserver` waits for that service forever when building the codec
list. Android's MediaProvider asks for the codec list during startup, hangs,
and is killed after 20 s. Shared storage (`/storage/emulated/0`) is
served by MediaProvider, so it is never mounted.

**Fix:**
1. Give Waydroid a copy of the vendor manifest without the OMX entry, through
   Waydroid's overlay directory. The vendor image itself stays unchanged.
2. Let Android use its Codec2 software codecs, which the image does contain.

Run these commands on the phone. Copy each block whole:

```bash
waydroid session stop

# 1. Vendor manifest without the OMX service, as an overlay file
img=$(sed -n 's/^images_path *= *//p' /var/lib/waydroid/waydroid.cfg)
tmp=$(mktemp -d)
sudo mount -o ro,loop "$img/vendor.img" "$tmp"
sudo mkdir -p /var/lib/waydroid/overlay/vendor/etc/vintf
sudo python3 - "$tmp/etc/vintf/manifest.xml" \
    /var/lib/waydroid/overlay/vendor/etc/vintf/manifest.xml <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
s, n = re.subn(r'\s*<hal format="hidl">\s*<name>android\.hardware\.media\.omx</name>.*?</hal>',
               '', s, flags=re.S)
if n != 1:
    sys.exit("expected one media.omx entry, found %d; nothing written" % n)
open(sys.argv[2], 'w').write(s)
EOF
sudo umount "$tmp"; rmdir "$tmp"
```

```bash
# 2. Codec2 instead of OMX
cfg=/var/lib/waydroid/waydroid.cfg
grep -q '^\[properties\]' "$cfg" || echo '[properties]' | sudo tee -a "$cfg" >/dev/null
grep -q '^debug.stagefright.ccodec' "$cfg" ||
    sudo sed -i '/^\[properties\]/a debug.stagefright.ccodec = 4' "$cfg"

# Waydroid applies [properties] only when it regenerates its base properties
sudo waydroid upgrade --offline
sudo systemctl restart waydroid-container
```

Then start Waydroid again from the app grid.

`waydroid.cfg` must have `mount_overlays = True` (the default). If the python
step prints "expected one media.omx entry, found 0", your vendor image no
longer declares the service. Then this fix is not needed, and nothing was
written.

## Fix 2: no internet inside Android

**Symptom:** Android shows a network connection, but nothing loads.
`sudo waydroid shell -- ping 1.1.1.1` answers "Network is unreachable", and
`sudo waydroid shell -- ip rule` says "Operation not supported".

**Cause and fix:** the kernel lacks policy routing. Update to kernel r44 or
later, including the boot image (see Requirements). Nothing has to be
changed in Waydroid itself.

## Check

With Waydroid running:

```bash
sudo waydroid shell -- sm list-volumes all      # emulated;0 mounted
sudo waydroid shell -- getprop debug.stagefright.ccodec   # 4
sudo waydroid shell -- ping -c2 google.com      # replies
```

## After a Waydroid image update

`waydroid upgrade` keeps both the overlay file and the property. The overlay
replaces the vendor manifest of every later vendor image, though. After a
vendor image update, run Fix 1 step 1 again so that the overlay matches the
new image, or remove the overlay file if the new image is fixed.

## Undo

```bash
sudo rm /var/lib/waydroid/overlay/vendor/etc/vintf/manifest.xml
sudo sed -i '/^debug.stagefright.ccodec/d' /var/lib/waydroid/waydroid.cfg
sudo waydroid upgrade --offline
sudo systemctl restart waydroid-container
```

## Not needed

- Changing `lxc.apparmor.profile` in `/var/lib/waydroid/lxc/waydroid/config`
  to `unconfined` does not help with either problem. Waydroid rewrites that
  file on `waydroid upgrade` and `waydroid init`.
- `chmod`/`chown` on `/data/media/0` inside the container does not help:
  the storage was missing, not inaccessible.
