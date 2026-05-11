"""Scenario 24: "Concurrent Write Throughput" — Bluesky-scale concurrent repo writes

Exercise 32 accounts with sequential warm-up posts, a 32-thread burst,
then a mixed workload of creates, deletes, and applyWrites operations.
The scenario records instrumentation for latency, throughput, process, and
storage behavior while the PDS is under load.

Services: PDS
"""

from __future__ import annotations

import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call
from scripts.lib.atproto.config import SERVICE_URLS
from scripts.lib.atproto.diagnostics import create_run_context
from scripts.lib.atproto.instrumentation import (
    PrometheusScraper,
    ProcessMonitor,
    StorageMonitor,
    OperationTimer,
    PhaseTimer,
    InstrumentationReport,
)


_OPERATION_STATS_TYPE = type(OperationTimer().get_stats("__probe__"))


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


@dataclass
class AccountPlan:
    slot: int
    label: str
    name: str
    handle: str
    email: str
    password: str
    did: str | None = None
    access_jwt: str | None = None
    created_rkeys: list[str] = field(default_factory=list)
    warmup_rkeys: list[str] = field(default_factory=list)
    burst_rkeys: list[str] = field(default_factory=list)
    mixed_rkeys: list[str] = field(default_factory=list)
    deleted_rkeys: set[str] = field(default_factory=set)


@contextmanager
def _phase_scope(phase_timer: PhaseTimer, name: str):
    phase_timer.start_phase(name)
    try:
        yield
    finally:
        phase_timer.end_phase()


