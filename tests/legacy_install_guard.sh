#!/bin/bash
set -euo pipefail
source "${1:?source directory}/tools/install-guard.sh"
package="${2:?published package}"
version=$(basename "$package" | sed -n 's/^Axial-\([0-9.]*\)-universal.pkg$/\1/p')
case "$version" in
  0.1.0) digest=a4ae851d8a58d7d6d16e4ed6bb8dc54aeb6827014d402e09f44564bdb384d778 ;;
  0.2.0) digest=f3dab047a993b18ee5a660f72fec59d66beb71d32debf76b510d7d7a7369c980 ;;
  0.2.1) digest=ecce6147925428b0d821a2f66f6c776b4bbc476571366bd3a1de19f8703e9301 ;;
  *) exit 2 ;;
esac
[[ $(shasum -a 256 "$package" | awk '{print $1}') == "$digest" ]]
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
pkgutil --expand-full "$package" "$temporary/package"
root="$temporary/package/Axial-$version-universal-Runtime.pkg/Payload"
# A missing binary is recoverable when the bundle still identifies itself.
framework="$root/Library/Frameworks/3DconnexionClient.framework"
mv "$framework/Versions/A/3DconnexionClient" "$temporary/client"
axial_check "$root"
mv "$temporary/client" "$framework/Versions/A/3DconnexionClient"
for name in 3DconnexionClient 3DconnexionNavlib; do
  /usr/libexec/PlistBuddy -c 'Delete :CFBundleIdentifier' "$root/Library/Frameworks/$name.framework/Resources/Info.plist"
done
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIdentifier' "$root/Applications/Axial.app/Contents/Info.plist"
axial_check "$root"
# Missing metadata plus missing resources is recoverable using surviving code.
rm "$framework/Headers/ConnexionClientAPI.h" "$root/Applications/Axial.app/Contents/Resources/ToyCar.scn"
axial_check "$root"
# Without either identity metadata or surviving Axial code, do not guess.
mv "$framework/Versions/A/3DconnexionClient" "$temporary/client"
if axial_check "$root"; then exit 1; fi
mv "$temporary/client" "$framework/Versions/A/3DconnexionClient"
# A surviving executable must be byte-identical, not merely have a known name.
cp "$framework/Versions/A/3DconnexionClient" "$temporary/client"
printf 'modified' >> "$framework/Versions/A/3DconnexionClient"
if axial_check "$root"; then exit 1; fi
mv "$temporary/client" "$framework/Versions/A/3DconnexionClient"
# A copied original executable must not whitelist unrelated bundle contents.
touch "$framework/foreign-file"
if axial_check "$root"; then exit 1; fi
rm "$framework/foreign-file"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.vendor.driver' "$framework/Resources/Info.plist"
if axial_check "$root"; then exit 1; fi
echo 'PASS: verified complete/incomplete legacy recovery; foreign additions and unidentifiable remains are rejected'
