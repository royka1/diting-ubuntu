# phoc (patched)

Ubuntu's phoc with one fix, rebuilt as a local Debian package by
`scripts/build-phoc.sh` (version `<ubuntu version>diting1`):

- `0001-output-honor-non-preferred-modes-from-output-managem.patch`
  (from the owner's Xiaomi Apollo work): phoc only applied a mode chosen through
  wlr-output-management when it was the panel's preferred one, so every
  refresh-rate change (Settings, wlr-randr) silently reverted to the default.
  Needed for the panel's 90/120 Hz modes.
