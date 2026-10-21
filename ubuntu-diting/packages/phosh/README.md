# phosh (patched)

Ubuntu's phosh with one change, rebuilt as a local Debian package by
`scripts/build-phosh.sh` (version `<ubuntu version>diting1`):

- `0001-screen-saver-manager-keep-the-screen-off-after-a-wak.patch`: the
  charger firmware wakes the phone every eight minutes, and phosh and
  gnome-settings-daemon turned the screen on at every resume. Phosh now holds
  the outputs off from suspend on. After resume it wakes the screen as before,
  unless the system-sleep hook of device-xiaomi-diting created
  `/run/diting-resuspend.dark` (no power or volume key pressed during
  suspend). A power key press, an incoming call or a notification that wakes
  the screen releases the hold.

Without device-xiaomi-diting 0.7.16 or later the file never exists and phosh
behaves as before. An archive phosh with a higher version replaces this
build; then the screen lights up at every wake-up again.
