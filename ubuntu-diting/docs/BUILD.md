# Build

## Host

Tested host: Armbian 26.2.1 (Debian 13 trixie), **native aarch64** (CIX P1, 12
cores, 31 GiB RAM), GCC 14.2.0. On x86_64 hosts the scripts default to
`CROSS_COMPILE=aarch64-linux-gnu-` and debootstrap runs `--foreign` with
`qemu-user-static` (not tested in this session).

Debian/Ubuntu host packages:

```sh
sudo apt install git gnupg2 make gcc bc flex bison perl python3 python3-venv \
  libssl-dev libelf-dev libdw-dev device-tree-compiler mkbootimg rsync curl \
  dpkg-dev debhelper fakeroot lintian debootstrap ubuntu-keyring \
  e2fsprogs zstd lz4 cpio kmod xz-utils shellcheck yamllint adb fastboot
# x86_64 hosts additionally: gcc-aarch64-linux-gnu qemu-user-static binfmt-support
python3 -m venv ../tools/venv && ../tools/venv/bin/pip install dtschema   # for make dtbs-check
```

(`mkbootimg`/`unpack_bootimg` come from Debian's `mkbootimg` package;
`fdtput`/`fdtget` from `device-tree-compiler`.)

### openSUSE Tumbleweed x86_64 (current build host since 2026-10-14)

Kernel r37 onward is cross-built on a Ryzen 7 5800X (16 threads, about 14
minutes for a clean kernel build) because the CIX P1 host corrupts memory
under build load (see below).

```sh
sudo zypper install cross-aarch64-gcc14 cross-aarch64-binutils qemu-linux-user \
  debootstrap fakeroot android-tools-mkbootimg debhelper
```

The scripts detect `aarch64-suse-linux-` as cross prefix. On a host without
a dpkg database, `build-kernel.sh` passes an empty `--admindir` to
`dpkg-buildpackage` (build-dependency check skipped), wraps `depmod` with
`-m /lib/modules` (openSUSE's kmod defaults to `/usr/lib/modules`; the
package keeps `/lib/modules` like all earlier revisions) and skips the
`linux-headers` package (its scripts would need an arm64 libc, which the
kernel-only cross compiler lacks; the phone does not install it). The
`linux-image` package is file-for-file identical to the natively built one
(r36 vs r37: 4202 paths).

openSUSE ships no Ubuntu archive keyring: `config/keyrings/ubuntu-archive-keyring.gpg`
(Ubuntu's 2012 and 2018 archive keys, copied from `ubuntu-keyring` on the
phone, fingerprints in `config/diting.conf`) is used for debootstrap so that
the Release signature is checked. `img2simg` (android-tools) makes the sparse
image for `make release`.

`build-libva-v4l2-stateful.sh` (VA-API driver) and `build-firmware-setup.sh` build in their own arm64
buildd chroot (`work/build-chroot-<suite>-arm64`, created with
`debootstrap --variant=buildd`, main/universe enabled), which runs under
qemu-user via binfmt on x86_64 (registered by `qemu-linux-user`; the `F`
flag makes the interpreter usable inside the chroot) and natively on arm64.

Not yet ported to x86_64: the scripts that build in a copy of the rootfs
(`build-libcamera.sh`, `build-sensors.sh`, `build-phoc.sh`) still require a
native arm64 host; they could move to the buildd chroot the same way.

## Known host issue: compiler crashes with transparent huge pages

On the build host (CIX P1, kernel `7.1.8-edge-cix-p1`, THP `always`) parallel
GCC runs crashed randomly (segfaults, `pop_scope` ICEs, and once a bogus syntax
error in an unmodified file), at -j12, -j8 and -j4 alike. Measurements:

| Test | Failures |
| --- | --- |
| same compile, 20x sequential | 0/20 |
| same compile, 12 parallel x 6, THP on | 6/72 |
| same compile, 12 parallel x 6, THP off (`prctl(PR_SET_THP_DISABLE)`) | 0/72 |
| sha256 of a 192 MiB file on all cores | 0 mismatches |

THP under concurrent load is the main trigger on this host kernel (not the
source code, not a single core), but not the only one: with THP disabled, a full
-j12 build had 0 crashes, yet crashes returned when a QEMU TCG guest ran
alongside the build (load ≈ 15). The host is therefore marginal under very heavy
load and its output must be checked, not trusted. The build therefore runs make under `work/tools/nothp`
(built from `tools/src/nothp.c`), which disables THP for the build processes only;
no host setting is changed. Disable with `DITING_NOTHP=0`. A retry on ICE remains
as a safety net (`output/logs/kernel-ice.log`), and `scripts/check-reproducible.sh`
rebuilds everything and compares Image, DTB and all modules bit for bit to detect
silent miscompiles.

Owner action suggested (outside this project): report/upgrade the host kernel, or
set `transparent_hugepage=madvise` on the host.

2026-10-13 (host up 24 days): even with THP disabled, one kernel link (ld
segfault, BFD assertion) and one `dpkg-deb` (SIGPIPE) failed and the libcamera
C++ build hit gcc internal compiler errors three times in a row (-j12 and -j6),
while the same builds had been clean before. A host reboot was not tried.
libcamera was then built natively on the phone instead (Ubuntu 26.04 arm64,
same compiler, about 10 minutes):

    # on the phone, in ~/build/libcamera with the Ubuntu source + packages/libcamera/*.patch
    dpkg-source -x libcamera_*.dsc src && cd src
    cp ../*.patch debian/patches/ && ls ../*.patch | xargs -n1 basename >> debian/patches/series
    QUILT_PATCHES=debian/patches quilt push -a
    dch -v "$(dpkg-parsechangelog -S Version)diting1" -D resolute "..."
    sudo mk-build-deps -i -r -t "apt-get -y --no-install-recommends" debian/control
    DEB_BUILD_OPTIONS="nocheck parallel=8" dpkg-buildpackage -b -us -uc
    # afterwards: purge libcamera-build-deps and remove exactly the packages it
    # pulled in (not a plain autoremove, which also takes unrelated orphans)

The packages go to `output/debs/libcamera/`, which `build-rootfs.sh` installs.

## Targets

See `make help`. Timing on the host above: kernel ≈ 25 min at -j12 (`defconfig` + fragment
builds all arm64 modules), rootfs ≈ 10 min, everything else seconds.

## Reproducibility

- kernel: locked tag object + commit + signer fingerprint (`config/kernel.lock`);
  `KBUILD_BUILD_USER/HOST/TIMESTAMP` fixed; source exported without `.git`
- patches/fragment/lock digest stored in `work/kernel-src/.diting-stamp`; any
  change re-exports the tree and wipes kernel objects
- Ubuntu: suite and mirror in `config/diting.conf`; installed versions recorded in
  `output/rootfs-packages-<suite>.tsv` (archive contents change over time, so the
  rootfs is reproducible in configuration, not bit-for-bit)
