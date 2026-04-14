#!/usr/bin/env python3
"""Print a compact summary table for test-audit JSON artifacts."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def summarize(base: Path) -> None:
    files = [
        ("simple", base / "audit-simple.json"),
        ("auto", base / "audit-auto.json"),
        ("clang", base / "audit-clang.json"),
    ]

    print("mode\tstatus\tfindings\tcritical\thigh\terrors\tattempted\tfallbacks")
    for mode, path in files:
        if not path.exists():
            print(f"{mode}\tmissing\t-\t-\t-\t-\t-\t-")
            continue

        data = json.loads(path.read_text())
        stats = data.get("statistics", {})
        meta = data.get("metadata", {})
        issues_by_severity = stats.get("issues_by_severity", {})
        errors = data.get("errors", [])
        status = "ok" if not errors else "parse-errors"
        attempted = meta.get("clang_attempted_count", 0)
        fallbacks = meta.get("clang_fallback_count", 0)

        print(
            f"{mode}\t{status}\t{stats.get('issues_found', 0)}\t"
            f"{issues_by_severity.get('critical', 0)}\t"
            f"{issues_by_severity.get('high', 0)}\t{len(errors)}\t"
            f"{attempted}\t{fallbacks}"
        )


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: audit_summary.py <artifacts-dir>", file=sys.stderr)
        return 2

    summarize(Path(sys.argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
