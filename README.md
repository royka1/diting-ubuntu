# Ubuntu on the Xiaomi 12T Pro (diting)

Ubuntu 26.04 LTS arm64 with Phosh for the Xiaomi 12T Pro / Redmi K50 Ultra
(`diting`, Snapdragon 8+ Gen 1, SM8475), on the upstream stable Linux kernel
with a device patch series.

- **Install a released image:** [ubuntu-diting/release/INSTALL.md](ubuntu-diting/release/INSTALL.md)
  (images under Releases).
- **Build it yourself:** [ubuntu-diting/README.md](ubuntu-diting/README.md).
- **Hardware status:** [docs/BRINGUP_STATUS.md](docs/BRINGUP_STATUS.md),
  [ubuntu-diting/docs/KNOWN_ISSUES.md](ubuntu-diting/docs/KNOWN_ISSUES.md).
- **Kernel tree** (v7.2.10 + the patches in `kernel/patches` as commits):
  https://github.com/royka1/linux-diting

## Sources in this repository

| Path | What | Licence |
| --- | --- | --- |
| `kernel/patches/`, `kernel/config/` | Linux 7.2.10 patch series and config fragment | GPL-2.0 (kernel) |
| `ubuntu-diting/` | build system, Debian packaging, device package, install scripts | GPL-2.0-or-later |
| `ubuntu-diting/packages/libva-v4l2-stateful/` | patches for [libva-v4l2-stateful](https://github.com/sky1-linux/libva-v4l2-stateful) (VA-API over V4L2, iris decoder) | MIT (upstream) |
| `ubuntu-diting/packages/libcamera/`, `phoc/`, `hexagonrpc/` | patches for Ubuntu's libcamera and phoc and for hexagonrpc | upstream licences (LGPL-2.1+, GPL-3.0+, GPL-3.0+) |
| `ubuntu-diting/packages/audio-topology/` | AudioReach topology for the speakers | BSD-3-Clause macros from linux-msm/audioreach-topology |
| `tools/` | firmware builder, Android super parser, ACDB/topology, camera and DSP tools | GPL-2.0-or-later |

Upstream projects are fetched at pinned commits by `make sources`
(`ubuntu-diting/config/diting.conf`); Ubuntu packages come from the Ubuntu
archive.

No Xiaomi or Qualcomm firmware is in this repository or in the images: each
phone extracts its own at first boot (`ubuntu-diting/packages/diting-firmware-setup`).

This is a personal, experimental port, written with the help of an AI coding
assistant (Claude). It is not affiliated with Xiaomi, Canonical or
postmarketOS, and the patches have not been submitted upstream.
