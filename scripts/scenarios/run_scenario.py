#!/usr/bin/env python3
"""ATProto Scenario Runner — Run one, some, or all scenario simulations.

Usage:
    python run_scenario.py                    # Run all scenarios
    python run_scenario.py 01                 # Run scenario 1 only
    python run_scenario.py 01 03 05           # Run specific scenarios
    python run_scenario.py --list             # List available scenarios
    python run_scenario.py --setup-only       # Start network, don't run
    python run_scenario.py --teardown         # Stop network after running
    python run_scenario.py --pds2             # Start second PDS for federation
    python run_scenario.py --verbose          # Debug output
"""

from __future__ import annotations

import argparse
import importlib
import logging
import sys
import time
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent))

from lib.report import ScenarioResult, StepStatus

SCENARIOS_DIR = Path(__file__).parent / "scenarios"
REPORTS_DIR = Path(__file__).parent / "reports"

# Scenario registry: (id, module_name, description, needs_pds2)
SCENARIO_REGISTRY = [
    ("01", "scenarios.01_account_lifecycle", "Account Lifecycle & Identity", False),
    ("02", "scenarios.02_social_graph", "Social Graph", False),
    ("03", "scenarios.03_content_creation", "Content Creation & Interaction", False),
    ("04", "scenarios.04_moderation_safety", "Moderation & Safety", False),
    ("05", "scenarios.05_federation", "Federation & Multi-PDS", True),
    ("06", "scenarios.06_chat_dms", "Chat & DMs", False),
    ("07", "scenarios.07_blobs_uploads", "Blobs & Uploads", False),
    ("08", "scenarios.08_oauth_sessions", "OAuth2 & Sessions", False),
    ("09", "scenarios.09_firehose_streaming", "Firehose & Event Streaming", False),
    ("10", "scenarios.10_performance_resilience", "Performance & Resilience", False),
    ("11", "scenarios.11_lab_oauth_login", "Lab OAuth2 Login", False),
]


def list_scenarios() -> None:
    """Print available scenarios."""
    print("\nAvailable ATProto Scenario Simulations:\n")
    print(f"  {'ID':<4} {'PDS2':<5} {'Description'}")
    print(f"  {'─'*4} {'─'*5} {'─'*40}")
    for sid, _, desc, needs_pds2 in SCENARIO_REGISTRY:
        pds2_marker = "yes" if needs_pds2 else ""
        print(f"  {sid:<4} {pds2_marker:<5} {desc}")
    print()


def run_scenario(scenario_id: str, verbose: bool = False) -> ScenarioResult:
    """Import and run a single scenario by ID."""
    # Find the scenario in the registry
    entry = None
    for sid, module_name, desc, _ in SCENARIO_REGISTRY:
        if sid == scenario_id:
            entry = (sid, module_name, desc)
            break

    if entry is None:
        print(f"ERROR: Unknown scenario '{scenario_id}'")
        sys.exit(1)

    sid, module_name, desc = entry

    # Reset character handles for each scenario to avoid PDS collisions
    try:
        from lib.characters import reset_characters
        reset_characters()
    except ImportError:
        pass

    # Set up logging
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format="%(name)s: %(message)s")

    # Import the scenario module
    try:
        mod = importlib.import_module(module_name)
    except ImportError as exc:
        print(f"ERROR: Could not import scenario {sid}: {exc}")
        result = ScenarioResult(scenario_name=desc)
        result.step_failed(f"Import scenario {sid}", str(exc))
        return result

    # Run it
    if not hasattr(mod, "run"):
        print(f"ERROR: Scenario {sid} has no 'run' function")
        result = ScenarioResult(scenario_name=desc)
        result.step_failed(f"Scenario {sid} entry point", "No 'run' function defined")
        return result

    try:
        result = mod.run()
    except Exception as exc:
        print(f"ERROR: Scenario {sid} crashed: {exc}")
        result = ScenarioResult(scenario_name=desc)
        result.step_failed(f"Scenario {sid} execution", str(exc))

    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description="ATProto Scenario Runner — Simulate real-world ATProto service scenarios"
    )
    parser.add_argument(
        "scenarios",
        nargs="*",
        help="Scenario IDs to run (e.g., 01 03 05). Default: all",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available scenarios and exit",
    )
    parser.add_argument(
        "--setup-only",
        action="store_true",
        help="Start the local network and exit without running scenarios",
    )
    parser.add_argument(
        "--teardown",
        action="store_true",
        help="Stop the local network after running scenarios",
    )
    parser.add_argument(
        "--binary",
        action="store_true",
        help="Use built binaries instead of Docker containers",
    )
    parser.add_argument(
        "--pds2",
        action="store_true",
        help="Start a second PDS for federation scenarios",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable debug output",
    )
    parser.add_argument(
        "--no-json",
        action="store_true",
        help="Don't write JSON report files",
    )

    args = parser.parse_args()

    if args.list:
        list_scenarios()
        return

    # Determine which scenarios to run
    if args.scenarios:
        scenario_ids = args.scenarios
    else:
        scenario_ids = [sid for sid, _, _, needs_pds2 in SCENARIO_REGISTRY
                        if not needs_pds2 or args.pds2]

    # Setup
    if args.setup_only:
        from lib.docker import start_local_network
        print(f"Starting local network (setup only, binary={args.binary})...")
        start_local_network(with_pds2=args.pds2, use_binary=args.binary)
        print("Network is running. Press Ctrl+C to stop.")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            pass
        return

    # Run scenarios
    results: list[ScenarioResult] = []
    for sid in scenario_ids:
        print(f"\n{'='*60}")
        print(f"  Running scenario {sid}...")
        print(f"{'='*60}")
        result = run_scenario(sid, verbose=args.verbose)
        result.print_summary()
        if not args.no_json:
            report_path = result.write_report(str(REPORTS_DIR))
            print(f"  Report: {report_path}")
        results.append(result)

    # Teardown
    if args.teardown:
        from lib.docker import stop_local_network
        print("\nTearing down local network...")
        stop_local_network(use_binary=args.binary)

    # Final summary
    total_passed = sum(r.passed for r in results)
    total_failed = sum(r.failed for r in results)
    total_skipped = sum(r.skipped for r in results)

    print(f"\n{'='*60}")
    print(f"  OVERALL RESULTS")
    print(f"{'='*60}")
    for r in results:
        icon = "PASS" if r.ok else "FAIL"
        color = "\033[0;32m" if r.ok else "\033[0;31m"
        reset = "\033[0m"
        print(f"  {color}{icon}{reset} {r.scenario_name} ({r.passed}/{r.total} passed, {r.skipped} skipped)")

    print(f"{'-'*60}")
    print(f"  Total: {total_passed} passed, {total_failed} failed, {total_skipped} skipped")
    print(f"{'='*60}")

    sys.exit(1 if total_failed > 0 else 0)


if __name__ == "__main__":
    main()
