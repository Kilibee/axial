#!/bin/bash
set -euo pipefail
# Installer passes its target volume as argument three.
root="${3:-/}"
for name in Axial 3DconnexionClient 3DconnexionNavlib; do
  if [[ "$name" == Axial ]]; then
    bundle="${root%/}/Applications/Axial.app"
    plist="$bundle/Contents/Info.plist"
  else
    bundle="${root%/}/Library/Frameworks/$name.framework"
    plist="$bundle/Resources/Info.plist"
  fi
  if [[ -e "$bundle" || -L "$bundle" ]]; then
    identity=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
    [[ "$identity" == "pro.jest.$name" ]] || {
      echo "Refusing to replace $bundle; uninstall the existing driver first." >&2
      exit 1
    }
  fi
done
