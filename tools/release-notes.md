## Fixes

- Fixes macOS Installer redirecting Axial into an existing development copy instead of `/Applications/Axial.app`. App and framework installation locations are now fixed explicitly.
- Adds package metadata checks and Homebrew install/reinstall regression tests with a registered duplicate app, ensuring the development copy remains untouched.
- Makes the Homebrew release update resilient to GitHub temporarily omitting uploaded files from its release-by-tag API: it downloads the published asset URLs and verifies checksums directly.

Includes the JavaScript/WebSocket API compatibility and native-client fixes introduced in v0.2.0.

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
