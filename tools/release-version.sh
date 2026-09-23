#!/bin/bash
set -euo pipefail
if [[ "${1:-}" =~ ^refs/tags/v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  printf '%s\n' "${BASH_REMATCH[1]}"
else
  echo '::error::Release requires a tag named vMAJOR.MINOR.PATCH; select a tag when dispatching manually.' >&2
  exit 1
fi
