#!/usr/bin/env bash
set -euo pipefail

root="."
ignore_file=""
json=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      json=1
      shift
      ;;
    --ignore-file)
      ignore_file="$2"
      shift 2
      ;;
    *)
      root="$1"
      shift
      ;;
  esac
done

search_dir="$root/Garazyk/Sources"

if [ ! -d "$search_dir" ]; then
  search_dir="$root"
fi

if [ "$json" -eq 1 ]; then
  SEARCH_DIR="$search_dir" IGNORE_FILE="$ignore_file" python3 - <<'PY'
import json
import os
import subprocess

search_dir = os.environ["SEARCH_DIR"]
ignore_file = os.environ.get("IGNORE_FILE") or None

def run(pattern):
    cmd = ["rg", "-n", "-S", pattern, search_dir]
    if ignore_file:
        cmd.extend(["--ignore-file", ignore_file])
    try:
        output = subprocess.check_output(cmd, text=True)
    except subprocess.CalledProcessError as exc:
        output = exc.output or ""
    results = []
    for line in output.splitlines():
        parts = line.split(":", 2)
        if len(parts) == 3:
            results.append({"file": parts[0], "line": int(parts[1]), "match": parts[2].strip()})
    return results

report = {
    "not_implemented": run("not_implemented"),
    "todo_fixme": run("TODO|FIXME"),
    "stub_markers": run("\\.stub\\b|\\bstub\\b"),
}

print(json.dumps(report, indent=2, sort_keys=True))
PY
  exit 0
fi

rg_args=(-n -S)
if [ -n "$ignore_file" ]; then
  rg_args+=(--ignore-file "$ignore_file")
fi

echo "== not_implemented =="
rg "${rg_args[@]}" "not_implemented" "$search_dir" || true

echo ""
echo "== TODO/FIXME =="
rg "${rg_args[@]}" "TODO|FIXME" "$search_dir" || true

echo ""
echo "== stub markers =="
rg "${rg_args[@]}" "\\.stub\\b|\\bstub\\b" "$search_dir" || true