def _extract_rkey(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


def _merge_operation_stats(target: dict[str, Any], source: dict[str, Any]) -> None:
    for name, stats in source.items():
        combined = target.get(name)
        if combined is None:
            combined = _OPERATION_STATS_TYPE(name=name)
            target[name] = combined
        for duration_ns in getattr(stats, "_durations_ns", []):
            combined.record(duration_ns)


def _merge_operation_timer(target: dict[str, Any], timer: OperationTimer) -> None:
    _merge_operation_stats(target, timer.get_all_stats())


def _build_accounts() -> list[AccountPlan]:
    accounts: list[AccountPlan] = []
    seed_names = ["luna", "marcus", "rosa", "volt", "quiet"]

    for slot, name in enumerate(seed_names, start=1):
        char = get_character(name)
        accounts.append(
            AccountPlan(
                slot=slot,
                label=name,
                name=char.name,
                handle=char.handle,
                email=char.email,
                password=char.password,
            )
        )

    for slot in range(6, 33):
        label = f"load-{slot}"
        accounts.append(
            AccountPlan(
                slot=slot,
                label=label,
                name=f"Load Account {slot}",
                handle=f"{label}.test",
                email=f"{label}@test.local",
                password=f"load-pass-{slot:02d}",
            )
        )

    return accounts


def _remember_created(plan: AccountPlan, rkeys: list[str]) -> None:
    plan.created_rkeys.extend(rkeys)


def _current_expected_rkeys(plan: AccountPlan) -> set[str]:
    return set(plan.created_rkeys) - plan.deleted_rkeys


def run() -> ScenarioResult:
    result = ScenarioResult("Concurrent Write Throughput")
    result.start()

    ctx = create_run_context()
    client = XrpcClient(PDS1)
    accounts = _build_accounts()
    phase_timer = PhaseTimer()

    pds_metrics_url = f"{SERVICE_URLS['pds']}/metrics"
    pds_data_dir = os.environ.get("PDS_DATA_DIR", "/tmp/garazyk-atproto-e2e/pds-data")
    pds_db_path = f"{pds_data_dir}/pds.db"
    pds_wal_path = f"{pds_data_dir}/pds.db-wal"

    prometheus = PrometheusScraper({"pds": pds_metrics_url})
    _pid_file = os.environ.get("ATPROTO_E2E_PID_FILE") or None
    _compose_project = os.environ.get("ATPROTO_E2E_COMPOSE_PROJECT")
    process_monitor = ProcessMonitor(["pds"], ["kaszlak"], pid_file=_pid_file, docker_compose_project=_compose_project)
    storage_monitor = StorageMonitor({"pds": [pds_db_path, pds_wal_path]})

    setup_timer = OperationTimer()
    warmup_timer = OperationTimer()
    cooldown_timer = OperationTimer()
    worker_timers: list[OperationTimer] = []
    workload_completed = False

    prometheus.start()
    process_monitor.start()
    storage_monitor.start()

    try:
        timed_call(
            result,
            "PDS health check",
            lambda: client.wait_for_healthy(timeout=30),
        )
        if result.failed > 0:
            return result

        with _phase_scope(phase_timer, "Setup"):
            created_accounts = 0
            setup_failures = 0
            for plan in accounts:
                if plan.slot <= 5:
                    character = get_character(plan.label)
                    session = timed_call(
                        result,
                        f"Create account: {character.name}",
                        lambda p=plan: _create_account(client, setup_timer, p),
                        detail_fn=lambda s: f"did={s['did']}",
                    )
                else:
                    session = timed_call(
                        result,
                        f"Create account: {plan.name}",
                        lambda p=plan: _create_account(client, setup_timer, p),
                        detail_fn=lambda s: f"did={s['did']}",
                    )

                if session:
                    plan.did = session["did"]
                    plan.access_jwt = session["accessJwt"]
                    created_accounts += 1
                    if plan.slot <= 5:
                        character.did = plan.did
                        character.access_jwt = plan.access_jwt
                else:
                    setup_failures += 1

            if created_accounts != len(accounts):
                result.step_failed(
                    "Setup accounts",
                    f"created={created_accounts}/{len(accounts)}, failures={setup_failures}",
                )
                return result

            result.step_passed(
                "Setup accounts",
                f"created={created_accounts}, first_five_from_character_pool=5, generated_handles={len(accounts) - 5}",
            )

        with _phase_scope(phase_timer, "Warm-up"):
            warmup_started = time.perf_counter()
            warmup_successes = 0
            warmup_failures = 0
            for plan in accounts:
                for index in range(5):
                    rkey = f"w{plan.slot}-{index + 1}"
                    try:
                        with warmup_timer.measure("create_record"), warmup_timer.measure("create_post_warmup"):
                            response = client.records.create_record(
                                plan.did,
                                "app.bsky.feed.post",
                                {
                                    "$type": "app.bsky.feed.post",
                                    "text": f"Warm-up post {index + 1} from {plan.name}",
                                    "createdAt": _now(),
                                },
                                plan.access_jwt,
                                rkey=rkey,
                            )
                        created_rkey = _extract_rkey(response["uri"])
                        plan.warmup_rkeys.append(created_rkey)
                        _remember_created(plan, [created_rkey])
                        warmup_successes += 1
                    except Exception:
                        warmup_failures += 1

            warmup_elapsed = time.perf_counter() - warmup_started
            if warmup_failures == 0:
                result.step_passed(
                    "Warm-up",
                    f"posts={warmup_successes}, failures=0, elapsed={warmup_elapsed:.1f}s, rate={warmup_successes/max(warmup_elapsed, 0.01):.1f} posts/s",
                )
            else:
                result.step_failed(
                    "Warm-up",
                    f"posts={warmup_successes}, failures={warmup_failures}, elapsed={warmup_elapsed:.1f}s",
                )

        burst_started = time.perf_counter()
        burst_successes = 0
        burst_failures = 0
        with _phase_scope(phase_timer, "Burst"):
            with ThreadPoolExecutor(max_workers=len(accounts)) as executor:
                futures = [executor.submit(_burst_worker, plan) for plan in accounts]
                for future in as_completed(futures):
                    worker_result = future.result()
                    burst_successes += worker_result["successes"]
                    burst_failures += worker_result["failures"]
                    worker_timers.append(worker_result["timer"])
        burst_elapsed = time.perf_counter() - burst_started
        burst_rate = burst_successes / max(burst_elapsed, 0.01)
        if burst_failures == 0:
            result.step_passed(
                "Burst",
                f"created={burst_successes}, failed=0, elapsed={burst_elapsed:.1f}s, rate={burst_rate:.1f} writes/s",
            )
        else:
            result.step_failed(
                "Burst",
                f"created={burst_successes}, failed={burst_failures}, elapsed={burst_elapsed:.1f}s, rate={burst_rate:.1f} writes/s",
            )

        mixed_started = time.perf_counter()
        mixed_create_successes = 0
        mixed_delete_successes = 0
        mixed_apply_successes = 0
        mixed_failures = 0
        with _phase_scope(phase_timer, "Mixed workload"):
            with ThreadPoolExecutor(max_workers=len(accounts)) as executor:
                futures = [executor.submit(_mixed_worker, plan) for plan in accounts]
                for future in as_completed(futures):
                    worker_result = future.result()
                    mixed_create_successes += worker_result["create_successes"]
                    mixed_delete_successes += worker_result["delete_successes"]
                    mixed_apply_successes += worker_result["apply_successes"]
                    mixed_failures += worker_result["failures"]
                    worker_timers.append(worker_result["timer"])
        mixed_elapsed = time.perf_counter() - mixed_started
        if mixed_failures == 0:
            result.step_passed(
                "Mixed workload",
                (
                    f"creates={mixed_create_successes}, deletes={mixed_delete_successes}, "
                    f"applyWrites={mixed_apply_successes}, failures=0, elapsed={mixed_elapsed:.1f}s"
                ),
            )
        else:
            result.step_failed(
                "Mixed workload",
                (
                    f"creates={mixed_create_successes}, deletes={mixed_delete_successes}, "
                    f"applyWrites={mixed_apply_successes}, failures={mixed_failures}, elapsed={mixed_elapsed:.1f}s"
                ),
            )

        with _phase_scope(phase_timer, "Cooldown"):
            verified_accounts = 0
            inconsistent_accounts = 0
            for plan in accounts:
                records = timed_call(
                    result,
                    f"Cooldown verify: {plan.name}",
                    lambda p=plan: _verify_records(client, cooldown_timer, p),
                    detail_fn=lambda r: f"records={r['records']}, expected={r['expected']}",
                )
                if records:
                    verified_accounts += 1
                else:
                    inconsistent_accounts += 1

            if inconsistent_accounts == 0:
                result.step_passed(
                    "Cooldown consistency",
                    f"accounts={verified_accounts}, inconsistent=0",
                )
            else:
                result.step_failed(
                    "Cooldown consistency",
                    f"accounts={verified_accounts}, inconsistent={inconsistent_accounts}",
                )

            workload_completed = True


    finally:
        all_operation_stats: dict[str, Any] = {}
        _merge_operation_timer(all_operation_stats, setup_timer)
        _merge_operation_timer(all_operation_stats, warmup_timer)
        _merge_operation_timer(all_operation_stats, cooldown_timer)
        for timer in worker_timers:
            _merge_operation_timer(all_operation_stats, timer)

        prometheus_data: dict[str, Any] = {}
        process_data: dict[str, Any] = {}
        storage_data: dict[str, Any] = {}
        try:
            prometheus_data = prometheus.stop()
        except Exception as exc:
            result.step_failed("Prometheus scraper stop", str(exc))
        try:
            process_data = process_monitor.stop()
        except Exception as exc:
            result.step_failed("Process monitor stop", str(exc))
        try:
            storage_data = storage_monitor.stop()
        except Exception as exc:
            result.step_failed("Storage monitor stop", str(exc))

        report = InstrumentationReport(
            operation_stats=all_operation_stats,
            metrics_time_series=prometheus_data,
            process_stats=process_data,
            storage_stats=storage_data,
            phase_timings=phase_timer.to_dict(),
        )
        result.record_artifact("instrumentation", report.to_dict())
        result.record_artifact(
            "accounts",
            {
                plan.label: {
                    "slot": plan.slot,
                    "name": plan.name,
                    "handle": plan.handle,
                    "did": plan.did,
                    "created_rkeys": list(plan.created_rkeys),
                    "deleted_rkeys": sorted(plan.deleted_rkeys),
                    "expected_final_count": len(_current_expected_rkeys(plan)),
                }
                for plan in accounts
            },
        )

        if workload_completed:
            create_post_p95_ms = _p95_ms(all_operation_stats, "create_record")
            burst_throughput_ok = burst_rate >= 32.0
            burst_writes_ok = burst_failures == 0
            create_latency_ok = create_post_p95_ms < 500.0

            storage_stats = storage_data.get("pds")
            if storage_stats and storage_stats.samples:
                final_db_bytes = storage_stats.samples[-1].db_size_bytes
                final_wal_bytes = storage_stats.samples[-1].wal_size_bytes
            else:
                final_db_bytes = 0
                final_wal_bytes = 0
            wal_ratio_ok = final_wal_bytes == 0 if final_db_bytes == 0 else final_wal_bytes < (2 * final_db_bytes)

            if burst_writes_ok:
                result.step_passed("Burst writes succeeded", f"failures=0, writes={burst_successes}")
            else:
                result.step_failed("Burst writes succeeded", f"failures={burst_failures}, writes={burst_successes}")

            if create_latency_ok:
                result.step_passed("Create record p95 < 500ms", f"p95_ms={create_post_p95_ms:.1f}")
            else:
                result.step_failed("Create record p95 < 500ms", f"p95_ms={create_post_p95_ms:.1f}")

            if burst_throughput_ok:
                result.step_passed("Burst throughput >= 32 writes/sec", f"rate={burst_rate:.1f} writes/s")
            else:
                result.step_failed("Burst throughput >= 32 writes/sec", f"rate={burst_rate:.1f} writes/s")

            if wal_ratio_ok:
                result.step_passed(
                    "Storage WAL < 2x DB",
                    f"db_bytes={final_db_bytes}, wal_bytes={final_wal_bytes}",
                )
            else:
                result.step_failed(
                    "Storage WAL < 2x DB",
                    f"db_bytes={final_db_bytes}, wal_bytes={final_wal_bytes}",
                )

        try:
            report.write_json(str(ctx.reports_dir / "instrumentation-24.json"))
            report.write_html(
                str(ctx.reports_dir / "instrumentation-24.html"),
                title="Concurrent Write Throughput",
            )
            result.step_passed("Instrumentation reports written", str(ctx.reports_dir))
        except Exception as exc:
            result.step_failed("Instrumentation reports written", str(exc))

        result.finish()

    return result


def _create_account(client: XrpcClient, timer: OperationTimer, plan: AccountPlan) -> dict[str, Any]:
    with timer.measure("create_account"):
        return client.accounts.create_account(plan.handle, plan.email, plan.password)


def _burst_worker(plan: AccountPlan) -> dict[str, Any]:
    client = XrpcClient(PDS1)
    timer = OperationTimer()
    successes = 0
    failures = 0

    for index in range(10):
        rkey = f"b{plan.slot}-{index + 1}"
        try:
            with timer.measure("create_record"), timer.measure("create_post_burst"):
                response = client.records.create_record(
                    plan.did,
                    "app.bsky.feed.post",
                    {
                        "$type": "app.bsky.feed.post",
                        "text": f"Burst post {index + 1} from {plan.name}",
                        "createdAt": _now(),
                    },
                    plan.access_jwt,
                    rkey=rkey,
                )
            created_rkey = _extract_rkey(response["uri"])
            plan.burst_rkeys.append(created_rkey)
            _remember_created(plan, [created_rkey])
            successes += 1
        except Exception:
            failures += 1

    return {"successes": successes, "failures": failures, "timer": timer}


def _mixed_worker(plan: AccountPlan) -> dict[str, Any]:
    client = XrpcClient(PDS1)
    timer = OperationTimer()
    create_successes = 0
    delete_successes = 0
    apply_successes = 0
    failures = 0

    create_rkey = f"m{plan.slot}-c"
    try:
        with timer.measure("create_record"), timer.measure("create_post_mixed"):
            response = client.records.create_record(
                plan.did,
                "app.bsky.feed.post",
                {
                    "$type": "app.bsky.feed.post",
                    "text": f"Mixed workload post from {plan.name}",
                    "createdAt": _now(),
                },
                plan.access_jwt,
                rkey=create_rkey,
            )
        created_rkey = _extract_rkey(response["uri"])
        plan.mixed_rkeys.append(created_rkey)
        _remember_created(plan, [created_rkey])
        create_successes += 1
    except Exception:
        failures += 1

    delete_target = plan.warmup_rkeys[0] if plan.warmup_rkeys else (plan.burst_rkeys[0] if plan.burst_rkeys else None)
    if delete_target:
        try:
            with timer.measure("delete_record"), timer.measure("delete_post_mixed"):
                client.records.delete_record(
                    plan.did,
                    "app.bsky.feed.post",
                    delete_target,
                    plan.access_jwt,
                )
            plan.deleted_rkeys.add(delete_target)
            delete_successes += 1
        except Exception:
            failures += 1
    else:
        failures += 1

    batch_rkeys = [f"m{plan.slot}-a", f"m{plan.slot}-b"]
    writes = [
        {
            "$type": "com.atproto.repo.applyWrites#create",
            "collection": "app.bsky.feed.post",
            "rkey": rkey,
            "value": {
                "$type": "app.bsky.feed.post",
                "text": f"Batch write {suffix} from {plan.name}",
                "createdAt": _now(),
            },
        }
        for suffix, rkey in zip(("A", "B"), batch_rkeys)
    ]
    try:
        with timer.measure("apply_writes"), timer.measure("apply_writes_mixed"):
            response = client.records.apply_writes(plan.did, writes, plan.access_jwt)
        returned_rkeys = []
        for item in response.get("results", []):
            uri = item.get("uri")
            if uri:
                returned_rkeys.append(_extract_rkey(uri))
        if not returned_rkeys:
            returned_rkeys = batch_rkeys
        plan.mixed_rkeys.extend(returned_rkeys)
        _remember_created(plan, returned_rkeys)
        apply_successes += len(returned_rkeys)
    except Exception:
        failures += 1

    return {
        "create_successes": create_successes,
        "delete_successes": delete_successes,
        "apply_successes": apply_successes,
        "failures": failures,
        "timer": timer,
    }


def _verify_records(client: XrpcClient, timer: OperationTimer, plan: AccountPlan) -> dict[str, Any]:
    with timer.measure("list_records"), timer.measure("list_records_cooldown"):
        response = client.records.list_records(plan.did, "app.bsky.feed.post", limit=100, token=plan.access_jwt)

    records = response.get("records", [])
    actual_rkeys = {_extract_rkey(record["uri"]) for record in records if record.get("uri")}
    expected_rkeys = _current_expected_rkeys(plan)
    missing = sorted(expected_rkeys - actual_rkeys)
    unexpected = sorted(actual_rkeys - expected_rkeys)

    if missing or unexpected:
        raise AssertionError(
            f"missing={len(missing)} ({', '.join(missing[:5])}), unexpected={len(unexpected)} ({', '.join(unexpected[:5])})"
        )

    return {"records": len(actual_rkeys), "expected": len(expected_rkeys)}


def _p95_ms(stats: dict[str, Any], name: str) -> float:
    operation = stats.get(name)
    if operation is None:
        return 0.0
    return round(operation.p95_ns / 1_000_000.0, 1)


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
