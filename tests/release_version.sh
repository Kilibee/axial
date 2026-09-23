#!/bin/bash
set -euo pipefail
root=$1
[[ $(bash "$root/tools/release-version.sh" refs/tags/v0.1.1) == 0.1.1 ]]
[[ $(bash "$root/tools/release-version.sh" refs/tags/v0.2.0) == 0.2.0 ]]
[[ $(bash "$root/tools/release-version.sh" refs/tags/v12.34.56) == 12.34.56 ]]
for invalid in refs/heads/main refs/tags/0.1.1 refs/tags/v1.2 refs/tags/v1.2.3-rc1 ''; do
  if bash "$root/tools/release-version.sh" "$invalid" >/dev/null 2>&1; then exit 1; fi
done
echo 'Release version validation passed'
