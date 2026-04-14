#!/usr/bin/env python3
"""
doc-coverage.py - Documentation coverage for Objective-C headers
"""

import os
import re
import sys
from pathlib import Path

def count_documentation(content):
    """Count documented vs total items in an Objective-C header."""
    results = {
        'classes': {'total': 0, 'documented': 0},
        'methods': {'total': 0, 'documented': 0},
        'properties': {'total': 0, 'documented': 0},
        'enums': {'total': 0, 'documented': 0},
        'categories': {'total': 0, 'documented': 0},
        'protocols': {'total': 0, 'documented': 0},
    }

    lines = content.split('\n')

    # Track doc blocks
    in_doc_block = False
    doc_block_start = 0

    for i, line in enumerate(lines):
        # Track doc blocks
        if '/*!' in line or '/**' in line:
            in_doc_block = True
            doc_block_start = i
        if '*/' in line and in_doc_block:
            in_doc_block = False

        # Count classes (@interface without category)
        if re.match(r'^@interface\s+\w+\s*[:{<]', line):
            results['classes']['total'] += 1
            # Check for doc in previous 10 lines
            prev = '\n'.join(lines[max(0, i-10):i])
            if '@class' in prev or '@abstract' in prev:
                results['classes']['documented'] += 1

        # Count categories (@interface with parentheses)
        if re.match(r'^@interface\s+\w+\s*\(', line):
            results['categories']['total'] += 1
            prev = '\n'.join(lines[max(0, i-10):i])
            if '@category' in prev or '@abstract' in prev:
                results['categories']['documented'] += 1

        # Count protocols
        if re.match(r'^@protocol\s+\w+', line):
            results['protocols']['total'] += 1
            prev = '\n'.join(lines[max(0, i-10):i])
            if '@protocol' in prev or '@abstract' in prev:
                results['protocols']['documented'] += 1

        # Count properties
        if '@property' in line:
            results['properties']['total'] += 1
            # Check previous line or doc block
            prev = '\n'.join(lines[max(0, i-5):i])
            if '@abstract' in prev or '@property' in prev or '/*!' in prev:
                results['properties']['documented'] += 1

        # Count methods
        if re.match(r'^[\+\-]\s*\(', line):
            results['methods']['total'] += 1
            # Check for recent doc block
            if i - doc_block_start <= 10 and doc_block_start > 0:
                results['methods']['documented'] += 1

        # Count enums
        if 'typedef NS_ENUM' in line or 'typedef NS_OPTIONS' in line:
            results['enums']['total'] += 1
            prev = '\n'.join(lines[max(0, i-10):i])
            if '@enum' in prev or '@abstract' in prev:
                results['enums']['documented'] += 1

    return results


def main():
    search_dir = sys.argv[1] if len(sys.argv) > 1 else 'Garazyk/Sources'

    totals = {
        'classes': {'total': 0, 'documented': 0},
        'methods': {'total': 0, 'documented': 0},
        'properties': {'total': 0, 'documented': 0},
        'enums': {'total': 0, 'documented': 0},
        'categories': {'total': 0, 'documented': 0},
        'protocols': {'total': 0, 'documented': 0},
    }

    file_count = 0

    for root, dirs, files in os.walk(search_dir):
        # Skip compat directories
        if '/Compat/' in root:
            continue

        for fname in files:
            if not fname.endswith('.h'):
                continue

            file_count += 1
            fpath = os.path.join(root, fname)

            try:
                with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
            except:
                continue

            results = count_documentation(content)

            for key in totals:
                totals[key]['total'] += results[key]['total']
                totals[key]['documented'] += results[key]['documented']

    # Print report
    print()
    print("DOCUMENTATION COVERAGE REPORT")
    print("==============================")
    print()

    def pct(total, documented):
        if total == 0:
            return 100
        return (documented * 100) // total

    for key in ['classes', 'methods', 'properties', 'enums', 'categories', 'protocols']:
        t = totals[key]['total']
        d = totals[key]['documented']
        p = pct(t, d)
        print(f"{key.capitalize():12} {d:5} / {t:<5} ({p:3}%)")

    print()
    print("------------------------------")

    grand_total = sum(totals[k]['total'] for k in totals)
    grand_doc = sum(totals[k]['documented'] for k in totals)
    overall_pct = pct(grand_total, grand_doc)

    print(f"{'OVERALL':12} {grand_doc:5} / {grand_total:<5} ({overall_pct:3}%)")
    print()
    print(f"Files analyzed: {file_count}")
    print()

    if overall_pct >= 90:
        print("[PASS] Coverage >= 90%")
        sys.exit(0)
    elif overall_pct >= 70:
        print("[WARN] Coverage < 90%")
        sys.exit(0)
    else:
        print("[FAIL] Coverage < 70%")
        sys.exit(1)


if __name__ == '__main__':
    main()
