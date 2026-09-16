#!/bin/bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'Installation checks require a disposable GitHub runner.' >&2; exit 1; }
version=$(sed -n 's/project(Axial VERSION \([^ ]*\).*/\1/p' CMakeLists.txt)
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
brew install --cask consi/axial-ci/axial
codesign --verify --deep --strict /Applications/Axial.app
mkdir -p "$HOME/Library/Application Support/Axial"
touch "$HOME/Library/Application Support/Axial/ci-preserve"
# Refuse removal if another driver has replaced a framework.
sudo /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.foreign' "$foreign/Resources/Info.plist"
if brew uninstall --cask consi/axial-ci/axial; then exit 1; fi
[[ -e /Applications/Axial.app ]]
sudo /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier pro.jest.3DconnexionClient' "$foreign/Resources/Info.plist"
brew uninstall --cask consi/axial-ci/axial
[[ ! -e /Applications/Axial.app && ! -e "$foreign" && ! -e /Library/Frameworks/3DconnexionNavlib.framework ]]
[[ -e "$HOME/Library/Application Support/Axial/ci-preserve" ]]
