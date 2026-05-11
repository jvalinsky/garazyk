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
    python run_scenario.py --timeout 60      # Kill scenarios after 60s
"""

from __future__ import annotations

import argparse
import importlib
import json
import logging
import os
import signal
import sys
import time
from pathlib import Path

# Add scenario-local compatibility shims and repository helpers to path.
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(REPO_ROOT))

from scripts.lib.atproto import ScenarioResult, StepStatus, SERVICE_URLS, create_run_context
from scripts.lib.atproto.docker import (
    collect_local_network_diagnostics,
    start_local_network,
    stop_local_network,
)

SCENARIOS_DIR = SCRIPT_DIR / "scenarios"

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
    ("11", "scenarios.11_lab_oauth_login", "Lab OAuth2 Login", False),
    ("12", "scenarios.12_account_migration", "Account Migration & PLC Audit", True),
    ("13", "scenarios.13_oauth_client_e2e", "E2E OAuth2 Client Integration", False),
    ("14", "scenarios.14_drafts_bookmarks", "Drafts & Bookmarks Workflow", False),
    ("15", "scenarios.15_mutes_relationships_starterpacks", "Mutes, Relationships & Starter Packs", False),
    ("16", "scenarios.16_notification_management", "Notification Management & Preferences", False),
    ("17", "scenarios.17_actor_preferences_discovery", "Actor Preferences & Discovery", False),
    ("18", "scenarios.18_admin_operations", "AppView Admin Operations", False),
    ("19", "scenarios.19_contact_age_assurance", "Contact Management & Age Assurance", False),
    ("20", "scenarios.20_unspecced_search", "Unspecced Search & Discovery", False),
    ("21", "scenarios.21_appview_lexicon_endpoints", "AppView Lexicon-Driven Endpoints", False),
    ("22", "scenarios.22_appview_hooks", "AppView Index Hooks & Dead Letter", False),
    ("23", "scenarios.23_appview_write_proxy", "AppView Write Proxy & OAuth2", False),
    ("24", "scenarios.24_concurrent_write_throughput", "Concurrent Write Throughput (Instrumented)", False),
    ("25", "scenarios.25_firehose_fanout_scale", "Firehose Fan-Out at Scale (Instrumented)", False),
    ("26", "scenarios.26_appview_ingest_load", "AppView Ingest Under Load (Instrumented)", False),
    ("27", "scenarios.27_fullstack_soak", "Full-Stack Soak Test (Instrumented)", False),
    ("28", "scenarios.28_repo_format_benchmarks", "Repo Format Benchmarks (CAR vs STAR)", False),
    ("29", "scenarios.29_depth_charger", "The Depth Charger (Serialization Limits)", False),
    ("30", "scenarios.30_temporal_distortion", "Temporal Distortion (Clock Skew)", False),
    ("31", "scenarios.31_noisy_neighbor", "The Noisy Neighbor (Rate Limiting)", False),
    ("32", "scenarios.32_identity_fatigue", "Identity Fatigue (PLC Quota)", False),
    ("33", "scenarios.33_tortoise_consumer", "The Tortoise Consumer (Firehose Backpressure)", False),
    ("34", "scenarios.34_format_roundtrip", "Format Round-Trip (STAR/CAR Integrity)", False),
    ("35", "scenarios.35_interrupted_migration", "The Interrupted Migration (Atomicity)", False),
    ("10", "scenarios.10_performance_resilience", "Performance & Resilience", False),
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


def _run_scenario_in_process(module_name: str) -> ScenarioResult:
    """Import and execute a scenario module inside a subprocess.

    This function runs inside a child process spawned by
    run_scenario(). It must not share state with the parent.
    """
    mod = importlib.import_module(module_name)
    return mod.run()


def run_scenario(scenario_id: str, verbose: bool = False, timeout: int = 120) -> ScenarioResult:
    """Import and run a single scenario by ID.

    timeout sets the maximum wall-clock seconds a scenario may run
    before being killed. A timed-out scenario is reported as a
    single failed step rather than hanging the entire runner.
    """
    import concurrent.futures

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
        from scripts.lib.atproto import reset_characters
        reset_characters()
    except ImportError:
        pass

    # Set up logging
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format="%(name)s: %(message)s")

    # Import the scenario module (lightweight check before spawning process)
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
        with concurrent.futures.ProcessPoolExecutor(max_workers=1) as executor:
            future = executor.submit(_run_scenario_in_process, module_name)
            result = future.result(timeout=timeout)
    except concurrent.futures.TimeoutError:
        print(f"ERROR: Scenario {sid} timed out after {timeout}s")
        result = ScenarioResult(scenario_name=desc)
        result.step_failed(f"Scenario {sid} timeout", f"exceeded {timeout}s wall-clock limit")
    except Exception as exc:
        print(f"ERROR: Scenario {sid} crashed: {exc}")
        result = ScenarioResult(scenario_name=desc)
        result.step_failed(f"Scenario {sid} execution", str(exc))

    if result.started_at is None:
        result.started_at = time.time()
    if result.finished_at is None:
        result.finished_at = time.time()
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
        "--setup",
        action="store_true",
        help="Start the local network before running scenarios",
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
    parser.add_argument(
        "--run-id",
        default=os.environ.get("ATPROTO_E2E_RUN_ID", ""),
        help="Run id used for logs, reports, diagnostics, and compose project naming",
    )
    parser.add_argument(
        "--diagnostics-dir",
        default=os.environ.get("ATPROTO_E2E_DIAGNOSTICS_DIR", ""),
        help="Directory for diagnostic bundles",
    )
    parser.add_argument(
        "--reports-dir",
        default=os.environ.get("ATPROTO_E2E_REPORTS_DIR", ""),
        help="Directory for scenario JSON reports",
    )
    parser.add_argument(
        "--collect-diagnostics",
        action="store_true",
        help="Collect diagnostics for the current run and exit",
    )
    parser.add_argument(
        "--keep-running",
        action="store_true",
        help="Leave services running after setup or scenario execution",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=120,
        help="Per-scenario wall-clock timeout in seconds (default: 120)",
    )

    args = parser.parse_args()
    context = create_run_context(
        run_id=args.run_id or None,
        diagnostics_dir=args.diagnostics_dir or None,
    )
    reports_dir = Path(args.reports_dir) if args.reports_dir else context.reports_dir
    reports_dir.mkdir(parents=True, exist_ok=True)

    if args.list:
        list_scenarios()
        return

    if args.collect_diagnostics:
        collect_local_network_diagnostics(use_binary=args.binary, context=context)
        print(f"Diagnostics: {context.diagnostics_dir}")
        return

    # Determine which scenarios to run
    if args.scenarios:
        scenario_ids = args.scenarios
    else:
        scenario_ids = [sid for sid, _, _, needs_pds2 in SCENARIO_REGISTRY
                        if not needs_pds2 or args.pds2]

    # Setup
    if args.setup_only:
        print(f"Starting local network (setup only, binary={args.binary})...")
        start_local_network(with_pds2=args.pds2, use_binary=args.binary, context=context)
        print(f"Run directory: {context.run_dir}")
        if args.keep_running:
            print("Network is running. Stop it with:")
            stop_cmd = [
                str(SCRIPT_DIR / "setup_local_network.sh"),
                "--teardown",
                "--run-id",
                context.run_id,
            ]
            if args.binary:
                stop_cmd.append("--binary")
            print("  " + " ".join(stop_cmd))
            return
        print("Network is running. Press Ctrl+C to stop and collect diagnostics.")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            pass
        finally:
            stop_local_network(use_binary=args.binary, context=context, collect_diagnostics=True)
        return

    network_started = False
    interrupted = False

    def _handle_signal(signum: int, _frame: object) -> None:
        nonlocal interrupted
        interrupted = True
        print(f"\nInterrupted by signal {signum}; collecting diagnostics...", file=sys.stderr)
        collect_local_network_diagnostics(use_binary=args.binary, context=context)
        if network_started and not args.keep_running:
            stop_local_network(
                use_binary=args.binary,
                context=context,
                collect_diagnostics=False,
            )
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    # Run scenarios
    results: list[ScenarioResult] = []
    report_paths: list[str] = []
    try:
        if args.setup:
            start_local_network(with_pds2=args.pds2, use_binary=args.binary, context=context)
            network_started = True

        for sid in scenario_ids:
            print(f"\n{'='*60}")
            print(f"  Running scenario {sid}...")
            print(f"{'='*60}")
            result = run_scenario(sid, verbose=args.verbose, timeout=args.timeout)
            result.metadata.update(
                {
                    "run_id": context.run_id,
                    "run_dir": str(context.run_dir),
                    "diagnostics_dir": str(context.diagnostics_dir),
                    "service_urls": SERVICE_URLS,
                    "scenario_id": sid,
                    "binary_mode": args.binary,
                    "pds2": args.pds2,
                }
            )
            result.print_summary()
            if not args.no_json:
                report_path = result.write_report(str(reports_dir))
                report_paths.append(report_path)
                print(f"  Report: {report_path}")
            results.append(result)
    except KeyboardInterrupt:
        if not interrupted:
            collect_local_network_diagnostics(use_binary=args.binary, context=context)
        raise SystemExit(130)
    finally:
        should_collect = any(r.failed for r in results)
        if should_collect:
            collect_local_network_diagnostics(use_binary=args.binary, context=context)
        if (args.teardown or args.setup) and not args.keep_running:
            print("\nTearing down local network...")
            stop_local_network(
                use_binary=args.binary,
                context=context,
                collect_diagnostics=False,
            )

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

    overall = {
        "run_id": context.run_id,
        "run_dir": str(context.run_dir),
        "diagnostics_dir": str(context.diagnostics_dir),
        "reports_dir": str(reports_dir),
        "scenario_ids": scenario_ids,
        "binary_mode": args.binary,
        "pds2": args.pds2,
        "report_paths": report_paths,
        "summary": {
            "passed": total_passed,
            "failed": total_failed,
            "skipped": total_skipped,
        },
        "ok": total_failed == 0,
    }
    (reports_dir / "overall-summary.json").write_text(
        json.dumps(overall, indent=2), encoding="utf-8"
    )
    if total_failed > 0:
        print(f"  Diagnostics: {context.diagnostics_dir}")

    sys.exit(1 if total_failed > 0 else 0)


if __name__ == "__main__":
    main()
