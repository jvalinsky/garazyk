#!/usr/bin/env python3
"""Repo-wide documentation registry, indexing, graphing, and validation.

This tool canonicalizes documentation workflows around docs/ while still
tracking markdown files across the repository.

Commands:
  sync      Generate registry, graph, orphan report, and hub/backlink pages.
  validate  Validate internal links/orphans/external links.

Validation modes:
  --internal-strict  Fail on unresolved internal links.
  --orphans          Fail on docs with no inbound links unless allowlisted.
  --external-report  Check external links and write a non-blocking report.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set, Tuple


ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
METADATA_DIR = DOCS / "metadata"
REPORTS_DIR = DOCS / "reports" / "docs"
INDEX_DIR = DOCS / "repo-index"

REGISTRY_PATH = METADATA_DIR / "doc-registry.json"
REGISTRY_SCHEMA_PATH = METADATA_DIR / "doc-registry.schema.json"
GRAPH_PATH = METADATA_DIR / "doc-link-graph.json"
ORPHAN_JSON_PATH = METADATA_DIR / "doc-orphans.json"
MIGRATION_MAP_PATH = METADATA_DIR / "doc-migration-map.json"
EXTERNAL_REPORT_PATH = METADATA_DIR / "external-links-report.json"
ORPHAN_ALLOWLIST_PATH = METADATA_DIR / "orphan-allowlist.txt"

CANONICAL_DOC_RE = re.compile(r"^docs/(0[1-9]|1[0-2])-[^/]+/")
MD_LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
URL_SCHEME_RE = re.compile(r"^(?:https?|mailto|tel|ftp|data):", re.IGNORECASE)

ROOT_ENTRYPOINTS: Set[str] = {
    "README.md",
    "BUILD.md",
    "CONTRIBUTING.md",
    "DOCUMENTATION.md",
    "AGENTS.md",
    "AGENTS_QUICKREF.md",
    "ADMINUI_START_HERE.md",
    "ADMINUI_QUICKSTART.md",
    "ADMINUI_PROJECT_COMPLETE.md",
    "ADMINUI_DEPLOYMENT_GUIDE.md",
}

TOP_LEVEL_MARKDOWN_DIRS: Tuple[str, ...] = (
    "docs",
    "Garazyk",
    "examples",
    "tooling",
    "scripts",
    "skills",
)

SCAN_DIR_SKIP_NAMES = {
    ".git",
    "node_modules",
    ".vitepress",
    "dist",
    "build",
    "build-linux",
    ".cache",
    ".cadmus",
    ".ruff_cache",
    ".claude",
    ".deciduous",
    ".letta",
    "vendor",
    "blobs",
    "cache",
    "did_cache",
    "keys",
    "sequencer",
}

CANONICAL_DEFAULT = "docs/index.md"


@dataclass
class DocRecord:
    path: str
    classification: str
    canonical_target: str
    owner: str
    status: str


@dataclass
class LinkIssue:
    source: str
    line: int
    href: str
    message: str


@dataclass
class LinkEdge:
    source: str
    target: str
    href: str
    line: int


def posix_rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def ensure_dirs() -> None:
    for directory in (METADATA_DIR, REPORTS_DIR, INDEX_DIR):
        directory.mkdir(parents=True, exist_ok=True)


def discover_markdown_files() -> List[Path]:
    files: List[Path] = []

    for rel_dir in TOP_LEVEL_MARKDOWN_DIRS:
        directory = ROOT / rel_dir
        if not directory.exists():
            continue

        for root_dir, dirnames, filenames in os.walk(directory):
            dirnames[:] = [
                d
                for d in dirnames
                if d not in SCAN_DIR_SKIP_NAMES and not d.startswith(".")
            ]
            root_path = Path(root_dir)
            for filename in filenames:
                if not filename.endswith(".md"):
                    continue
                files.append(root_path / filename)

    for entry in ROOT.iterdir():
        if entry.is_file() and entry.suffix == ".md":
            files.append(entry)

    # Unique + stable
    unique = sorted({f.resolve() for f in files}, key=lambda p: posix_rel(p))
    return unique


def classify_doc(path: str) -> str:
    if CANONICAL_DOC_RE.match(path):
        return "canonical"
    if path in {"docs/index.md", "docs/README.md", "docs/SUMMARY.md"}:
        return "canonical"

    if path.startswith("docs/archive/"):
        return "archive"
    if path.startswith("docs/scratchpad/"):
        return "archive"
    if path.startswith("docs/plans/archive/"):
        return "archive"
    if path.startswith("docs/plan/"):
        return "archive"

    if path in ROOT_ENTRYPOINTS:
        return "entrypoint"
    if path.startswith("ADMINUI_") and path.endswith(".md"):
        return "entrypoint"

    return "internal-reference"


def infer_owner(path: str) -> str:
    if path.startswith("docs/"):
        if path.startswith("docs/security/"):
            return "security"
        if path.startswith("docs/tests/"):
            return "quality"
        if path.startswith("docs/plans/"):
            return "planning"
        return "docs"
    if path.startswith("Garazyk/Sources/Admin/"):
        return "admin"
    if path.startswith("Garazyk/"):
        return "core"
    if path.startswith("tooling/"):
        return "tooling"
    if path.startswith("skills/"):
        return "skills"
    if path.startswith("scripts/"):
        return "tooling"
    if path.startswith("examples/"):
        return "docs"
    return "docs"


def infer_status(classification: str) -> str:
    if classification == "canonical":
        return "active"
    if classification == "archive":
        return "archived"
    if classification == "entrypoint":
        return "active"
    return "reference"


def infer_canonical_target(path: str, classification: str) -> str:
    if classification == "canonical":
        return path

    explicit: Dict[str, str] = {
        "README.md": "docs/index.md",
        "BUILD.md": "docs/01-getting-started/setup.md",
        "CONTRIBUTING.md": "docs/index.md",
        "DOCUMENTATION.md": "docs/11-reference/documentation-map.md",
        "AGENTS.md": "docs/11-reference/documentation-map.md",
        "AGENTS_QUICKREF.md": "docs/11-reference/documentation-map.md",
        "ADMINUI_START_HERE.md": "docs/11-reference/admin-ui-documentation.md",
        "ADMINUI_QUICKSTART.md": "docs/11-reference/admin-ui-documentation.md",
        "ADMINUI_PROJECT_COMPLETE.md": "docs/11-reference/admin-ui-documentation.md",
        "ADMINUI_DEPLOYMENT_GUIDE.md": "docs/11-reference/admin-ui-documentation.md",
    }
    if path in explicit:
        return explicit[path]

    if path.startswith("docs/security/"):
        return "docs/11-reference/security-audit-guide.md"
    if path.startswith("docs/tests/"):
        return "docs/11-reference/testing-map.md"
    if path.startswith("docs/oauth2/"):
        return "docs/06-authentication/oauth2-dpop.md"
    if path.startswith("docs/architecture/"):
        return "docs/01-getting-started/architecture-overview.md"
    if path.startswith("docs/guides/"):
        return "docs/index.md"
    if path.startswith("docs/plans/") or path.startswith("docs/plan/"):
        return "docs/archive/planning/README.md"
    if path.startswith("docs/scratchpad/"):
        return "docs/archive/planning/README.md"

    if path.startswith("Garazyk/Sources/Admin/"):
        return "docs/11-reference/admin-ui-documentation.md"
    if path.startswith("Garazyk/"):
        return "docs/11-reference/source-adjacent-documentation.md"
    if path.startswith("skills/"):
        return "docs/11-reference/tooling-and-skills-documentation.md"
    if path.startswith("tooling/"):
        return "docs/11-reference/tooling-and-skills-documentation.md"
    if path.startswith("scripts/"):
        return "docs/11-reference/tooling-and-skills-documentation.md"
    if path.startswith("examples/"):
        return "docs/10-tutorials/index.md"

    return CANONICAL_DEFAULT


def build_registry(files: List[Path]) -> List[DocRecord]:
    records: List[DocRecord] = []
    for file_path in files:
        rel = posix_rel(file_path)
        classification = classify_doc(rel)
        records.append(
            DocRecord(
                path=rel,
                classification=classification,
                canonical_target=infer_canonical_target(rel, classification),
                owner=infer_owner(rel),
                status=infer_status(classification),
            )
        )
    records.sort(key=lambda r: r.path)
    return records


def write_registry_schema() -> None:
    schema = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "Garazyk Doc Registry",
        "type": "array",
        "items": {
            "type": "object",
            "required": [
                "path",
                "classification",
                "canonical_target",
                "owner",
                "status",
            ],
            "properties": {
                "path": {"type": "string"},
                "classification": {
                    "type": "string",
                    "enum": [
                        "canonical",
                        "archive",
                        "entrypoint",
                        "internal-reference",
                    ],
                },
                "canonical_target": {"type": "string"},
                "owner": {"type": "string"},
                "status": {"type": "string"},
            },
            "additionalProperties": False,
        },
    }
    REGISTRY_SCHEMA_PATH.write_text(json.dumps(schema, indent=2) + "\n", encoding="utf-8")


def clean_href(href: str) -> str:
    value = href.strip()
    if value.startswith("<") and value.endswith(">"):
        value = value[1:-1].strip()
    return value


def is_external_href(href: str) -> bool:
    return bool(URL_SCHEME_RE.match(href))


def remove_fragment_and_query(href: str) -> str:
    value = href.split("#", 1)[0]
    value = value.split("?", 1)[0]
    return value


def resolve_internal_target(source: Path, href: str) -> Optional[Path]:
    href = clean_href(href)
    if not href or href.startswith("#"):
        return None

    link = remove_fragment_and_query(href)
    if not link:
        return None

    candidates: List[Path] = []
    if link.startswith("/"):
        link_no_lead = link.lstrip("/")
        candidates.append(ROOT / link_no_lead)
        candidates.append(DOCS / link_no_lead)
    else:
        base = source.parent
        candidates.append((base / link).resolve())

    expanded: List[Path] = []
    for candidate in candidates:
        expanded.append(candidate)
        if candidate.suffix == "":
            expanded.append(candidate.with_suffix(".md"))
            expanded.append(candidate / "README.md")
            expanded.append(candidate / "index.md")

    for candidate in expanded:
        if candidate.exists():
            return candidate.resolve()
    return None


def iter_markdown_links(content: str) -> Iterable[Tuple[int, str, str]]:
    for line_no, line in enumerate(content.splitlines(), start=1):
        for match in MD_LINK_RE.finditer(line):
            text = match.group(1)
            href = match.group(2)
            yield line_no, text, href


def analyze_links(files: List[Path], records: List[DocRecord]) -> Tuple[List[LinkEdge], List[LinkIssue], Dict[str, List[str]], Dict[str, int], Dict[str, int]]:
    record_paths = {r.path for r in records}
    edges: List[LinkEdge] = []
    issues: List[LinkIssue] = []
    outgoing: Dict[str, List[str]] = defaultdict(list)
    internal_stats = {"internal": 0, "external": 0, "anchor": 0, "missing": 0}
    external_counts: Dict[str, int] = defaultdict(int)

    path_to_file = {posix_rel(p): p for p in files}

    for rel, source in sorted(path_to_file.items()):
        content = source.read_text(encoding="utf-8", errors="ignore")
        for line_no, _text, raw_href in iter_markdown_links(content):
            href = clean_href(raw_href)
            if not href:
                continue
            if href.startswith("#"):
                internal_stats["anchor"] += 1
                continue
            if is_external_href(href):
                internal_stats["external"] += 1
                external_counts[href] += 1
                continue

            internal_stats["internal"] += 1
            resolved = resolve_internal_target(source, href)
            if resolved is None:
                internal_stats["missing"] += 1
                issues.append(
                    LinkIssue(
                        source=rel,
                        line=line_no,
                        href=href,
                        message="Unresolved internal link",
                    )
                )
                continue

            target_rel = posix_rel(resolved)
            if target_rel in record_paths:
                edges.append(LinkEdge(source=rel, target=target_rel, href=href, line=line_no))
                outgoing[rel].append(target_rel)
            else:
                # Non-markdown targets still need to exist; unresolved already handled above.
                outgoing[rel].append(target_rel)

    return edges, issues, outgoing, internal_stats, dict(sorted(external_counts.items()))


def load_orphan_allowlist() -> Set[str]:
    if not ORPHAN_ALLOWLIST_PATH.exists():
        return set()
    values = {
        line.strip()
        for line in ORPHAN_ALLOWLIST_PATH.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    }
    return values


def compute_orphans(records: List[DocRecord], edges: List[LinkEdge]) -> Tuple[List[str], Dict[str, int]]:
    inbound: Dict[str, int] = {r.path: 0 for r in records}
    for edge in edges:
        if edge.target in inbound:
            inbound[edge.target] += 1

    allowlist = load_orphan_allowlist()
    orphans: List[str] = []
    for record in records:
        if inbound[record.path] > 0:
            continue
        if record.path in allowlist:
            continue
        orphans.append(record.path)

    return sorted(orphans), inbound


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def relative_link(from_path: Path, to_rel: str) -> str:
    to_path = ROOT / to_rel
    rel = os.path.relpath(to_path, start=from_path.parent)
    return rel.replace("\\", "/")


def write_markdown(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def build_collection(records: List[DocRecord], prefix: str) -> List[DocRecord]:
    return [r for r in records if r.path.startswith(prefix)]


def make_registry_table(path: Path, records: List[DocRecord]) -> str:
    lines = ["| Path | Classification | Canonical Target | Owner | Status |", "| --- | --- | --- | --- | --- |"]
    for record in records:
        link = relative_link(path, record.path)
        target_link = relative_link(path, record.canonical_target)
        lines.append(
            f"| [{record.path}]({link}) | `{record.classification}` | [{record.canonical_target}]({target_link}) | `{record.owner}` | `{record.status}` |"
        )
    return "\n".join(lines)


def generate_index_pages(records: List[DocRecord], inbound: Dict[str, int], edges: List[LinkEdge]) -> None:
    index_pages = {
        "root-entrypoints.md": [r for r in records if r.classification == "entrypoint"],
        "source-adjacent.md": build_collection(records, "Garazyk/"),
        "examples.md": build_collection(records, "examples/"),
        "tooling.md": build_collection(records, "tooling/"),
        "scripts.md": build_collection(records, "scripts/"),
        "skills.md": build_collection(records, "skills/"),
        "docs-noncanonical.md": [
            r
            for r in records
            if r.path.startswith("docs/") and r.classification != "canonical"
        ],
        "all-documents.md": records,
    }

    for filename, page_records in index_pages.items():
        page = INDEX_DIR / filename
        title = filename.replace(".md", "").replace("-", " ").title()
        front_matter = f"---\ntitle: {title}\n---\n"
        intro = [
            front_matter,
            f"# {title}",
            "",
            "Auto-generated documentation index for repository discoverability.",
            "",
            f"Total documents in this view: **{len(page_records)}**",
            "",
        ]
        table = make_registry_table(page, page_records)
        write_markdown(page, "\n".join(intro) + "\n" + table)

    backlinks_lines = [
        "---",
        "title: Backlinks",
        "---",
        "# Backlinks",
        "",
        "Auto-generated inbound link inventory for markdown discoverability.",
        "",
    ]

    incoming: Dict[str, List[str]] = defaultdict(list)
    for edge in edges:
        incoming[edge.target].append(edge.source)

    for record in records:
        backlinks_lines.append(f"## `{record.path}`")
        backlinks_lines.append("")
        backlinks_lines.append(f"Inbound links: **{inbound.get(record.path, 0)}**")
        backlinks_lines.append("")
        sources = sorted(set(incoming.get(record.path, [])))
        if not sources:
            backlinks_lines.append("- _No inbound links detected._")
        else:
            for source in sources:
                backlinks_lines.append(
                    f"- [{source}]({relative_link(INDEX_DIR / 'backlinks.md', source)})"
                )
        backlinks_lines.append("")

    write_markdown(INDEX_DIR / "backlinks.md", "\n".join(backlinks_lines))

    top_index_lines = [
        "---",
        "title: Repository Documentation Index",
        "---",
        "# Repository Documentation Index",
        "",
        "Section-level indexes for non-canonical and cross-repository markdown collections.",
        "",
        "## Sections",
        "",
        "- [All Documents](all-documents.md)",
        "- [Root Entrypoints](root-entrypoints.md)",
        "- [Docs Non-Canonical](docs-noncanonical.md)",
        "- [Source-Adjacent](source-adjacent.md)",
        "- [Examples](examples.md)",
        "- [Tooling](tooling.md)",
        "- [Scripts](scripts.md)",
        "- [Skills](skills.md)",
        "- [Backlinks](backlinks.md)",
        "",
    ]
    write_markdown(INDEX_DIR / "index.md", "\n".join(top_index_lines))


def write_orphan_allowlist_if_missing() -> None:
    if ORPHAN_ALLOWLIST_PATH.exists():
        return
    ORPHAN_ALLOWLIST_PATH.write_text(
        "# Paths allowed to have zero inbound markdown links.\n"
        "# Keep this list short.\n",
        encoding="utf-8",
    )


def write_graph_outputs(records: List[DocRecord], edges: List[LinkEdge], issues: List[LinkIssue], inbound: Dict[str, int], stats: Dict[str, int], external_counts: Dict[str, int]) -> None:
    node_map = {
        r.path: {
            "id": r.path,
            "classification": r.classification,
            "owner": r.owner,
            "status": r.status,
            "canonical_target": r.canonical_target,
        }
        for r in records
    }

    payload = {
        "generated_at": int(time.time()),
        "summary": {
            "nodes": len(records),
            "edges": len(edges),
            "internal_links": stats["internal"],
            "external_links": stats["external"],
            "anchor_links": stats["anchor"],
            "missing_internal_links": stats["missing"],
        },
        "nodes": list(node_map.values()),
        "edges": [
            {
                "source": edge.source,
                "target": edge.target,
                "href": edge.href,
                "line": edge.line,
            }
            for edge in edges
        ],
        "issues": [
            {
                "source": issue.source,
                "line": issue.line,
                "href": issue.href,
                "message": issue.message,
            }
            for issue in issues
        ],
        "inbound": inbound,
        "external_link_counts": external_counts,
    }

    write_json(GRAPH_PATH, payload)

    orphan_payload = {
        "generated_at": int(time.time()),
        "orphans": [path for path, count in inbound.items() if count == 0],
        "inbound": inbound,
    }
    write_json(ORPHAN_JSON_PATH, orphan_payload)

    report_md = [
        "---",
        "title: Documentation Link Graph Report",
        "---",
        "# Documentation Link Graph Report",
        "",
        f"Generated nodes: **{len(records)}**",
        f"Generated edges: **{len(edges)}**",
        f"Missing internal links: **{stats['missing']}**",
        "",
        "## Orphans",
        "",
    ]
    orphans = [path for path, count in inbound.items() if count == 0]
    if not orphans:
        report_md.append("No orphan documents detected.")
    else:
        for orphan in sorted(orphans):
            report_md.append(f"- `{orphan}`")

    report_md.extend(["", "## Missing Internal Links", ""])
    if not issues:
        report_md.append("No unresolved internal markdown links detected.")
    else:
        for issue in issues[:500]:
            report_md.append(f"- `{issue.source}:{issue.line}` -> `{issue.href}`")

    write_markdown(REPORTS_DIR / "link-graph-report.md", "\n".join(report_md))


def default_migration_map_if_missing() -> None:
    if MIGRATION_MAP_PATH.exists():
        return
    payload = {
        "generated_at": int(time.time()),
        "moves": [],
        "notes": [
            "Populate this map with old_path/new_path pairs whenever markdown files are moved.",
            "Pointer stubs should be kept at old locations until links are fully migrated.",
        ],
    }
    write_json(MIGRATION_MAP_PATH, payload)


def run_sync() -> int:
    ensure_dirs()
    write_orphan_allowlist_if_missing()
    write_registry_schema()
    default_migration_map_if_missing()

    # Pass 1: bootstrap generated index/backlink pages.
    files = discover_markdown_files()
    records = build_registry(files)
    edges, issues, _outgoing, stats, external_counts = analyze_links(files, records)
    _orphans, inbound = compute_orphans(records, edges)
    generate_index_pages(records, inbound, edges)

    # Pass 2: re-scan so generated pages are included in registry + graph.
    files = discover_markdown_files()
    records = build_registry(files)
    edges, issues, _outgoing, stats, external_counts = analyze_links(files, records)
    _orphans, inbound = compute_orphans(records, edges)
    generate_index_pages(records, inbound, edges)

    write_json(
        REGISTRY_PATH,
        [
            {
                "path": r.path,
                "classification": r.classification,
                "canonical_target": r.canonical_target,
                "owner": r.owner,
                "status": r.status,
            }
            for r in records
        ],
    )

    write_graph_outputs(records, edges, issues, inbound, stats, external_counts)

    print(f"[repo-docs] sync complete: {len(records)} docs, {len(edges)} graph edges")
    print(f"[repo-docs] registry: {REGISTRY_PATH.relative_to(ROOT)}")
    print(f"[repo-docs] index hub: {INDEX_DIR.relative_to(ROOT)}/index.md")
    return 0


def load_registry() -> List[DocRecord]:
    if not REGISTRY_PATH.exists():
        print("[repo-docs] registry missing; run sync first", file=sys.stderr)
        sys.exit(2)
    raw = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    records = [
        DocRecord(
            path=item["path"],
            classification=item["classification"],
            canonical_target=item["canonical_target"],
            owner=item["owner"],
            status=item["status"],
        )
        for item in raw
    ]
    return records


def validate_internal_strict(records: List[DocRecord]) -> Tuple[List[LinkIssue], List[LinkEdge], Dict[str, int], Dict[str, int]]:
    files = [ROOT / r.path for r in records if (ROOT / r.path).exists()]
    edges, issues, _outgoing, stats, external_counts = analyze_links(files, records)
    return issues, edges, stats, external_counts


def check_external_links(records: List[DocRecord]) -> Dict[str, object]:
    files = [ROOT / r.path for r in records if (ROOT / r.path).exists()]
    seen: Set[str] = set()
    results: Dict[str, Dict[str, object]] = {}

    for file_path in files:
        content = file_path.read_text(encoding="utf-8", errors="ignore")
        for _line, _text, href in iter_markdown_links(content):
            link = clean_href(href)
            if not link or not is_external_href(link):
                continue
            seen.add(link)

    for url in sorted(seen):
        status = "ok"
        code: Optional[int] = None
        message = "OK"
        try:
            request = urllib.request.Request(
                url,
                method="HEAD",
                headers={"User-Agent": "garazyk-docs-validator/1.0"},
            )
            with urllib.request.urlopen(request, timeout=8) as response:
                code = response.getcode()
                if code and code >= 400:
                    status = "error"
                    message = f"HTTP {code}"
        except urllib.error.HTTPError as exc:
            code = exc.code
            status = "error"
            message = f"HTTP {exc.code}"
        except Exception as exc:  # pragma: no cover
            status = "warning"
            message = str(exc)

        results[url] = {"status": status, "code": code, "message": message}

    payload = {
        "generated_at": int(time.time()),
        "checked": len(results),
        "results": results,
    }
    write_json(EXTERNAL_REPORT_PATH, payload)
    return payload


def validate(args: argparse.Namespace) -> int:
    ensure_dirs()
    records = load_registry()

    exit_code = 0

    issues: List[LinkIssue] = []
    edges: List[LinkEdge] = []
    stats: Dict[str, int] = {}
    external_counts: Dict[str, int] = {}

    if args.internal_strict or args.orphans:
        issues, edges, stats, external_counts = validate_internal_strict(records)

    if args.internal_strict:
        if issues:
            print(f"[repo-docs] internal strict failed: {len(issues)} unresolved links")
            for issue in issues[:200]:
                print(f"  - {issue.source}:{issue.line} -> {issue.href} ({issue.message})")
            exit_code = 1
        else:
            print("[repo-docs] internal strict passed")

    if args.orphans:
        orphans, inbound = compute_orphans(records, edges)
        write_graph_outputs(records, edges, issues, inbound, stats, external_counts)
        if orphans:
            print(f"[repo-docs] orphan check failed: {len(orphans)} orphan docs")
            for orphan in orphans[:200]:
                print(f"  - {orphan}")
            exit_code = 1
        else:
            print("[repo-docs] orphan check passed")

    if args.external_report:
        report = check_external_links(records)
        bad = [
            url
            for url, info in report["results"].items()
            if info["status"] in {"error", "warning"}
        ]
        print(
            f"[repo-docs] external report complete: checked={report['checked']} issues={len(bad)}"
        )
        # Non-blocking by design.

    return exit_code


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Repository documentation utility")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("sync", help="Generate registry/indexes/graph/backlinks")

    enrich_parser = subparsers.add_parser(
        "enrich-related",
        help="Add standardized Related sections to canonical docs that lack one",
    )
    enrich_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report files that would change without writing",
    )

    validate_parser = subparsers.add_parser("validate", help="Validate markdown docs")
    validate_parser.add_argument(
        "--internal-strict",
        action="store_true",
        help="Fail on unresolved internal markdown links",
    )
    validate_parser.add_argument(
        "--external-report",
        action="store_true",
        help="Generate non-blocking external link report",
    )
    validate_parser.add_argument(
        "--orphans",
        action="store_true",
        help="Fail on orphan docs unless allowlisted",
    )

    return parser.parse_args()


def append_related_sections(dry_run: bool = False) -> int:
    files = discover_markdown_files()
    records = build_registry(files)
    changed: List[str] = []

    for record in records:
        if record.classification != "canonical":
            continue

        path = ROOT / record.path
        content = path.read_text(encoding="utf-8", errors="ignore")
        if re.search(r"^##\\s+Related\\s*$", content, flags=re.MULTILINE):
            continue

        docs_map = relative_link(path, "docs/11-reference/documentation-map.md")
        contributor = relative_link(path, "docs/index.md")
        repo_index = relative_link(path, "docs/repo-index/index.md")
        related = (
            "\\n\\n## Related\\n\\n"
            f"- [Documentation Map]({docs_map})\\n"
            f"- [Contributor Guide]({contributor})\\n"
            f"- [Repository Documentation Index]({repo_index})\\n"
        )

        changed.append(record.path)
        if not dry_run:
            path.write_text(content.rstrip() + related + "\\n", encoding="utf-8")

    mode = "would update" if dry_run else "updated"
    print(f"[repo-docs] {mode} {len(changed)} canonical docs with missing Related sections")
    for rel in changed[:200]:
        print(f"  - {rel}")
    return 0


def main() -> int:
    args = parse_args()
    if args.command == "sync":
        return run_sync()
    if args.command == "enrich-related":
        return append_related_sections(dry_run=args.dry_run)
    if args.command == "validate":
        if not (args.internal_strict or args.external_report or args.orphans):
            print(
                "[repo-docs] choose at least one validation mode: "
                "--internal-strict, --external-report, --orphans",
                file=sys.stderr,
            )
            return 2
        return validate(args)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
