#!/bin/bash
set -euo pipefail
source "$1/tools/install-guard.sh"
holder_binary=$2
temporary=$(mktemp -d)
holder=''
cleanup() { if [[ -n "$holder" ]]; then kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true; fi; rm -rf "$temporary"; }
trap cleanup EXIT
root="$temporary/volume"
mkdir -p "$root/Library/Frameworks"
for source in "$3" "$4"; do
  name=$(basename "$source" .framework)
  target="$root/Library/Frameworks/$name.framework"
  ditto "$source" "$target"
  axial_check "$root"
  rm -f "$temporary/ready"
  "$holder_binary" "$target/$name" "$temporary/ready" &
  holder=$!
  for attempt in {1..100}; do [[ ! -f "$temporary/ready" ]] || break; sleep 0.01; done
  [[ -f "$temporary/ready" ]]
  if axial_check "$root" > "$temporary/result" 2>&1; then echo 'Mapped framework was not detected' >&2; exit 1; fi
  grep -q "PID $holder" "$temporary/result"
  kill "$holder";wait "$holder" || true;holder=''
  axial_check "$root"
done
echo 'PASS: Client and Navlib executable mappings block replacement until the client exits'
