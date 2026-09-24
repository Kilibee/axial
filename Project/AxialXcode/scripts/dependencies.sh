#!/bin/bash
set -euo pipefail
root="$(cd "${PROJECT_DIR}/../.." && pwd)"
dependency_dir="${PROJECT_DIR}/Build/External"
mkdir -p "${dependency_dir}"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
cmake_bin="$(command -v cmake || true)"
if [[ -z "${cmake_bin}" ]]; then
  echo "CMake 3.29 or later is required to build Axial's dependencies." >&2
  exit 1
fi
"${cmake_bin}" -S "${root}" -B "${dependency_dir}" -G 'Unix Makefiles' \
  -DAXIAL_BUILD_APP=OFF -DBUILD_TESTING=OFF \
  '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64'
"${cmake_bin}" --build "${dependency_dir}" --target axial-tls --parallel 4
for required in \
  "${dependency_dir}/_deps/axial_boost-src/boost/asio.hpp" \
  "${dependency_dir}/tls/arm64/install/include/openssl/evp.h" \
  "${dependency_dir}/tls/libssl.a" "${dependency_dir}/tls/libcrypto.a"; do
  if [[ ! -s "${required}" ]]; then
    echo "Missing dependency output: ${required}" >&2
    exit 1
  fi
done
