#!/bin/bash
# Development harness: launch a native benchmark parent at interactive priority.
# Its app-owned helper inherits this context; shell niceness can otherwise cap QoS.
set -euo pipefail
if [[ $# -lt 4 ]]; then echo 'usage: run-benchmark-job.sh output.jsonl benchmark service client [benchmark arguments...]' >&2; exit 2; fi
output=$1;shift
mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
[[ ! -e "$output" ]] || { echo "Refusing to overwrite $output" >&2; exit 2; }
label="pro.jest.benchmark-$$"
domain="gui/$(id -u)"
plist="${output%.jsonl}.plist"
cleanup(){ launchctl bootout "$domain/$label" >/dev/null 2>&1 || true; }
trap cleanup EXIT
trap 'exit 130' INT TERM
plutil -create xml1 "$plist"
plutil -insert Label -string "$label" "$plist"
plutil -insert ProcessType -string Interactive "$plist"
plutil -insert RunAtLoad -bool YES "$plist"
plutil -insert StandardOutPath -string "$output" "$plist"
plutil -insert StandardErrorPath -string "${output%.jsonl}.log" "$plist"
plutil -insert ProgramArguments -xml '<array/>' "$plist"
index=0
artifacts=()
for argument in "$@"; do
  if [[ $index -lt 3 ]]; then argument="$(cd "$(dirname "$argument")" && pwd)/$(basename "$argument")"; artifacts+=("$argument"); fi
  plutil -insert "ProgramArguments.$index" -string "$argument" "$plist"
  index=$((index+1))
done
shasum -a 256 "${artifacts[@]}" > "${output%.jsonl}.binaries.sha256"
launchctl bootstrap "$domain" "$plist"
while true; do
  info=$(launchctl print "$domain/$label")
  state=$(awk '$1 == "state" && $2 == "=" {print $3 " " $4; exit}' <<< "$info")
  if [[ "$state" == 'not running' ]]; then
    printf '%s\n' "$info" > "${output%.jsonl}.launchd.txt"
    status=$(awk '/last exit code =/ {print $5; exit}' <<< "$info")
    [[ "$status" == 0 ]] && exit 0
    echo "Benchmark failed (exit ${status:-unknown}); see $output" >&2
    exit 1
  fi
  sleep 1
done
