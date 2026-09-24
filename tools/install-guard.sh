#!/bin/bash
# Shared by the generated cask, package preinstall, CMake and uninstaller.
# No changes to the installation are allowed before axial_check succeeds.
source "$(dirname "${BASH_SOURCE[0]}")/legacy-files.sh"

# Match every surviving entry against ONE published release. Missing files are
# allowed, but there must still be a byte-identical Axial executable as evidence
# of ownership. Receipts and third-party headers alone cannot establish this.
axial_legacy_owned() (
  set -euo pipefail
  local bundle=$1 name=$2 temporary entry kind value excluded
  temporary=$(/usr/bin/mktemp -d) || exit 1
  trap '/bin/rm -rf "$temporary"' EXIT
  cd "$bundle" || exit 1
  excluded=./Versions/A/Resources/Info.plist
  [[ "$name" != Axial ]] || excluded=./Contents/Info.plist
  /usr/bin/find -s . -print0 > "$temporary/entries" || exit 1
  while IFS= read -r -d '' entry; do
    [[ "$entry" != "$excluded" ]] || continue
    [[ "$entry" != *'|'* && "$entry" != *$'\n'* ]] || exit 1
    if [[ -L "$entry" ]]; then
      kind=l;value=$(/usr/bin/readlink "$entry") || exit 1
    elif [[ -d "$entry" ]]; then
      kind=d;value=-
    elif [[ -f "$entry" ]]; then
      kind=f;value=$(/usr/bin/shasum -a 256 "$entry" | /usr/bin/awk '{print $1}') || exit 1
    else
      exit 1
    fi
    printf '%s|%s|%s\n' "$kind" "$value" "$entry"
  done < "$temporary/entries" > "$temporary/actual"
  axial_known_files > "$temporary/known" || exit 1
  /usr/bin/awk -F '|' -v name="$name" '
    NR == FNR {if ($2 == name) {versions[$1]=1; known[$1 SUBSEP $5]=$3 "|" $4}; next}
    {
      for (version in versions) {
        if (known[version SUBSEP $3] != $1 "|" $2) rejected[version]=1
        else if ($1 == "f" && ($3 == "./Versions/A/" name || $3 == "./Contents/MacOS/Axial" ||
          $3 == "./Contents/Library/Helpers/axialctl" ||
          $3 == "./Contents/Library/Helpers/Axial Service.app/Contents/MacOS/axial-service")) anchor[version]=1
      }
    }
    END {for (version in versions) if (!rejected[version] && anchor[version]) exit 0; exit 1}
  ' "$temporary/known" "$temporary/actual"
)

axial_check() (
  set -euo pipefail
  local root="${1:-/}" name bundle plist identity result link target
  root=$(cd "$root" && pwd -P) || { echo 'Cannot inspect installation volume.' >&2; exit 1; }
  local bundles=()
  for name in Axial 3DconnexionClient 3DconnexionNavlib; do
    if [[ "$name" == Axial ]]; then
      bundle="${root%/}/Applications/Axial.app"
      plist="$bundle/Contents/Info.plist"
    else
      bundle="${root%/}/Library/Frameworks/$name.framework"
      plist="$bundle/Resources/Info.plist"
    fi
    [[ -e "$bundle" || -L "$bundle" ]] || continue
    # Never follow an installation redirected into an unrelated directory.
    if [[ -L "$bundle" || ! -d "$bundle" || $(cd "$bundle" && pwd -P) != "$bundle" ]]; then
      echo "Refusing redirected or invalid Axial bundle: $bundle" >&2; exit 1
    fi
    while IFS= read -r -d '' link; do
      target=$(/usr/bin/readlink "$link") || exit 1
      if [[ "$target" == /* || "$target" == .. || "$target" == ../* || "$target" == */../* || "$target" == */.. ]]; then
        echo "Refusing broken or redirected Axial bundle link: $link" >&2; exit 1
      fi
    done < <(/usr/bin/find "$bundle" -type l -print0)
    identity=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null) || identity=''
    if [[ "$identity" != "pro.jest.$name" ]]; then
      if [[ -n "$identity" ]] || ! axial_legacy_owned "$bundle" "$name"; then
        echo "Refusing to change $bundle: missing, invalid or foreign bundle identity; surviving files do not identify a supported Axial installation." >&2
        echo 'Restore the original bundle or uninstall its owning driver, then retry.' >&2
        exit 1
      fi
    fi
    bundles+=("$bundle")
  done
  [[ ${#bundles[@]} -gt 0 ]] || exit 0
  # lsof reports executable mappings as well as open file descriptors. Run as
  # root on the live volume to include applications belonging to other users.
  if [[ "$root" == / && $EUID != 0 ]]; then
    echo 'Administrator access is required to check applications using Axial.' >&2; exit 1
  fi
  local temporary
  temporary=$(/usr/bin/mktemp -d) || exit 1
  trap '/bin/rm -rf "$temporary"' EXIT
  local busy=0
  for bundle in "${bundles[@]}"; do
    result=0
    /usr/sbin/lsof -nP -Fpcn +D "$bundle" > "$temporary/users" 2> "$temporary/errors" || result=$?
    if [[ -s "$temporary/errors" || $result -gt 1 ]]; then
      echo "Cannot check processes using $bundle; installation has not been changed." >&2
      cat "$temporary/errors" >&2; exit 1
    fi
    if [[ -s "$temporary/users" ]]; then
      echo "Axial files are in use: $bundle" >&2
      /usr/bin/awk '/^p/ {pid=substr($0,2)} /^c/ {printf "  %s (PID %s)\n", substr($0,2), pid}' "$temporary/users" >&2
      busy=1
    fi
  done
  if [[ $busy == 1 ]]; then
    echo 'Quit the listed applications (including Axial), then retry. No installed files have been changed.' >&2
    exit 1
  fi
)
