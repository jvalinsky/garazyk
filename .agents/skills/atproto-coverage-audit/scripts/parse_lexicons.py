#!/usr/bin/env python3
import argparse
import json
import os
import sys

XRPC_TYPES = {"query", "procedure", "subscription"}


def method_id_from_path(base, path):
    rel = os.path.relpath(path, base)
    rel_no_ext = os.path.splitext(rel)[0]
    parts = rel_no_ext.split(os.sep)
    return ".".join(parts)


def parse_lexicon(path):
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    lex_type = None
    defs = data.get("defs", {})
    main_def = defs.get("main", {})
    if isinstance(main_def, dict):
        lex_type = main_def.get("type")
    lex_id = data.get("id")
    return lex_type, lex_id


def main():
    parser = argparse.ArgumentParser(description="Parse lexicon JSON to list method IDs.")
    parser.add_argument("repo_root", nargs="?", default=".", help="Repository root path")
    parser.add_argument("--lexicon-root", help="Override lexicon root path")
    parser.add_argument("--output", help="Write TSV output to a file")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    args = parser.parse_args()

    if args.lexicon_root:
        lexicon_root = args.lexicon_root
    else:
        current_root = os.path.join(args.repo_root, "lexicons")
        legacy_root = os.path.join(args.repo_root, "Garazyk", "Resources", "lexicons")
        lexicon_root = current_root if os.path.isdir(current_root) else legacy_root

    if not os.path.isdir(lexicon_root):
        print(f"Lexicon root not found: {lexicon_root}", file=sys.stderr)
        return 1

    entries = []
    for root, _, files in os.walk(lexicon_root):
        for filename in files:
            if not filename.endswith(".json"):
                continue
            path = os.path.join(root, filename)
            try:
                lex_type, lex_id = parse_lexicon(path)
            except json.JSONDecodeError:
                continue
            if lex_type not in XRPC_TYPES:
                continue
            method_id = lex_id or method_id_from_path(lexicon_root, path)
            entries.append((method_id, lex_type, path))

    entries.sort(key=lambda item: item[0])
    if args.json:
        payload = [
            {"method_id": method_id, "type": lex_type, "location": path}
            for method_id, lex_type, path in entries
        ]
        output = json.dumps(payload, indent=2, sort_keys=True)
    else:
        lines = ["method_id\ttype\tlocation"]
        for method_id, lex_type, path in entries:
            lines.append(f"{method_id}\t{lex_type}\t{path}")
        output = "\n".join(lines)

    if args.output and not args.json:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(output + "\n")
    else:
        print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
