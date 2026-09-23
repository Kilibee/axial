#!/bin/bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'Installation checks require a disposable GitHub runner.' >&2; exit 1; }
brew update
version=$(<release/VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid artifact VERSION' >&2; exit 1; }
tap=$(mktemp -d)
bash tools/generate-cask.sh "$version" release "$tap/Casks/axial.rb"
git -C "$tap" init
git -C "$tap" -c user.name=CI -c user.email=ci@example.invalid add .
git -C "$tap" -c user.name=CI -c user.email=ci@example.invalid commit -m 'Test cask'
brew tap --custom-remote consi/axial-ci "$tap"
cache=$(brew --cache --cask consi/axial-ci/axial)
mkdir -p "$(dirname "$cache")"
cp "release/Axial-$version-universal.pkg" "$cache"
brew style --cask consi/axial-ci/axial
# A foreign framework must prevent installation before any app is written.
foreign=/Library/Frameworks/3DconnexionClient.framework
sudo mkdir -p "$foreign/Resources"
sudo /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.example.foreign' "$foreign/Resources/Info.plist"
if brew install --cask consi/axial-ci/axial; then exit 1; fi
[[ ! -e /Applications/Axial.app ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$foreign/Resources/Info.plist") == com.example.foreign ]]
sudo rm "$foreign/Resources/Info.plist"
sudo rmdir "$foreign/Resources" "$foreign"
# Register an older development copy before installation. A relocatable package
# can silently update this copy instead of creating /Applications/Axial.app.
mkdir -p build
duplicate=$(mktemp -d "$PWD/build/installer-duplicate.XXXXXX")
pkgutil --expand-full "release/Axial-$version-universal.pkg" "$duplicate/package"
payload_app=$(find "$duplicate/package" -type d -path '*/Applications/Axial.app')
[[ -n "$payload_app" && "$payload_app" != *$'\n'* ]]
duplicate_app="$duplicate/Developer build/Axial.app"
ditto "$payload_app" "$duplicate_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 0.0.0' "$duplicate_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.0.0' "$duplicate_app/Contents/Info.plist"
touch "$duplicate_app/Contents/Resources/axial-ci-preserve"
codesign --force --sign - "$duplicate_app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
trap '"$lsregister" -u "$duplicate_app" >/dev/null 2>&1 || true' EXIT
"$lsregister" -f "$duplicate_app"
check_install_location() {
  codesign --verify --deep --strict /Applications/Axial.app
  [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Axial.app/Contents/Info.plist) == "$version" ]]
  [[ -e "$duplicate_app/Contents/Resources/axial-ci-preserve" ]]
  [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$duplicate_app/Contents/Info.plist") == 0.0.0 ]]
  codesign --verify --deep --strict "$duplicate_app"
}
brew install --cask consi/axial-ci/axial
check_install_location
brew reinstall --cask consi/axial-ci/axial
check_install_location
web_credentials='/Library/Application Support/Axial/Web'
[[ -x /Applications/Axial.app/Contents/Library/Helpers/axial-web-setup ]]
# Package installation must not need a GUI session, create a CA, alter trust,
# or configure network addresses. The app owns that permission flow.
[[ ! -e "$web_credentials" && ! -e /Library/LaunchDaemons/pro.jest.axial-web-loopback.plist ]]
mkdir -p "$HOME/Library/Application Support/Axial"
touch "$HOME/Library/Application Support/Axial/ci-preserve"
# Refuse removal if another driver has replaced a framework.
sudo /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.foreign' "$foreign/Resources/Info.plist"
if brew uninstall --cask consi/axial-ci/axial; then exit 1; fi
[[ -e /Applications/Axial.app ]]
sudo /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier pro.jest.3DconnexionClient' "$foreign/Resources/Info.plist"
brew uninstall --cask consi/axial-ci/axial
[[ ! -e /Applications/Axial.app && ! -e "$foreign" && ! -e /Library/Frameworks/3DconnexionNavlib.framework ]]
[[ ! -e "$web_credentials" && ! -e /Library/LaunchDaemons/pro.jest.axial-web-loopback.plist ]]
[[ -e "$HOME/Library/Application Support/Axial/ci-preserve" ]]
