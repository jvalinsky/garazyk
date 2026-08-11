#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
# Reject Objective-C setters that recurse by assigning their own property.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

matches="$(
  while IFS= read -r source; do
    [[ -f "$source" ]] || continue
    perl -0ne '
      while (/^[ \t]*-[ \t]*\([^)]*\)[ \t]*set([A-Z][A-Za-z0-9_]*)[ \t]*:[ \t]*\([^)]*\)[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*\{/mg) {
        my ($name, $parameter, $start) = ($1, $2, pos($_));
        my $property = lcfirst($name);
        my $end = index($_, "\n}", $start);
        $end = length($_) if $end < 0;
        my $body = substr($_, $start, $end - $start);
        if ($body =~ /\bself\.\Q$property\E[ \t]*=[ \t]*\Q$parameter\E[ \t]*;/) {
          my $line = 1 + (() = substr($_, 0, $start) =~ /\n/g);
          print "$ARGV:$line: self.$property = $parameter; recurses in -set$name:\n";
        }
      }
    ' "$source"
  done < <(git ls-files ':(glob)Garazyk/Sources/**/*.m')
)"

if [[ -n "$matches" ]]; then
  printf '%s' "$matches" >&2
  exit 1
fi
