#!/bin/bash
set -euo pipefail
# Run from the downloaded release artifact directory. Never install on a developer Mac.
shasum -a 256 -c SHA256SUMS
package=(Axial-*-universal.pkg)
[[ ${#package[@]} == 1 && -f "${package[0]}" ]]
expanded=$(mktemp -d)
pkgutil --expand-full "${package[0]}" "$expanded/package"
app=$(find "$expanded/package" -type d -path '*/Applications/Axial.app')
[[ -n "$app" && "$app" != *$'\n'* ]]
payload="${app%/Applications/Axial.app}"
service="$app/Contents/Library/Helpers/Axial Service.app/Contents/MacOS/axial-service"
client="$payload/Library/Frameworks/3DconnexionClient.framework"
navlib="$payload/Library/Frameworks/3DconnexionNavlib.framework"
for binary in "$app/Contents/MacOS/Axial" "$service" "$app/Contents/Library/Helpers/axialctl" "$client/Versions/A/3DconnexionClient" "$navlib/Versions/A/3DconnexionNavlib"; do
  lipo -verify_arch arm64 x86_64 "$binary"
  xcrun vtool -show-build "$binary"
  [[ $(xcrun vtool -show-build "$binary" | awk '/minos/ {print $2}' | sort -u) == 13.0 ]]
done
for bundle in "$app" "$client" "$navlib"; do
  codesign --verify --deep --strict "$bundle"
done
[[ $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist") == 13.0 ]]
./tests/core-tests fixtures/spaceexplorer-motion.txt fixtures/upstream-device-buttons.toml
./tests/transport-tests
./tests/owner-tests "$service"
./tests/integration-tests "$service" "$client/Versions/A/3DconnexionClient" "$navlib/Versions/A/3DconnexionNavlib"
for test in navigation diagnostics session-log model; do "./tests/$test-tests"; done
while IFS= read -r info; do
  /usr/bin/xmllint --xpath 'string(/pkg-info/@identifier)' "$info"
  printf '\n'
done < <(find "$expanded/package" -name PackageInfo) | jq -Rsc 'split("\n") | map(select(length > 0)) | unique' > receipts.json
jq -e 'length > 0 and all(.[]; test("^pro\\.jest\\.[A-Za-z0-9_.-]+$"))' receipts.json
