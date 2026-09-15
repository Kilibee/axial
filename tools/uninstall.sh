#!/bin/bash
set -euo pipefail
# Preserve user profiles. Remove only bundles with our exact identifiers.
for name in 3DconnexionClient 3DconnexionNavlib; do
  path="/Library/Frameworks/$name.framework"
  if [[ -e "$path" ]]; then
    identity=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$path/Resources/Info.plist")
    [[ "$identity" == "pro.jest.$name" ]] || { echo "Refusing to remove $path" >&2; exit 1; }
  fi
done
if [[ -e /Applications/Axial.app ]]; then
  identity=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/Axial.app/Contents/Info.plist)
  [[ "$identity" == pro.jest.Axial ]] || exit 1
fi
echo 'Disable Start at login and quit Axial before uninstalling.'
for name in 3DconnexionClient 3DconnexionNavlib; do rm -rf "/Library/Frameworks/$name.framework"; done
rm -rf /Applications/Axial.app
echo 'Axial removed; settings retained. You can reinstall the vendor driver.'
