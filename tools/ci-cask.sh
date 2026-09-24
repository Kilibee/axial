#!/bin/bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'Installation checks require a disposable GitHub runner.' >&2; exit 1; }
brew update
# This script mutates only disposable runner installations.
version=$(<release/VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid artifact VERSION' >&2; exit 1; }
tap=$(mktemp -d)
bash tools/generate-cask.sh "$version" release "$tap/Casks/axial.rb"
# Reinstall can fetch again even when the cache was pre-seeded. Always serve
# this build's exact artifact, not a published package with the same version.
ruby -ruri - "$tap/Casks/axial.rb" "$PWD/release/Axial-$version-universal.pkg" <<'RUBY'
cask, package = ARGV
url = "file://#{URI::DEFAULT_PARSER.escape(package)}"
File.write(cask, File.read(cask).sub(/^  url .*$/, "  url #{url.dump}"))
RUBY
git -C "$tap" init
git -C "$tap" -c user.name=CI -c user.email=ci@example.invalid add .
git -C "$tap" -c user.name=CI -c user.email=ci@example.invalid commit -m 'Test cask'
brew tap --custom-remote consi/axial-ci "$tap"
brew trust consi/axial-ci
installed_tap=$(brew --repository consi/axial-ci)
cp "$tap/Casks/axial.rb" "$tap/current.rb"
brew style --cask consi/axial-ci/axial
brew fetch --cask --force consi/axial-ci/axial
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
  [[ $(shasum -a 256 /Applications/Axial.app/Contents/MacOS/Axial | awk '{print $1}') == $(shasum -a 256 "$payload_app/Contents/MacOS/Axial" | awk '{print $1}') ]]
  for name in 3DconnexionClient 3DconnexionNavlib; do
    framework="/Library/Frameworks/$name.framework"
    expected="${payload_app%/Applications/Axial.app}/Library/Frameworks/$name.framework"
    codesign --verify --deep --strict "$framework"
    [[ $(shasum -a 256 "$framework/$name" | awk '{print $1}') == $(shasum -a 256 "$expected/$name" | awk '{print $1}') ]]
  done
  [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Axial.app/Contents/Info.plist) == "$version" ]]
  [[ -e "$duplicate_app/Contents/Resources/axial-ci-preserve" ]]
  [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$duplicate_app/Contents/Info.plist") == 0.0.0 ]]
  codesign --verify --deep --strict "$duplicate_app"
}
# Snapshot installed payload, receipts and configuration before rejected operations.
snapshot() {
  brew list --cask --versions axial
  for path in /Applications/Axial.app /Library/Frameworks/3DconnexionClient.framework /Library/Frameworks/3DconnexionNavlib.framework "/Library/Application Support/Axial" /Library/LaunchDaemons/pro.jest.axial-web-loopback.plist; do
    if [[ -d "$path" ]]; then
      sudo find -s "$path" -type f -exec shasum -a 256 {} +
      sudo find -s "$path" -type l -exec ls -ld {} +
    elif [[ -f "$path" ]]; then sudo shasum -a 256 "$path"; fi
  done
  find -s "$HOME/Library/Application Support/Axial" -type f -exec shasum -a 256 {} +
  while IFS= read -r receipt; do pkgutil --pkg-info-plist "$receipt"; done < <(pkgutil --pkgs='^pro\.jest\.installer(\..*)?$')
}
blocked() {
  snapshot > "$tap/before"
  if "$@" > "$tap/blocked.log" 2>&1; then cat "$tap/blocked.log"; exit 1; fi
  cat "$tap/blocked.log"
  snapshot > "$tap/after"
  cmp "$tap/before" "$tap/after"
}
xcrun clang++ tests/hold_framework.cpp -o "$tap/hold-framework"
mkdir -p "$HOME/Library/Application Support/Axial"
touch "$HOME/Library/Application Support/Axial/ci-preserve"
brew install --cask consi/axial-ci/axial
check_install_location
brew reinstall --cask consi/axial-ci/axial
check_install_location
# Both mapped frameworks block reinstall and uninstall before
# any receipt, configuration or payload is removed.
for name in 3DconnexionClient 3DconnexionNavlib; do
  rm -f "$tap/ready"
  "$tap/hold-framework" "/Library/Frameworks/$name.framework/$name" "$tap/ready" &
  holder=$!
  for attempt in {1..100}; do [[ ! -f "$tap/ready" ]] || break; sleep 0.05; done
  [[ -f "$tap/ready" ]]
  blocked brew reinstall --cask consi/axial-ci/axial
  grep -q 'files are in use' "$tap/blocked.log"
  blocked brew uninstall --cask consi/axial-ci/axial
  kill "$holder";wait "$holder" || true
  check_install_location
done

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

# Exercise a genuine brew upgrade with the corrected cached uninstall guard.
# Only the cask metadata version is lowered; the payload is the canonical build.
sed -e 's/^  version ".*"/  version "0.0.1"/' \
  -e "s/Axial-#{version}-universal.pkg/Axial-$version-universal.pkg/g" \
  "$tap/current.rb" > "$installed_tap/Casks/axial.rb"
