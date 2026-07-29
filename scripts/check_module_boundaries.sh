#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Workstream 08 M1: link-time module-boundary gate.
#
# The declared ATProto* library dependency graph in CMakeLists.txt is
# documentation only — static archives defer symbol resolution to the final
# executable link, so a class reference that violates the declared layering
# never fails a build. This script makes the graph enforceable: for each
# ATProto* archive, it computes the Objective-C classes the archive actually
# references but does not itself define, resolves each to the ATProto*
# archive (if any) that defines it, and flags any resolution outside that
# archive's declared transitive PUBLIC dependency set.
#
# Usage: scripts/check_module_boundaries.sh [build-dir]
#
# Exits 1 if any leak not already recorded in the baseline file is found.
# The baseline (docs/module-boundary-baseline.txt) may shrink as
# modules are cleaned up; it must never grow silently — new leaks require a
# deliberate baseline edit in the same commit that introduces them, so
# review sees the regression.
#
# Written for bash 3.2 (macOS system default) — no associative arrays.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="${1:-build}"
CMAKE_FILE="CMakeLists.txt"
BASELINE="docs/module-boundary-baseline.txt"

MODULES="ATProtoCore ATProtoStorage ATProtoServices ATProtoTransport ATProtoXRPC ATProtoSync ATProtoPLC ATProtoRuntime ATProtoMediaCore ATProtoVideoService"

for m in $MODULES; do
  lib="$BUILD_DIR/lib${m}.a"
  if [[ ! -f "$lib" ]]; then
    echo "FAIL: $lib not found — build AllTests (or any target) first" >&2
    exit 1
  fi
done

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

is_module() {
  local candidate="$1"
  for m in $MODULES; do
    [[ "$candidate" == "$m" ]] && return 0
  done
  return 1
}

# --- Step 1: declared PUBLIC deps per module, parsed from CMakeLists.txt ---
# Each module's directly-declared deps live in $WORKDIR/declared_<module>.txt
for m in $MODULES; do
  : > "$WORKDIR/declared_${m}.txt"
done
while IFS= read -r line; do
  target="$(sed -E 's/target_link_libraries\(([A-Za-z0-9]+) PUBLIC.*/\1/' <<<"$line")"
  rest="$(sed -E 's/target_link_libraries\([A-Za-z0-9]+ PUBLIC (.*)\)/\1/' <<<"$line")"
  is_module "$target" || continue
  for tok in $rest; do
    if is_module "$tok"; then
      echo "$tok" >> "$WORKDIR/declared_${target}.txt"
    fi
  done
done < <(grep -E '^\s*target_link_libraries\(ATProto[A-Za-z]+ PUBLIC' "$CMAKE_FILE")

# --- Step 2: transitive closure of declared PUBLIC deps, per module ---
# $WORKDIR/allowed_<module>.txt = module itself + full transitive PUBLIC dep closure.
for m in $MODULES; do
  echo "$m" > "$WORKDIR/allowed_${m}.txt"
  sort -u -o "$WORKDIR/declared_${m}.txt" "$WORKDIR/declared_${m}.txt"
  cat "$WORKDIR/declared_${m}.txt" >> "$WORKDIR/allowed_${m}.txt"
  sort -u -o "$WORKDIR/allowed_${m}.txt" "$WORKDIR/allowed_${m}.txt"
done
changed=1
while [[ $changed -eq 1 ]]; do
  changed=0
  for m in $MODULES; do
    before="$(wc -l < "$WORKDIR/allowed_${m}.txt")"
    for dep in $(cat "$WORKDIR/allowed_${m}.txt"); do
      [[ "$dep" == "$m" ]] && continue
      cat "$WORKDIR/allowed_${dep}.txt" >> "$WORKDIR/allowed_${m}.txt"
    done
    sort -u -o "$WORKDIR/allowed_${m}.txt" "$WORKDIR/allowed_${m}.txt"
    after="$(wc -l < "$WORKDIR/allowed_${m}.txt")"
    [[ "$after" -ne "$before" ]] && changed=1
  done
