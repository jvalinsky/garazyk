#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Workstream 08 M5.1/M5.2: project-symbol namespace gate.
#
# The ATProto* static archives export a flat Objective-C class namespace.
# M5's policy reserves three semantic prefixes for project-owned types:
#   ATProto - protocol/domain primitives
#   PDS     - PDS-specific types
#   GZ      - Garazyk infrastructure
# Everything else is "unprefixed" and must be renamed (M5.3) before the
# namespace gate can close. This script enforces a shrink-only baseline over
# the unprefixed class inventory so M5.3 can proceed in small buildable
# commits without the set silently growing.
#
# Usage:
#   scripts/check_namespace.sh [build-dir]          # gate (default)
#   scripts/check_namespace.sh [build-dir] --init   # (re)generate baseline
#
# The gate scans the module archives for defined _OBJC_CLASS_$_ symbols, strips
# system/vendored classes by provenance (anything not defined in the ten
# ATProto* archives is invisible to nm here, so only project-compiled code
# appears), and classifies the remainder by the reserved prefixes above.
# Exits 1 if any unprefixed class is not already recorded in the baseline.
# The baseline (docs/namespace-baseline.txt) may shrink as classes are
# renamed; it must never grow silently — new unprefixed classes require a
# deliberate baseline edit in the same commit that introduces them, so review
# sees the regression.
#
# Written for bash 3.2 (macOS system default) — no associative arrays.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="${1:-build}"
INIT_MODE=0
if [[ "${2:-}" == "--init" ]]; then
  INIT_MODE=1
fi

BASELINE="docs/namespace-baseline.txt"

MODULES="ATProtoCore ATProtoStorage ATProtoServices ATProtoTransport ATProtoAdminUI ATProtoXRPC ATProtoSync ATProtoRelayAdminUI ATProtoPLC ATProtoRuntime ATProtoMediaCore ATProtoVideoService"

for m in $MODULES; do
  lib="$BUILD_DIR/lib${m}.a"
  if [[ ! -f "$lib" ]]; then
    echo "FAIL: $lib not found — build AllTests (or any target) first" >&2
    exit 1
  fi
done

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# --- Step 1: inventory of every defined Objective-C class across the archives.
# A class may legitimately appear in more than one archive (composition
# targets), so dedupe across the whole set — the namespace is what matters.
# System and vendored classes are excluded by provenance: nm on the archives
# only reports _defined_ symbols for code compiled into them, so Foundation,
# AppKit, libsecp256k1 (C-only), and vendored reference code do not appear
# here as defined ObjC classes.
: > "$WORKDIR/classes.raw"
for m in $MODULES; do
  nm "$BUILD_DIR/lib${m}.a" 2>/dev/null \
    | awk '/_OBJC_CLASS_\$_/ && $1 != "U" && NF >= 2 {print $NF}' \
    | sed 's/^_OBJC_CLASS_\$_//' >> "$WORKDIR/classes.raw"
done
sort -u "$WORKDIR/classes.raw" -o "$WORKDIR/classes.txt"

# --- Step 2: classify by the reserved M5 prefixes.
# Unprefixed = does not start with ATProto, PDS, or GZ. A leading underscore
# marks linker-internal or compiler-generated symbols, not public API; treat
# those as prefixed for namespace purposes.
grep -E '^(ATProto|PDS|GZ|_)' "$WORKDIR/classes.txt" > "$WORKDIR/prefixed.txt" || true
grep -vE '^(ATProto|PDS|GZ|_)' "$WORKDIR/classes.txt" > "$WORKDIR/unprefixed.txt" || true

TOTAL="$(wc -l < "$WORKDIR/classes.txt" | tr -d ' ')"
UNPREFIXED="$(wc -l < "$WORKDIR/unprefixed.txt" | tr -d ' ')"

if [[ "$INIT_MODE" -eq 1 ]]; then
  mkdir -p "$(dirname "$BASELINE")"
  {
    echo "# Workstream 08 M5.1: project-owned Objective-C classes without a reserved"
    echo "# (ATProto/PDS/GZ) prefix, as of $(date +%Y-%m-%d)."
    echo "#"
    echo "# Shrink-only: entries may be removed as classes are renamed (M5.3), but a"
    echo "# new unprefixed class must never be added silently — CI fails until either"
    echo "# the class is prefixed or this file is edited in the same commit that"
    echo "# introduces it, so review sees the regression."
    echo "#"
    echo "# Starting inventory: $UNPREFIXED unprefixed classes out of $TOTAL total."
    cat "$WORKDIR/unprefixed.txt"
  } > "$BASELINE"
  echo "==> Namespace baseline written to $BASELINE ($UNPREFIXED unprefixed classes, $TOTAL total)."
  exit 0
fi

# --- Step 3: ratchet against baseline (shrink-only). ---
grep -v '^#' "$BASELINE" | grep -v '^[[:space:]]*$' | sort -u > "$WORKDIR/baseline.sorted" || true

new_unprefixed="$(comm -23 "$WORKDIR/unprefixed.txt" "$WORKDIR/baseline.sorted" || true)"
shrunk="$(comm -13 "$WORKDIR/unprefixed.txt" "$WORKDIR/baseline.sorted" || true)"

echo "==> Namespace check ($UNPREFIXED unprefixed classes of $TOTAL total; $(wc -l < "$WORKDIR/baseline.sorted" | tr -d ' ') baselined)"

if [[ -n "$shrunk" ]]; then
  echo "--- Baseline entries no longer present (safe to remove from $BASELINE) ---"
  echo "$shrunk"
fi

if [[ -n "$new_unprefixed" ]]; then
  echo "FAIL: new unprefixed project classes not present in $BASELINE:"
  echo "$new_unprefixed"
  echo
  echo "Name the new class with a reserved prefix (ATProto/PDS/GZ) instead. If a"
  echo "new unprefixed class is unavoidable in this change, add the exact line(s)"
  echo "above to $BASELINE in the same commit, so review sees it."
  exit 1
fi

echo "PASS: no new unprefixed project classes."
