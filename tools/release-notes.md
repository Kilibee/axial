## New JavaScript / WebSocket API

- Adds a local, TLS-secured WebSocket API compatible with 3DconnexionJS/WAMP v1 for browser-based 3D navigation, including camera updates, focus, fit, and mapped commands.
- Web navigation is enabled by default. Set up certificates and the loopback address from Axial's **WebSocket API compatibility** section with macOS approval; no shell scripts, host allowlists, or separately installed OpenSSL are needed.
- Axial checks web setup health and offers repair or certificate renewal when needed. Quitting Axial closes its WebSocket listener.
- Connected-client diagnostics now include WebSocket connections. The web compatibility section shows **Ready** when setup and the listener are healthy.

## Fixes

- Resolves controller references consistently across prefixed URIs, full URIs, and bare IDs, fixing rejected focus requests from 3DconnexionJS clients.
- Improves native client compatibility with helper-process applications and legacy button handling while preserving framework ABI versions.
- Reopening Axial brings the existing settings window forward instead of starting another instance.
- Restores the settings window after macOS setup approval and handles certificates already present in the keychain.
- Fixes a shutdown race that could leave the web service running.
- Uses the release tag as the authoritative package version, fixing the version mismatch that blocked v0.1.1 releases.

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
