#!/usr/bin/env bash
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "Usage: $0 <path>"
  exit 1
fi
path="$1"
printf "Scanning %s for TODO/FIXME/stub markers...\n" "$path"
rg --color never -n "TODO|FIXME|not implemented|stub" "$path"
