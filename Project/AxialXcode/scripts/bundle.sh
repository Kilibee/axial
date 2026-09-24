#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
root="$(cd "${PROJECT_DIR}/../.." && pwd)"
product_dir="${BUILT_PRODUCTS_DIR}"
app="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
dependency_dir="${PROJECT_DIR}/Build/External"
asset_dir="${PROJECT_DIR}/Build/Assets"
generated="${PROJECT_DIR}/Build/Generated"
mkdir -p "${generated}" "${app}/Contents/Resources"
sed -e "s/@PROJECT_VERSION@/${MARKETING_VERSION}/g" \
  -e "s/@CMAKE_OSX_DEPLOYMENT_TARGET@/${MACOSX_DEPLOYMENT_TARGET}/g" \
  "${root}/app/Manifests/AxialService.plist.in" > "${generated}/AxialService.plist"
cp "${asset_dir}/Axial.icns" "${asset_dir}/ToyCar.scn" "${app}/Contents/Resources/"
cp "${asset_dir}/Axial.icns" "${generated}/Axial.icns"
cmake -DAPP="${app}" -DSERVICE="${product_dir}/axial-service" \
  -DCLI="${product_dir}/axialctl" -DWEB_SETUP="${product_dir}/axial-web-setup" \
  -DGENERATED="${generated}" -DSOURCE_DIR="${root}" \
  -DBOOST_SOURCE="${dependency_dir}/_deps/axial_boost-src" \
  -DTLS_SOURCE="${dependency_dir}/tls/arm64/src/axial_tls_arm64" \
  -DIDENTITY=- -P "${root}/cmake/Bundle.cmake"
