#!/usr/bin/env python3
import json
import sys
import argparse

def main():
    parser = argparse.ArgumentParser(description='Process OCLint JSON report.')
    parser.add_argument('report_file', help='Path to OCLint JSON report')
    parser.add_argument('--threshold', type=int, default=20, help='Max allowed priority 1/2 violations')
    args = parser.parse_args()

    try:
        with open(args.report_file, 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: Report file {args.report_file} not found.")
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: Failed to decode JSON from {args.report_file}.")
        sys.exit(1)

    violations = data.get('violation', [])
    summary = data.get('summary', {})
    
    # Count by priority
    p1 = summary.get('numberOfViolationsWithPriority1', 0)
    p2 = summary.get('numberOfViolationsWithPriority2', 0)
    p3 = summary.get('numberOfViolationsWithPriority3', 0)
    
    total_critical = p1 + p2
    
    print("=" * 40)
    print("OCLint Analysis Summary")
    print("=" * 40)
    print(f"Total Violations: {len(violations)}")
    print(f"Priority 1: {p1}")
    print(f"Priority 2: {p2}")
    print(f"Priority 3: {p3}")
    print("-" * 40)
    
    if total_critical > 0:
        print("\nTop Issues:")
        # Sort by priority then line
        sorted_violations = sorted(violations, key=lambda x: (x.get('priority', 3), x.get('path', ''), x.get('startLine', 0)))
        
        for v in sorted_violations[:10]:
            path = v.get('path', 'unknown')
            line = v.get('startLine', 0)
            rule = v.get('rule', 'unknown')
            msg = v.get('message', '')
            prio = v.get('priority', 3)
            print(f"[P{prio}] {path}:{line} - {rule}: {msg}")
            
        if len(violations) > 10:
            print(f"... and {len(violations) - 10} more.")

    print("=" * 40)

    if total_critical > args.threshold:
        print(f"FAILURE: Critical violations ({total_critical}) exceeded threshold ({args.threshold}).")
        sys.exit(1)
    else:
        print(f"SUCCESS: Critical violations ({total_critical}) within threshold ({args.threshold}).")
        sys.exit(0)

if __name__ == "__main__":
    main()
