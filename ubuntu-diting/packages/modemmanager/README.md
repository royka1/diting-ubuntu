# modemmanager (local rebuild)

Ubuntu's `modemmanager` source (version in `scripts/build-modemmanager.sh`,
fetched with `apt-get source` in the arm64 build chroot) plus the patches in
this directory, built as `<ubuntu version>diting1`. `device-xiaomi-diting`
pins `*diting*` versions so the archive package does not replace it.

- `0001-netlink-fix-use-after-free-...`: upstream commit 9317cbc4 (Dan
  Williams, 2026-10-04). `transaction_complete()` read `tr->completion_fn`
  after removing (and so freeing) the transaction; after a resume, when
  ModemManager re-creates the `qmapmux0.0` data link, the freed memory was
  reused and ModemManager jumped to a bad address (SIGSEGV, backtrace in
  `src/mm-netlink.c:242`). Mobile data dropped until systemd restarted it.

Drop the rebuild once the Ubuntu archive ships a version with the fix.
