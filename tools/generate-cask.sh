#!/bin/bash
set -euo pipefail
version="${1:?version required}"
directory="${2:?release directory required}"
output="${3:?output cask required}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
package="Axial-$version-universal.pkg"
digest=$(shasum -a 256 "$directory/$package" | awk '{print $1}')
[[ $(cat "$directory/SHA256SUMS") == "$digest  $package" ]]
receipts=$(jq -ce 'select(length > 0 and all(.[]; test("^pro\\.jest\\.[A-Za-z0-9_.-]+$")))' "$directory/receipts.json")
if [[ -f "$output" ]]; then
  previous=$(sed -n 's/^  version "\([0-9.]*\)"/\1/p' "$output")
  [[ -n "$previous" && $(printf '%s\n%s\n' "$previous" "$version" | sort -V | tail -1) == "$version" ]] || {
    echo 'Refusing cask downgrade' >&2; exit 1;
  }
fi
url="https://github.com/consi/axial/releases/download/v$version/$package"
mkdir -p "$(dirname "$output")"
sed -e "s|@VERSION@|$version|g" -e "s|@SHA256@|$digest|g" \
  -e "s|@URL@|$url|g" -e "s|@RECEIPTS@|$receipts|g" \
  "$(dirname "$0")/cask.rb.in" > "$output"
