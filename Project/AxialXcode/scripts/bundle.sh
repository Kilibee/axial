#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
root="$(cd "${PROJECT_DIR}/../.." && pwd)"
product_dir="${BUILT_PRODUCTS_DIR}"
app="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
dependency_dir="${PROJECT_DIR}/Build/External"
asset_dir="${PROJECT_DIR}/Build/Assets"
generated="${PROJECT_DIR}/Build/Generated"
helper="${app}/Contents/Library/Helpers/Axial Service.app"
mkdir -p "${generated}" "${app}/Contents/Resources" \
  "${helper}/Contents/MacOS" "${helper}/Contents/Resources" \
  "${app}/Contents/Library/LaunchAgents"
sed -e "s/@PROJECT_VERSION@/${MARKETING_VERSION}/g" \
  -e "s/@CMAKE_OSX_DEPLOYMENT_TARGET@/${MACOSX_DEPLOYMENT_TARGET}/g" \
  "${root}/app/Manifests/AxialService.plist.in" > "${generated}/AxialService.plist"
cp "${asset_dir}/Axial.icns" "${asset_dir}/ToyCar.scn" "${app}/Contents/Resources/"
cp "${product_dir}/axial-service" "${helper}/Contents/MacOS/axial-service"
cp "${product_dir}/axialctl" "${app}/Contents/Library/Helpers/axialctl"
cp "${product_dir}/axial-web-setup" "${app}/Contents/Library/Helpers/axial-web-setup"
cp "${generated}/AxialService.plist" "${helper}/Contents/Info.plist"
cp "${asset_dir}/Axial.icns" "${helper}/Contents/Resources/Axial.icns"
cp "${root}/app/Manifests/pro.jest.service.plist" "${app}/Contents/Library/LaunchAgents/"
cp "${root}/LICENSE" "${dependency_dir}/_deps/axial_boost-src/LICENSE_1_0.txt" "${app}/Contents/Resources/"
cp "${dependency_dir}/tls/arm64/src/axial_tls_arm64/LICENSE.txt" "${app}/Contents/Resources/OpenSSL-LICENSE.txt"
cp "${root}/third_party/toycar/CC0-1.0.txt" "${app}/Contents/Resources/ToyCar-CC0-1.0.txt"
cp "${root}/third_party/toycar/UPSTREAM-README.md" "${app}/Contents/Resources/ToyCar-credits.txt"
for nested in "${helper}" "${app}/Contents/Library/Helpers/axialctl" "${app}/Contents/Library/Helpers/axial-web-setup"; do
  /usr/bin/codesign --force --options runtime --sign - "${nested}"
done
