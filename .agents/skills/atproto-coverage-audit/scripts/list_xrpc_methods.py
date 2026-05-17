#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys

PREFIX_MAP = {
    "ComAtproto": "com.atproto",
    "AppBsky": "app.bsky",
    "ChatBsky": "chat.bsky",
    "ToolsOzone": "tools.ozone",
    "ComWhtwndBlog": "com.whtwnd.blog",
    "ComShinolabsPinksea": "com.shinolabs.pinksea",
    "SocialGrain": "social.grain",
    "PlaceStream": "place.stream",
    "Statusphere": "statusphere",
    "Skylights": "skylights",
    "FyiFrontpage": "fyi.frontpage",
    "FyiUnravel": "fyi.unravel",
    "BlueLinkat": "blue.linkat",
    "LinkatBlue": "linkat.blue",
    "ShTangled": "sh.tangled",
}

CAMEL_RE = re.compile(r"[A-Z][a-z0-9]*|[A-Z]+(?![a-z])")
REGISTER_TYPED_RE = re.compile(r"\[\s*dispatcher\s+register([A-Za-z0-9]+):")
REGISTER_STRING_RE = re.compile(r"\[\s*dispatcher\s+registerMethod:\s*@\"([^\"]+)\"")
LEXICON_METHOD_TYPES_RE = re.compile(r'"([A-Za-z0-9_.]+)":\s*"(query|procedure|subscription)"')


def _split_camel(value: str):
    return CAMEL_RE.findall(value)


def _lower_camel(tokens):
    if not tokens:
        return ""
    head = tokens[0][:1].lower() + tokens[0][1:]
    return head + "".join(tokens[1:])


def _method_id_from_typed_symbol(symbol: str):
    for prefix, domain in sorted(PREFIX_MAP.items(), key=lambda item: -len(item[0])):
        if symbol.startswith(prefix):
            remainder = symbol[len(prefix):]
            tokens = _split_camel(remainder)
            if not tokens:
                return None
            namespace = tokens[0].lower()
            method = _lower_camel(tokens[1:])
            if not method:
                return None
            return f"{domain}.{namespace}.{method}"
    return None


def parse_registry(path):
    entries = []
    with open(path, "r", encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, start=1):
            for string_match in REGISTER_STRING_RE.finditer(line):
                method_id = string_match.group(1)
                entries.append({
                    "method_id": method_id,
                    "symbol": "registerMethod",
                    "kind": "string",
                    "location": f"{path}:{lineno}",
                })

            typed_match = REGISTER_TYPED_RE.search(line)
            if not typed_match:
                continue

            symbol = typed_match.group(1)
            if symbol == "Method":
                continue

            method_id = _method_id_from_typed_symbol(symbol) or "unknown"
            entries.append({
                "method_id": method_id,
                "symbol": symbol,
                "kind": "typed",
                "location": f"{path}:{lineno}",
            })

    return entries


def parse_generated_lexicons(path):
    entries = []
    with open(path, "r", encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, start=1):
            match = LEXICON_METHOD_TYPES_RE.search(line)
            if not match:
                continue
            entries.append({
                "method_id": match.group(1),
                "symbol": "LEXICON_METHOD_TYPES",
                "kind": match.group(2),
                "location": f"{path}:{lineno}",
            })
    return entries


def main():
    parser = argparse.ArgumentParser(description="List XRPC methods registered in the code.")
    parser.add_argument("repo_root", nargs="?", default=".", help="Repository root path")
    parser.add_argument("--output", help="Write TSV output to a file")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    args = parser.parse_args()

    entries = []
    generated_lexicons = os.path.join(args.repo_root, "packages", "gruszka", "lexicons.ts")
    if os.path.isfile(generated_lexicons):
        entries.extend(parse_generated_lexicons(generated_lexicons))
    else:
        sources_root = os.path.join(args.repo_root, "Garazyk", "Sources")
        if not os.path.isdir(sources_root):
            # Fallback to current directory if Garazyk/Sources doesn't exist.
            sources_root = args.repo_root

        for root, _, files in os.walk(sources_root):
            for filename in files:
                if not (filename.endswith(".m") or filename.endswith(".mm")):
                    continue
                path = os.path.join(root, filename)
                entries.extend(parse_registry(path))

    # Deduplicate entries by method_id
    seen = {}
    unique_entries = []
    for entry in entries:
        mid = entry["method_id"]
        if mid == "unknown":
            unique_entries.append(entry)
            continue
        if mid not in seen:
            seen[mid] = entry
            unique_entries.append(entry)
    
    entries = unique_entries

    if args.json:
        output = json.dumps(entries, indent=2, sort_keys=True)
    else:
        lines = ["method_id\tsymbol\tkind\tlocation"]
        for entry in entries:
            lines.append(
                f"{entry['method_id']}\t{entry['symbol']}\t{entry['kind']}\t{entry['location']}"
            )
        output = "\n".join(lines)

    if args.output and not args.json:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(output + "\n")
    else:
        print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
