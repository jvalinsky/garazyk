#!/usr/bin/env python3
"""
Add SPDX license headers to Garazyk source files.

For files with existing @copyright doc headers, adds SPDX lines above the doc header.
For files without any copyright header, adds SPDX lines at the very top.

Skips files that already have SPDX-License-Identifier lines.
"""

import os
import sys
import re

SPDX_COPYRIGHT = "// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky"
SPDX_LICENSE = "// SPDX-License-Identifier: Unlicense OR CC0-1.0"
SPDX_BLOCK = SPDX_COPYRIGHT + "\n" + SPDX_LICENSE + "\n"

# For the 4 files that were originally "Jack Myers" (2024)
SPDX_COPYRIGHT_2024 = "// SPDX-FileCopyrightText: 2024-2026 Jack Valinsky"
SPDX_BLOCK_2024 = SPDX_COPYRIGHT_2024 + "\n" + SPDX_LICENSE + "\n"

# Files that should use 2024 copyright (the former "Jack Myers" files)
FILES_2024 = {
    "Garazyk/Sources/Auth/CryptoUtils.m",
    "Garazyk/Sources/Auth/JWT.m",
    "Garazyk/Sources/Auth/Session.m",
    "Garazyk/Sources/Network/HttpServer.m",
}

# MSTWalker attribution
MSTWALKER_ATTRIBUTION = "// Based on https://github.com/bluesky-social/atproto (MIT OR Apache-2.0)\n"

def has_spdx(content):
    return "SPDX-License-Identifier" in content

def starts_with_doc_header(content):
    """Check if file starts with a /*! doc header"""
    return content.lstrip().startswith("/*!")

def starts_with_copyright_comment(content):
    """Check if file starts with /* ... Copyright ... */ style comment"""
    stripped = content.lstrip()
    return stripped.startswith("/*") and "Copyright" in content[:500]

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    if has_spdx(content):
        return "skip-existing"

    rel_path = os.path.relpath(filepath, "/Users/jack/Software/garazyk")
    is_2024 = rel_path in FILES_2024
    spdx_block = SPDX_BLOCK_2024 if is_2024 else SPDX_BLOCK

    # Check for MSTWalker files
    is_mstwalker = "MSTWalker" in filepath

    if starts_with_doc_header(content):
        # File starts with /*! ... @copyright ... */ doc header
        # Add SPDX lines BEFORE the doc header
        extra = ""
        if is_mstwalker:
            extra = MSTWALKER_ATTRIBUTION
        new_content = spdx_block + extra + content
    elif content.startswith("//") or content.startswith("#import") or content.startswith("#import") or content.startswith("#include") or content.startswith("#ifndef") or content.startswith("#if") or content.startswith("#define") or content.startswith("#"):
        # File starts with code/comments but no doc header
        # Add SPDX lines at the very top
        extra = ""
        if is_mstwalker:
            extra = MSTWALKER_ATTRIBUTION
        new_content = spdx_block + extra + content
    else:
        # Fallback: add at top
        extra = ""
        if is_mstwalker:
            extra = MSTWALKER_ATTRIBUTION
        new_content = spdx_block + extra + content

    with open(filepath, 'w') as f:
        f.write(new_content)

    return "added"

def main():
    root = "/Users/jack/Software/garazyk"
    extensions = {'.h', '.m', '.c'}

    # Directories to process
    source_dirs = [
        os.path.join(root, "Garazyk/Sources"),
        os.path.join(root, "Garazyk/Tests"),
        os.path.join(root, "Garazyk/Binaries"),
    ]

    # Directories to skip
    skip_dirs = {
        "vendor",
        "secp256k1",
    }

    stats = {"added": 0, "skip-existing": 0, "error": 0}

    for source_dir in source_dirs:
        for dirpath, dirnames, filenames in os.walk(source_dir):
            # Skip vendor directories
            rel = os.path.relpath(dirpath, root)
            should_skip = False
            for skip in skip_dirs:
                if rel.startswith(skip):
                    should_skip = True
                    break
            if should_skip:
                dirnames.clear()
                continue

            for filename in filenames:
                ext = os.path.splitext(filename)[1]
                if ext not in extensions:
                    continue

                filepath = os.path.join(dirpath, filename)
                try:
                    result = process_file(filepath)
                    stats[result] += 1
                except Exception as e:
                    print(f"ERROR: {filepath}: {e}", file=sys.stderr)
                    stats["error"] += 1

    print(f"Added: {stats['added']}")
    print(f"Skipped (existing): {stats['skip-existing']}")
    print(f"Errors: {stats['error']}")

if __name__ == "__main__":
    main()
