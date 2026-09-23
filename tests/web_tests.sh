#!/bin/bash
set -euo pipefail
credentials=$(mktemp -d)
trap 'rm -f "$credentials/root.crt" "$credentials/server.crt" "$credentials/server.key"; rmdir "$credentials"' EXIT
"$1" --prepare "$credentials"
[[ $(stat -f '%Lp' "$credentials/server.key") == 600 ]]
[[ ! -e "$credentials/root.key" ]]
/usr/bin/security verify-cert -c "$credentials/server.crt" -r "$credentials/root.crt" -p ssl -n 127.51.68.120 -N -L -q
if "$1" --prepare "$credentials" >/dev/null 2>&1; then
  echo 'Setup must not overwrite existing credentials' >&2; exit 1
fi
"$2" "$credentials"
