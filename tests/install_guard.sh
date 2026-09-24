#!/bin/bash
set -euo pipefail
source "${1:?source directory}/tools/install-guard.sh"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
root="$temporary/volume"
mkdir -p "$root"
axial_check "$root"
framework="$root/Library/Frameworks/3DconnexionClient.framework"
mkdir -p "$framework/Resources"
plist="$framework/Resources/Info.plist"
reject() {
  if axial_check "$root" > "$temporary/result" 2>&1; then
    echo 'Unsafe installation was accepted' >&2; exit 1
  fi
  [[ -d "$framework" ]]
}
# Missing, malformed, foreign and incomplete metadata must never crash through
# PlistBuddy or grant permission to replace an unknown framework.
reject
printf 'broken plist' > "$plist"
reject
rm "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.example.foreign' "$plist" >/dev/null
before=$(shasum -a 256 "$plist")
reject
[[ $(shasum -a 256 "$plist") == "$before" ]]
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier pro.jest.3DconnexionClient' "$plist"
axial_check "$root"
# Open file descriptors are sufficient to block; CI also tests dlopen mappings.
exec 9< "$plist"
reject
rg -q 'files are in use' "$temporary/result"
exec 9<&-
axial_check "$root"
mv "$framework" "$temporary/foreign"
ln -s "$temporary/foreign" "$framework"
reject
rm "$framework"
ln -s "$temporary/missing" "$framework"
if axial_check "$root" > "$temporary/result" 2>&1; then exit 1; fi
echo 'PASS: ownership checks, malformed metadata, busy files, redirected and dangling bundles'
