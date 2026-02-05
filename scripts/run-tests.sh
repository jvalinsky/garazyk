#!/usr/bin/env bash
#
# Run the native unit test binary (`build/tests/AllTests`).
#
# Notes:
# - On macOS, the `AllTests` runner links against `XCTest.framework`, which
#   typically requires a full Xcode install (not just Command Line Tools).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_ROOT

ALLTESTS_BIN="$PROJECT_ROOT/build/tests/AllTests"
readonly ALLTESTS_BIN

echo "Running all tests..."

if [[ ! -x "$ALLTESTS_BIN" ]]; then
  echo "ERROR: Test runner not found: $ALLTESTS_BIN" >&2
  echo "Build it with:" >&2
  echo "  xcodebuild -scheme AllTests build" >&2
  exit 1
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
  if [[ -z "$DEV_DIR" ]] || [[ "$DEV_DIR" == "/Library/Developer/CommandLineTools" ]]; then
    echo "ERROR: Xcode is required to run AllTests (XCTest.framework not found via Command Line Tools)." >&2
    echo "Install Xcode, then run:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
  fi
fi

"$ALLTESTS_BIN"

echo "Tests complete."