done

# --- Step 3: for each module, defined _OBJC_CLASS_$_ symbols (any .o in the archive defines it) ---
for m in $MODULES; do
  nm "$BUILD_DIR/lib${m}.a" 2>/dev/null \
    | awk '/_OBJC_CLASS_\$_/ && $1 != "U" && NF >= 2 {print $NF}' \
    | sed 's/^_OBJC_CLASS_\$_//' \
    | sort -u > "$WORKDIR/${m}.defined"
done

# --- Step 4: global map class -> owning module (skip classes defined in more than one module — ambiguous, not actionable here) ---
cat "$WORKDIR"/*.defined | sort | uniq -d > "$WORKDIR/ambiguous.classes"
: > "$WORKDIR/class_owner.map"
for m in $MODULES; do
  comm -23 "$WORKDIR/${m}.defined" "$WORKDIR/ambiguous.classes" | while IFS= read -r cls; do
    echo "$cls $m" >> "$WORKDIR/class_owner.map"
  done
done

# --- Step 5+6: per module, truly-external undefined classes resolved to a leak ---
: > "$WORKDIR/leaks.txt"
for m in $MODULES; do
  nm "$BUILD_DIR/lib${m}.a" 2>/dev/null \
    | awk '/_OBJC_CLASS_\$_/ && $1 == "U" {print $NF}' \
    | sed 's/^_OBJC_CLASS_\$_//' \
    | sort -u > "$WORKDIR/${m}.undef"
  comm -23 "$WORKDIR/${m}.undef" "$WORKDIR/${m}.defined" > "$WORKDIR/${m}.external"

  while IFS= read -r cls; do
    [[ -z "$cls" ]] && continue
    owner="$(awk -v c="$cls" '$1 == c {print $2}' "$WORKDIR/class_owner.map")"
    [[ -z "$owner" ]] && continue          # not one of our modules (Foundation/system/vendored) — not a boundary leak
    [[ "$owner" == "$m" ]] && continue     # defined in self, shouldn't happen post steps 3/5 but stay safe
    if ! grep -qx "$owner" "$WORKDIR/allowed_${m}.txt"; then
      echo "${m}:${cls} (defined in ${owner}, not a declared PUBLIC dependency of ${m})" >> "$WORKDIR/leaks.txt"
    fi
  done < "$WORKDIR/${m}.external"
done
sort -u "$WORKDIR/leaks.txt" -o "$WORKDIR/leaks.txt"

# --- Step 7: ratchet against baseline ---
mkdir -p "$(dirname "$BASELINE")"
touch "$BASELINE"
grep -v '^#' "$BASELINE" | grep -v '^[[:space:]]*$' | sort -u > "$WORKDIR/baseline.sorted" || true

new_leaks="$(comm -23 "$WORKDIR/leaks.txt" "$WORKDIR/baseline.sorted" || true)"
shrunk="$(comm -13 "$WORKDIR/leaks.txt" "$WORKDIR/baseline.sorted" || true)"

echo "==> Module boundary check ($(wc -l < "$WORKDIR/leaks.txt" | tr -d ' ') current leaks, $(wc -l < "$WORKDIR/baseline.sorted" | tr -d ' ') baselined)"

if [[ -n "$shrunk" ]]; then
  echo "--- Baseline entries no longer leaking (safe to remove from $BASELINE) ---"
  echo "$shrunk"
fi

if [[ -n "$new_leaks" ]]; then
  echo "FAIL: new module-boundary leaks not present in $BASELINE:"
  echo "$new_leaks"
  echo
  echo "If this is a deliberate, reviewed new dependency, add the PUBLIC link in"
  echo "CMakeLists.txt instead of the baseline. If it's an incidental leak that"
  echo "can't be fixed in this change, add the exact line(s) above to $BASELINE"
  echo "in the same commit, so review sees it."
  exit 1
fi

echo "PASS: no new module-boundary leaks."
