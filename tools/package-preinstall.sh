#!/bin/bash
set -euo pipefail
# install-guard.sh is embedded here by CMake in the package script.
source "$(dirname "$0")/install-guard.sh"
axial_check "${3:-/}"
