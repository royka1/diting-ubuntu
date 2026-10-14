# Wine / Box64 (future, not on the critical path)

- Keep the rootfs pure arm64. Do not add `armhf`/`i386`/`amd64` foreign architectures
  to the base image; Box64 does not need them.
- Box64 runs x86_64 Linux binaries on arm64 (needs a 4K-page kernel – our kernel uses
  4K pages). x86_64 Wine (wine64) runs under Box64; 32-bit Windows programs need
  WoW64 mode of a recent Wine or Box86 (which needs armhf multiarch — avoid).
- GPU acceleration for these needs Mesa freedreno/turnip on Adreno 730 (stage G),
  which needs GPU firmware and a working display pipeline first.
- Plan: package Box64 from source or an Ubuntu universe package if available in
  resolute; test only after stage G.
