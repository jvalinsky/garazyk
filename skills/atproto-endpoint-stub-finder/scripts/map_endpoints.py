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


def _split_camel(value: str):
    return CAMEL_RE.findall(value)


def _lower_camel(tokens):
    if not tokens:
        return ""
    head = tokens[0][:1].lower() + tokens[0][1:]
    return head + "".join(tokens[1:])


def _method_id(symbol: str):
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
                entries.append({
                    "method_id": string_match.group(1),
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

            method_id = _method_id(symbol) or "unknown"
            entries.append({
                "method_id": method_id,
                "symbol": symbol,
                "kind": "typed",
                "location": f"{path}:{lineno}",
            })
    return entries


def main():
    parser = argparse.ArgumentParser(description="Map XRPC registry entries to method IDs.")
    parser.add_argument("repo_root", nargs="?", default=".", help="Repository root path")
    parser.add_argument("--output", help="Write TSV output to a file")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    args = parser.parse_args()

    registry_path = os.path.join(
        args.repo_root, "Garazyk", "Sources", "Network", "XrpcMethodRegistry.m"
    )

    if not os.path.exists(registry_path):
        print(f"Registry not found: {registry_path}", file=sys.stderr)
        return 1

    entries = parse_registry(registry_path)

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
