#!/usr/bin/env bash
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "Usage: $0 <path>"
  exit 1
fi
path="$1"
printf "Scanning %s for TODO/FIXME/stub markers...\n" "$path"
set +e
rg --color never -n "TODO|FIXME|not implemented|stub" "$path"
rg_status=$?
set -e

# ripgrep returns:
# - 0: matches found
# - 1: no matches (not an error for this script)
# - 2: actual error (bad args, unreadable path, etc.)
if [ "$rg_status" -eq 2 ]; then
  exit 2
fi
