#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
root="$(cd "${PROJECT_DIR}/../.." && pwd)"
if [[ "${PRODUCT_NAME}" == "3DconnexionClient" ]]; then
  adapter=Client
else
  adapter=Navlib
fi
cmake -DFRAMEWORK="${TARGET_BUILD_DIR}/${WRAPPER_NAME}" \
  -DADAPTER="${adapter}" -DSOURCE_DIR="${root}" -DIDENTITY=- \
  -P "${root}/cmake/Framework.cmake"
