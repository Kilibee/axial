#!/bin/bash
set -euo pipefail
major="${1:-26}"
# Choose the newest installed non-beta patch of the requested Xcode major.
developer=$(find /Applications -maxdepth 1 -name "Xcode_${major}*.app" |
  grep -E "/Xcode_${major}([.][0-9]+)*[.]app$" | sort -V | tail -1)
[[ -n "$developer" ]] || { echo 'Required Xcode major is not installed' >&2; exit 1; }
export DEVELOPER_DIR="$developer/Contents/Developer"
sw_vers
uname -m
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
cmake --preset xcode -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
cmake --build --preset xcode
ctest --preset xcode -LE gui
cpack --preset xcode
mkdir -p build/release/tests build/release/fixtures
cp build/xcode/packages/Axial-*-universal.pkg build/release/
cp build/xcode/bin/Release/*-tests build/release/tests/
cp tests/fixtures/spaceexplorer-motion.txt tests/fixtures/upstream-device-buttons.toml build/release/fixtures/
cp tools/ci-runtime.sh build/release/
tar -czf build/release-tests.tar.gz -C build/release tests fixtures ci-runtime.sh
cp build/release-tests.tar.gz build/release/
cd build/release
shasum -a 256 Axial-*-universal.pkg > SHA256SUMS
