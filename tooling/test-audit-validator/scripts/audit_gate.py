#!/usr/bin/env python3
"""Validate machine-readable gate conditions for audit JSON artifacts."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", required=True, help="Path to audit JSON artifact")
    parser.add_argument(
        "--parser-mode",
        required=True,
        choices=("auto", "clang", "simple"),
        help="Expected parser_mode metadata value",
    )
    parser.add_argument(
        "--require-no-critical",
        action="store_true",
        help="Fail if critical findings are present",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    path = Path(args.path)
    if not path.exists():
        print(f"missing artifact: {path}", file=sys.stderr)
        return 2

    data = json.loads(path.read_text())
    metadata = data.get("metadata", {})
    statistics = data.get("statistics", {})
    severity = statistics.get("issues_by_severity", {})
    errors = data.get("errors", [])

    parser_mode = metadata.get("parser_mode")
    attempted = int(metadata.get("clang_attempted_count", 0))
    fallbacks = int(metadata.get("clang_fallback_count", 0))
    critical = int(severity.get("critical", 0))

    problems: list[str] = []
    if parser_mode != args.parser_mode:
        problems.append(f"parser_mode expected {args.parser_mode!r}, got {parser_mode!r}")
    if args.parser_mode in ("auto", "clang") and attempted <= 0:
        problems.append(f"clang_attempted_count must be > 0, got {attempted}")
    if fallbacks != 0:
        problems.append(f"clang_fallback_count must be 0, got {fallbacks}")
    if errors:
        problems.append(f"errors array must be empty, got {len(errors)}")
    if args.require_no_critical and critical > 0:
        problems.append(f"critical findings must be 0, got {critical}")

    if problems:
        for issue in problems:
            print(f"gate failure: {issue}", file=sys.stderr)
        return 1

    print("gate passed")
    print(f"  parser_mode={parser_mode} attempted={attempted} fallbacks={fallbacks} critical={critical}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
