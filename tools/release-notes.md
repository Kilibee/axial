## Fixes

- Gives both compatibility frameworks explicit bundle identifiers and verifies their metadata in the packaged installer.
- Checks bundle ownership and running applications before installation or removal. When Axial files are in use, the error lists process names and PIDs and leaves the installation intact.
- Recovers complete or incomplete published 0.1.0, 0.2.0 and 0.2.1 bundles with missing identifiers when surviving files match a known release. Modified or unidentifiable remains are rejected.
- Preserves web navigation setup during ordinary Homebrew uninstall, reinstall and upgrade with the new hooks. Use `brew uninstall --cask --zap consi/homebrew/axial` to remove web setup; saved profiles remain.
- Stops toy-car frame callbacks while idle, stopped or hidden, and resumes on effective movement. Three local paired trials reduced median idle scene CPU from 16.9% to 2.4%; moving CPU remained essentially unchanged near 120 FPS. These are synthetic measurements on Apple M5/macOS 27, not Fusion profiling.
- Avoids unnecessary settings updates while navigating in CAD applications, and adds installation, legacy recovery, movement and performance checks.

Homebrew caches the uninstall hook from the installed release. The new safeguards
cannot retroactively replace an older cached hook: migration from older releases
may still encounter its identifier failure or web-setup cleanup. Homebrew 7's
`brew install --cask --force` does not bypass that hook. This release does not edit
installed Homebrew metadata.

## Installation

Universal macOS installer for Apple Silicon and Intel Macs, targeting macOS 13 or later.

Install through Homebrew after the release workflow's Homebrew job completes:

```sh
brew tap consi/homebrew https://github.com/consi/homebrew
brew install --cask consi/homebrew/axial
open /Applications/Axial.app
```

Uninstall the 3Dconnexion driver first. Quit Axial and CAD applications before upgrading. Installation requires administrator access. Grant Axial Accessibility permission for keyboard shortcuts.

Binaries are ad-hoc signed; the installer is not Developer ID signed or notarized. macOS may require approval in Privacy & Security. No system-wide Gatekeeper bypass is required or recommended.

CI builds on macOS 15 and 26 (ARM and Intel), and macOS 27 (ARM preview). The canonical package is also tested on macOS 14 ARM. macOS 13 and native Intel macOS 14/27 are not runtime-tested. Hardware HID and CAD application testing remains manual.

Verify the downloaded installer with `shasum -a 256 -c SHA256SUMS`.