brew install --cask consi/axial-ci/axial
cp "$tap/current.rb" "$installed_tap/Casks/axial.rb"
service='/Applications/Axial.app/Contents/Library/Helpers/Axial Service.app/Contents/MacOS/axial-service'
AXIAL_SOCKET="$tap/mock-events" AXIAL_CONFIG="$tap/mock-settings.json" "$service" --mock &
holder=$!
for attempt in {1..100}; do [[ ! -S "$tap/mock-events" ]] || break; sleep 0.05; done
[[ -S "$tap/mock-events" ]]
blocked brew upgrade --cask consi/axial-ci/axial
blocked brew uninstall --cask consi/axial-ci/axial
kill "$holder";wait "$holder" || true
brew upgrade --cask consi/axial-ci/axial
check_install_location
brew uninstall --cask consi/axial-ci/axial

# Reinstall after complete removal, including the separate zap cleanup path.
brew install --cask consi/axial-ci/axial
check_install_location
# Configure web setup on this disposable runner, then prove reinstall retains it.
sudo /Applications/Axial.app/Contents/Library/Helpers/axial-web-setup --install
sudo shasum -a 256 "$web_credentials/root.crt" > "$tap/certificate-before"
brew reinstall --cask consi/axial-ci/axial
sudo shasum -a 256 "$web_credentials/root.crt" > "$tap/certificate-after"
cmp "$tap/certificate-before" "$tap/certificate-after"
brew uninstall --cask --zap consi/axial-ci/axial
[[ ! -e "$web_credentials" && ! -e /Library/LaunchDaemons/pro.jest.axial-web-loopback.plist ]]
[[ -e "$HOME/Library/Application Support/Axial/ci-preserve" ]]

# Install actual published versions using their original casks, then exercise
# the package's recovery guard. Homebrew 7 routes force-install through upgrade,
# so it cannot replace an old cached uninstall hook before that hook runs.
for old in 0.1.0 0.2.1; do
  legacy="$tap/legacy-$old";mkdir -p "$legacy"
  curl -fL --retry 3 "https://github.com/consi/axial/releases/download/v$old/Axial-$old-universal.pkg" -o "$legacy/Axial-$old-universal.pkg"
  case "$old" in
    0.1.0) digest=a4ae851d8a58d7d6d16e4ed6bb8dc54aeb6827014d402e09f44564bdb384d778 ;;
    0.2.1) digest=ecce6147925428b0d821a2f66f6c776b4bbc476571366bd3a1de19f8703e9301 ;;
  esac
  [[ $(shasum -a 256 "$legacy/Axial-$old-universal.pkg" | awk '{print $1}') == "$digest" ]]
  curl -fL --retry 3 "https://raw.githubusercontent.com/consi/axial/v$old/tools/cask.rb.in" -o "$legacy/cask.rb.in"
  receipts=$(cat release/receipts.json)
  sed -e "s|@VERSION@|$old|g" -e "s|@SHA256@|$digest|g" \
    -e "s|@URL@|https://github.com/consi/axial/releases/download/v$old/Axial-$old-universal.pkg|g" \
    -e "s|@RECEIPTS@|$(echo "$receipts" | jq -c .)|g" "$legacy/cask.rb.in" > "$tap/Casks/axial.rb"
  # --custom-remote taps may be cloned, not symlinked.
  cp "$tap/Casks/axial.rb" "$installed_tap/Casks/axial.rb"
  cache=$(brew --cache --cask consi/axial-ci/axial)
  mkdir -p "$(dirname "$cache")";cp "$legacy/Axial-$old-universal.pkg" "$cache"
  brew install --cask consi/axial-ci/axial
  if [[ "$old" == 0.1.0 ]]; then
    bash tests/legacy_install_guard.sh "$PWD" "$legacy/Axial-$old-universal.pkg"
  fi
  cp "$tap/current.rb" "$installed_tap/Casks/axial.rb"
  rm -f "$tap/ready"
  "$tap/hold-framework" /Library/Frameworks/3DconnexionClient.framework/3DconnexionClient "$tap/ready" &
  holder=$!
  for attempt in {1..100}; do [[ ! -f "$tap/ready" ]] || break; sleep 0.05; done
  [[ -f "$tap/ready" ]]
  if [[ "$old" == 0.1.0 ]]; then
    for name in 3DconnexionClient 3DconnexionNavlib; do
      sudo /usr/libexec/PlistBuddy -c 'Delete :CFBundleIdentifier' "/Library/Frameworks/$name.framework/Resources/Info.plist"
    done
    sudo rm /Library/Frameworks/3DconnexionClient.framework/Headers/ConnexionClientAPI.h
  fi
  blocked sudo /usr/sbin/installer -pkg "release/Axial-$version-universal.pkg" -target /
  kill "$holder";wait "$holder" || true
  sudo /usr/sbin/installer -pkg "release/Axial-$version-universal.pkg" -target /
  check_install_location
  brew uninstall --cask consi/axial-ci/axial
done

# The standalone uninstaller also validates ownership/use and forgets receipts.
brew install --cask consi/axial-ci/axial
sudo bash tools/uninstall.sh
[[ ! -e /Applications/Axial.app && ! -e "$foreign" && ! -e /Library/Frameworks/3DconnexionNavlib.framework ]]
[[ -z $(pkgutil --pkgs='^pro\.jest\.installer(\..*)?$') ]]
[[ -e "$HOME/Library/Application Support/Axial/ci-preserve" ]]
brew uninstall --cask consi/axial-ci/axial
