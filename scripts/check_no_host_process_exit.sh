#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Workstream 08 M7: library code (the ten ATProto* package-target sources
# under Garazyk/Sources/) must not unilaterally terminate the host process.
# That decision belongs to the binary composition root (Garazyk/Binaries/*)
# or to an explicit caller-owned callback (see GZServiceLifecycle).
#
# Rejects bare exit(...) and abort(...) calls. _exit(...) is intentionally
# exempt: it is the only async-signal-safe / post-fork-safe termination
# primitive, and is already used correctly at the few call sites that
# legitimately need it (a forked child after a failed execv, a re-entrant
# crash handler) - see GZCrashReporter.m and PDSCLIDaemonCommand.m.
#
# Line (//) and block (/* */) comments are stripped before matching (byte
# length and line breaks preserved) so prose that merely mentions
# exit()/abort() does not trip the gate.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

matches=""
while IFS= read -r source; do
  hit="$(perl -0pe 's{/\*.*?\*/}{ my $s = $&; $s =~ s/[^\n]/ /g; $s }gse; s{//[^\n]*}{}g' "$source" \
    | grep -nE '(^|[^A-Za-z0-9_])(exit|abort)\(' | sed "s#^#${source}:#" || true)"
  if [[ -n "$hit" ]]; then
    matches="${matches}${hit}"$'\n'
  fi
done < <(git ls-files ':(glob)Garazyk/Sources/**/*.m' | grep -v '/Tests/')

if [[ -n "$matches" ]]; then
  echo "error: found exit()/abort() in library sources (Garazyk/Sources/**/*.m)." >&2
  echo "Terminating the host process is not a library decision (workstream 08 M7)." >&2
  echo "Use an error return, a caller-owned lifecycle callback (see GZServiceLifecycle)," >&2
  echo "or _exit() if this is a post-fork/async-signal-safe path that genuinely cannot" >&2
  echo "return to a caller." >&2
  echo >&2
  printf '%s' "$matches" >&2
  exit 1
fi

echo "No exit()/abort() calls found in Garazyk/Sources/**/*.m."
