#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Map changed files to the AllTests classes that cover them, so an iteration
# run touches ~1% of the suite instead of all of it.
#
# Usage:
#   scripts/test/affected-tests.sh                 # working tree vs HEAD
#   scripts/test/affected-tests.sh origin/main     # everything since a ref
#   scripts/test/affected-tests.sh --run           # run the affected classes
#   scripts/test/affected-tests.sh --args          # emit `-f A -f B` for AllTests
#
# Selection is name-based and deliberately over-includes: a class is selected if
# it is a changed test file, or if any test file naming a changed source symbol
# maps to it. It is a fast pre-merge filter, not a substitute for the full
# `--gated=run` pass before pushing.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
cd "$repo_root"

test_binary="${repo_root}/build/tests/AllTests"

mode="classes"
base=""
for arg in "$@"; do
  case "$arg" in
    --run) mode="run" ;;
    --args) mode="args" ;;
    --classes) mode="classes" ;;
    -h|--help) sed -n '4,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) base="$arg" ;;
  esac
done

if [[ ! -x "$test_binary" ]]; then
  echo "Test binary not found at ${test_binary}" >&2
  echo "Build it first: cmake --build build --target AllTests --parallel 4" >&2
  exit 1
fi

# ── Changed files ────────────────────────────────────────────────────────
# Declared before the trap so `set -u` cannot trip on an early exit.
changed=""; symbols=""; candidates=""; registered=""; selected=""
trap 'rm -f "$changed" "$symbols" "$candidates" "$registered" "$selected"' EXIT
changed="$(mktemp)"
if [[ -n "$base" ]]; then
  git diff --name-only "$base"...HEAD > "$changed"
  git diff --name-only HEAD >> "$changed"
else
  git diff --name-only HEAD > "$changed"
fi
git ls-files --others --exclude-standard >> "$changed"
sort -u -o "$changed" "$changed"

# ── Symbols to look for in the test tree ─────────────────────────────────
# A changed source file contributes its basename (minus any +Category suffix)
# and every @interface/@implementation name it declares.
symbols="$(mktemp)"
candidates="$(mktemp)"
: > "$symbols"
: > "$candidates"

while IFS= read -r file; do
  [[ -f "$file" ]] || continue
  case "$file" in
    Garazyk/Tests/*.m)
      # A changed test file selects its own classes directly.
      grep -hoE '^@(interface|implementation) [A-Za-z0-9_]+' "$file" 2>/dev/null \
        | awk '{print $2}' >> "$candidates" || true
      ;;
    Garazyk/Sources/*.m|Garazyk/Sources/*.h)
      base_name="$(basename "$file")"
      base_name="${base_name%.*}"
      printf '%s\n' "${base_name%%+*}" >> "$symbols"
      grep -hoE '^@(interface|implementation) [A-Za-z0-9_]+' "$file" 2>/dev/null \
        | awk '{print $2}' >> "$symbols" || true
      ;;
  esac
done < "$changed"

sort -u -o "$symbols" "$symbols"

# ── Test files naming those symbols → their classes ──────────────────────
if [[ -s "$symbols" ]]; then
  if command -v rg >/dev/null 2>&1; then
    matches="$(rg -l -F -f "$symbols" Garazyk/Tests --glob '*.m' 2>/dev/null || true)"
  else
    matches="$(grep -rlF -f "$symbols" Garazyk/Tests --include='*.m' 2>/dev/null || true)"
  fi
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    grep -hoE '^@(interface|implementation) [A-Za-z0-9_]+' "$hit" 2>/dev/null \
      | awk '{print $2}' >> "$candidates" || true
  done <<< "$matches"
fi

sort -u -o "$candidates" "$candidates"

# ── Keep only names the runner actually registers ────────────────────────
registered="$(mktemp)"
"$test_binary" --list 2>/dev/null | sed 's/ \[gated:.*\]//' | awk 'NF' | sort -u > "$registered"

selected="$(mktemp)"
comm -12 "$candidates" "$registered" > "$selected"

if [[ ! -s "$selected" ]]; then
  echo "No affected test classes found for the changed files." >&2
  echo "Nothing to run; fall back to a category or the full suite if the change is broad." >&2
  exit 0
fi

case "$mode" in
  classes)
    cat "$selected"
    echo "--- $(wc -l < "$selected" | tr -d ' ') of $(wc -l < "$registered" | tr -d ' ') registered classes" >&2
    ;;
  args)
    while IFS= read -r cls; do printf -- '-f %s ' "$cls"; done < "$selected"
    echo
    ;;
  run)
    args=()
    while IFS= read -r cls; do args+=(-f "$cls"); done < "$selected"
    echo "==> ${#args[@]} filters; running $(wc -l < "$selected" | tr -d ' ') classes" >&2
    exec "$test_binary" --gated=run "${args[@]}"
    ;;
esac
