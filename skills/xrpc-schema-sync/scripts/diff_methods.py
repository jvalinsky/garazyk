#!/usr/bin/env python3
import argparse
import json
import sys


def load_ids(path):
    ids = set()
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("method_id"):
                continue
            ids.add(line.split("\t", 1)[0])
    return ids


def main():
    parser = argparse.ArgumentParser(description="Diff method IDs between code and lexicons.")
    parser.add_argument("--methods", required=True, help="TSV from list_xrpc_methods.py")
    parser.add_argument("--lexicons", required=True, help="TSV from parse_lexicons.py")
    parser.add_argument("--ignore-file", help="File with method IDs to ignore")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    args = parser.parse_args()

    try:
        method_ids = load_ids(args.methods)
        lexicon_ids = load_ids(args.lexicons)
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    ignore_ids = set()
    if args.ignore_file:
        with open(args.ignore_file, "r", encoding="utf-8") as handle:
            for line in handle:
                value = line.strip()
                if value and not value.startswith("#"):
                    ignore_ids.add(value)

    method_ids -= ignore_ids
    lexicon_ids -= ignore_ids

    missing_in_code = sorted(lexicon_ids - method_ids)
    missing_in_lexicons = sorted(method_ids - lexicon_ids)

    if args.json:
        payload = {
            "missing_in_code": missing_in_code,
            "missing_in_lexicons": missing_in_lexicons,
            "summary": {
                "missing_in_code": len(missing_in_code),
                "missing_in_lexicons": len(missing_in_lexicons),
            },
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    print("== Missing in code ==")
    for item in missing_in_code:
        print(item)

    print("\n== Missing in lexicons ==")
    for item in missing_in_lexicons:
        print(item)

    print(f"\nSummary: {len(missing_in_code)} missing in code, {len(missing_in_lexicons)} missing in lexicons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
