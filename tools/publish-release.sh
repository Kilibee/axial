#!/bin/bash
set -euo pipefail
tag="v$VERSION"
package="Axial-$VERSION-universal.pkg"
cd release
sha256sum -c SHA256SUMS
if ! gh release view "$tag" --repo consi/axial >/dev/null 2>&1; then
  gh release create "$tag" --repo consi/axial --verify-tag --draft --title "Axial $VERSION" --notes-file ../tools/release-notes.md
fi
existing=$(mktemp -d)
for asset in "$package" SHA256SUMS; do
  if gh release view "$tag" --repo consi/axial --json assets --jq '.assets[].name' | grep -Fxq "$asset"; then
    gh release download "$tag" --repo consi/axial --pattern "$asset" --dir "$existing"
    cmp "$asset" "$existing/$asset"
  else
    [[ $(gh release view "$tag" --repo consi/axial --json isDraft --jq .isDraft) == true ]]
    gh release upload "$tag" "$asset" --repo consi/axial
  fi
done
if [[ $(gh release view "$tag" --repo consi/axial --json isDraft --jq .isDraft) == true ]]; then
  gh release edit "$tag" --repo consi/axial --draft=false --latest
fi
