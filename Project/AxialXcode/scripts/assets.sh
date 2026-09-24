#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
root="$(cd "${PROJECT_DIR}/../.." && pwd)"
asset_dir="${PROJECT_DIR}/Build/Assets"
tool_dir="${PROJECT_DIR}/Build/Tools"
mkdir -p "${asset_dir}" "${tool_dir}"
mkdir -p "${tool_dir}/ModuleCache"
xcrun swiftc -module-cache-path "${tool_dir}/ModuleCache" -parse-as-library "${root}/tools/make-icon.swift" -o "${tool_dir}/make-icon"
"${tool_dir}/make-icon" "${asset_dir}/Axial.iconset"
xcrun iconutil --convert icns --output "${asset_dir}/Axial.icns" "${asset_dir}/Axial.iconset"
cmake -DSOURCE_DIR="${root}" -P "${root}/cmake/VerifyAssets.cmake"
xcrun swiftc -module-cache-path "${tool_dir}/ModuleCache" -parse-as-library "${root}/tools/convert-toycar.swift" -o "${tool_dir}/convert-toycar"
"${tool_dir}/convert-toycar" "${root}/third_party/toycar/source" "${asset_dir}/ToyCar.scn"
