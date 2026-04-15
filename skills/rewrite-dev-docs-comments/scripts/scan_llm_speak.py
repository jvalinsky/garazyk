#!/usr/bin/env python3
"""
Scan docs and comments for likely "LLM-speak" and low-signal phrasing.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, List, Sequence


TEXT_SUFFIXES = {
    ".c",
    ".cc",
    ".cpp",
    ".h",
    ".hpp",
    ".m",
    ".mm",
    ".swift",
    ".py",
    ".sh",
    ".js",
    ".ts",
    ".md",
    ".txt",
    ".rst",
    ".yaml",
    ".yml",
    ".json",
    ".j",
}


@dataclass
class Finding:
    path: str
    line: int
    column: int
    category: str
    match: str
    message: str
    text: str


PATTERNS: Sequence[tuple[str, str, str]] = (
    (
        "marketing-hype",
        (
            r"\b(cutting[- ]edge|game[- ]chang(?:er|ing)|revolutionary|best[- ]in[- ]class|"
            r"world[- ]class|seamless(?:ly)?|next[- ]gen|state[- ]of[- ]the[- ]art|"
            r"transformative|innovative|enterprise[- ]grade|supercharge|unlock)\b"
        ),
        "Replace hype with concrete technical behavior.",
    ),
    (
        "filler",
        (
            r"\b(it is important to note that|please note that|in this context|"
            r"at the end of the day|in order to|it(?:'s| is) worth noting that|in summary|"
            r"in conclusion|overall[, ]+)\b"
        ),
        "Delete filler and state the point directly.",
    ),
    (
        "vague-quality",
        r"\b(robust|comprehensive|powerful|scalable|efficient|optimized|intuitive|user[- ]friendly)\b",
        "Add measurable detail (scope, limits, or outcomes).",
    ),
    (
        "timeline-anchor",
        r"\b(currently|now|new|latest|as of this writing|at present)\b",
        "Prefer timeless phrasing for long-lived technical docs.",
    ),
    (
        "assistant-voice",
        (
            r"\b(let'?s dive|delve into|we can see that|as an ai|i hope this helps|"
            r"in today'?s (fast-paced )?digital landscape|leverage|harness)\b"
        ),
        "Use neutral, peer-to-peer engineering tone.",
    ),
    (
        "softener",
        r"\b(simply|just|obviously|clearly|basically|easy(?:ly)?)\b",
        "Remove softeners and describe exact behavior.",
    ),
)

COMMENT_RESTATE_RE = re.compile(
    r"^\s*(//|#|/\*+|\*+)\s*(this|these|the)\s+"
    r"(function|method|class|loop|variable|line|property|file|module)\b",
    re.IGNORECASE,
)

REPEATED_WORD_RE = re.compile(r"\b([A-Za-z]{3,})\s+\1\b", re.IGNORECASE)

COMPILED_PATTERNS = [
    (category, re.compile(pattern, re.IGNORECASE), message)
    for category, pattern, message in PATTERNS
]


def iter_targets(raw_paths: Sequence[str]) -> Iterable[str]:
    for raw in raw_paths:
        if raw == "-":
            yield raw
            continue

        target = Path(raw)
        if target.is_file():
            yield str(target)
            continue

        if target.is_dir():
            for child in sorted(target.rglob("*")):
                if child.is_file() and child.suffix.lower() in TEXT_SUFFIXES:
                    yield str(child)
            continue

        print(f"[warn] Skipping missing path: {raw}", file=sys.stderr)


def read_text(path: str) -> str:
    if path == "-":
        return sys.stdin.read()

    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"[warn] Failed to read {path}: {exc}", file=sys.stderr)
        return ""


def scan_text(path: str, text: str) -> List[Finding]:
    findings: List[Finding] = []
    in_fenced_code = False
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.lstrip()
        if stripped.startswith("```"):
            in_fenced_code = not in_fenced_code
            continue

        if in_fenced_code:
            continue

        # Skip markdown table rows to avoid flagging deliberate pattern catalogs.
        if stripped.startswith("|"):
            continue

        for category, regex, message in COMPILED_PATTERNS:
            for match in regex.finditer(line):
                findings.append(
                    Finding(
                        path=path,
                        line=line_no,
                        column=match.start() + 1,
                        category=category,
                        match=match.group(0),
                        message=message,
                        text=line.strip(),
                    )
                )

        if COMMENT_RESTATE_RE.search(line):
            findings.append(
                Finding(
                    path=path,
                    line=line_no,
                    column=1,
                    category="obvious-comment",
                    match=line.strip(),
                    message="Comment likely restates code; keep comments for rationale/invariants.",
                    text=line.strip(),
                )
            )

        for match in REPEATED_WORD_RE.finditer(line):
            findings.append(
                Finding(
                    path=path,
                    line=line_no,
                    column=match.start() + 1,
                    category="word-repeat",
                    match=match.group(0),
                    message="Collapse repeated words.",
                    text=line.strip(),
                )
            )

    return findings


def print_text_report(findings: Sequence[Finding]) -> None:
    if not findings:
        print("No likely LLM-speak markers found.")
        return

    by_category: dict[str, int] = {}
    for finding in findings:
        by_category[finding.category] = by_category.get(finding.category, 0) + 1
        print(
            f"{finding.path}:{finding.line}:{finding.column}: "
            f"[{finding.category}] {finding.message}"
        )
        print(f"  {finding.text}")

    print("\nSummary:")
    for category in sorted(by_category):
        print(f"  {category}: {by_category[category]}")
    print(f"  total: {len(findings)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Scan docs/comments for likely low-signal LLM-style phrasing."
    )
    parser.add_argument(
        "paths",
        nargs="+",
        help="Files, directories, or '-' for stdin.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit findings as JSON.",
    )
    parser.add_argument(
        "--fail-on-findings",
        action="store_true",
        help="Exit non-zero when any finding is detected.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    all_findings: List[Finding] = []
    for path in iter_targets(args.paths):
        text = read_text(path)
        if not text:
            continue
        all_findings.extend(scan_text(path, text))

    if args.json:
        print(json.dumps([asdict(finding) for finding in all_findings], indent=2))
    else:
        print_text_report(all_findings)

    if args.fail_on_findings and all_findings:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
