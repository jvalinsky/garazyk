#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
"""Collect public headers reachable from a Garazyk module umbrella header."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

IMPORT_RE = re.compile(r'^\s*#import\s+"([^"]+)"\s*$', re.MULTILINE)


def resolve_import(repo_root: Path, importer: Path, import_path: str) -> Path | None:
    if import_path.startswith("Frameworks/"):
        candidate = repo_root / "Garazyk" / import_path
    else:
        candidate = repo_root / "Garazyk" / "Sources" / import_path
    if candidate.is_file():
        return candidate
    # Umbrella headers live under Garazyk/Frameworks/<Module>/ but import
    # Sources-relative paths; also try relative to importer directory.
    relative = (importer.parent / import_path).resolve()
    if relative.is_file():
        return relative
    return None


def collect(repo_root: Path, umbrella: Path, seen: set[Path] | None = None) -> list[Path]:
    if seen is None:
        seen = set()
    umbrella = umbrella.resolve()
    if umbrella in seen or not umbrella.is_file():
        return []
    seen.add(umbrella)
    ordered: list[Path] = [umbrella]
    text = umbrella.read_text(encoding="utf-8", errors="replace")
    for match in IMPORT_RE.finditer(text):
        imported = resolve_import(repo_root, umbrella, match.group(1))
        if imported is None:
            print(f"warning: missing import {match.group(1)!r} from {umbrella}", file=sys.stderr)
            continue
        for header in collect(repo_root, imported, seen):
            if header not in ordered:
                ordered.append(header)
    return ordered


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo_root", type=Path)
    parser.add_argument("umbrella", type=Path)
    parser.add_argument("--cmake-list", action="store_true", help="Emit semicolon-separated CMake paths")
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    umbrella = args.umbrella if args.umbrella.is_absolute() else repo_root / args.umbrella
    headers = collect(repo_root, umbrella)
    if args.cmake_list:
        rel_paths = []
        for header in headers:
            try:
                rel = header.relative_to(repo_root)
            except ValueError:
                rel = header
            rel_paths.append(str(rel).replace("\\", "/"))
        sys.stdout.write(";".join(rel_paths))
    else:
        for header in headers:
            sys.stdout.write(f"{header}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
