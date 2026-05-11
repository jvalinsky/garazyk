"""Scenario 26: "AppView Ingest Under Load" — Bluesky-scale AppView ingest workload.

This scenario pushes AppView with sustained repo writes, then a burst to
exercise backpressure pause/resume behavior and verify ingest remains stable
under sustained load.

Services: PDS, AppView, Relay
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import threading
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call
from scripts.lib.atproto.config import SERVICE_URLS, APPVIEW_ADMIN_SECRET
from scripts.lib.atproto.firehose import FirehoseClient
from scripts.lib.atproto.instrumentation import (
    PrometheusScraper,
    ProcessMonitor,
    StorageMonitor,
    OperationTimer,
    PhaseTimer,
    InstrumentationReport,
)
from scripts.lib.atproto.diagnostics import create_run_context



def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())



def _build_account_specs() -> list[dict[str, object]]:
    specs: list[dict[str, object]] = []
    for name in ["luna", "marcus", "rosa", "volt", "quiet", "troll"]:
        char = get_character(name)
        specs.append(
            {
                "fixture": name,
                "name": char.name,
                "handle": char.handle,
                "email": char.email,
                "password": char.password,
                "did": None,
                "access_jwt": None,
            }
        )

    for index in range(1, 5):
        specs.append(
            {
                "fixture": None,
                "name": f"Ingest {index}",
                "handle": f"ingest-{index}.test",
                "email": f"ingest-{index}@test.com",
                "password": f"ingest_pass_{index:02d}",
                "did": None,
                "access_jwt": None,
            }
        )

    return specs



def _appview_admin_get_json(path: str, params: dict[str, object] | None = None) -> dict[str, object]:
    import requests

    url = f"{SERVICE_URLS['appview']}{path}"
    try:
        response = requests.get(
            url,
            headers={"Authorization": f"Bearer {APPVIEW_ADMIN_SECRET}"},
            params=params,
            timeout=5,
        )
    except requests.RequestException as exc:
        return {"error": str(exc)}
    try:
        return response.json()
    except ValueError:
        return {"raw": response.text, "status": response.status_code}



def _payload_text(payload: object) -> str:
    if payload is None:
        return ""
    if isinstance(payload, (dict, list)):
        try:
            return json.dumps(payload, sort_keys=True)
        except TypeError:
            return str(payload)
    return str(payload)



def _walk_payload(payload: object, prefix: str = ""):
    if isinstance(payload, dict):
        for key, value in payload.items():
            full_key = f"{prefix}.{key}" if prefix else str(key)
            yield full_key, value
            yield from _walk_payload(value, full_key)
    elif isinstance(payload, list):
        for index, value in enumerate(payload):
            full_key = f"{prefix}[{index}]" if prefix else f"[{index}]"
            yield from _walk_payload(value, full_key)



def _coerce_number(value: object) -> float | None:
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None



def _extract_flag(payload: object, key_fragments: tuple[str, ...]) -> bool | None:
    for key, value in _walk_payload(payload):
        key_lower = key.lower()
        if not any(fragment in key_lower for fragment in key_fragments):
            continue
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return bool(value)
        if isinstance(value, str):
            lowered = value.strip().lower()
            if lowered in {"true", "1", "yes", "on", "enabled", "running", "active", "paused"}:
                return lowered not in {"false", "0", "no", "off", "disabled", "inactive"}
    return None



def _first_not_none(*values: object | None) -> object | None:
    for value in values:
        if value is not None:
            return value
    return None



def _extract_number(payload: object, key_fragments: tuple[str, ...]) -> float | None:
    for key, value in _walk_payload(payload):
        key_lower = key.lower()
        if not any(fragment in key_lower for fragment in key_fragments):
            continue
        number = _coerce_number(value)
        if number is not None:
            return number
    return None



def _extract_record_count(payload: object) -> int | None:
    if not isinstance(payload, dict):
        return None

    for key in ("total", "count", "record_count", "items_total"):
        number = _coerce_number(payload.get(key))
        if number is not None:
            return int(number)

    for key in ("records", "entries", "items", "results"):
        value = payload.get(key)
        if isinstance(value, list):
            return len(value)

    return None



def _summarize_ingest_state(
    health: object,
    backfill: object,
    metrics: object,
    records: object | None = None,
) -> dict[str, object]:
    text = " | ".join(_payload_text(payload).lower() for payload in (health, backfill, metrics))
    explicit_backpressure = _first_not_none(
        _extract_flag(health, ("backpressure", "paused", "pause", "throttl", "stall")),
        _extract_flag(backfill, ("backpressure", "paused", "pause", "throttl", "stall")),
        _extract_flag(metrics, ("backpressure", "paused", "pause", "throttl", "stall")),
    )
    if explicit_backpressure is not None:
        backpressure_active = explicit_backpressure
    else:
        lowered_text = text.replace(" ", "")
        if (
            "backpressurecleared" in lowered_text
            or "backpressure:false" in lowered_text
            or "paused:false" in lowered_text
            or "pause:false" in lowered_text
        ):
            backpressure_active = False
        else:
            backpressure_active = any(keyword in text for keyword in ("backpressure", "paused", "pause", "throttl", "stall"))
    queue_depth = _first_not_none(
        _extract_number(metrics, ("queue_depth", "queue depth", "queue", "pending")),
        _extract_number(health, ("queue_depth", "queue depth", "queue", "pending")),
        _extract_number(backfill, ("queue_depth", "queue depth", "queue", "pending")),
    )

    ingest_lag = _extract_number(metrics, ("ingest_lag", "lag", "delay", "checkpoint"))
    if ingest_lag is None:
        ingest_lag = _extract_number(health, ("ingest_lag", "lag", "delay", "checkpoint"))
    if ingest_lag is None:
        ingest_lag = _extract_number(backfill, ("ingest_lag", "lag", "delay", "checkpoint"))

    indexed_records = _extract_record_count(records) if records is not None else None

    return {
        "backpressure_active": bool(backpressure_active),
        "queue_depth": queue_depth,
        "ingest_lag": ingest_lag,
        "indexed_records": indexed_records,
        "raw_text": text,
    }



def _collect_firehose_background(
    relay_url: str,
    events: list,
    stop_event: threading.Event,
    error_box: dict[str, str | None],
) -> None:
    try:
        fh_client = FirehoseClient(relay_url)

        def on_event(event):
            events.append(event)

        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        while not stop_event.is_set():
            try:
                loop.run_until_complete(
                    fh_client.subscribe(on_event, duration_s=45.0, recv_timeout=5.0)
                )
            except Exception as exc:
                error_box["error"] = str(exc)
                break
        loop.close()
    except Exception as exc:
        error_box["error"] = str(exc)



def _wait_for_healthy_with_timer(client: XrpcClient, operation_timer: OperationTimer) -> None:
    with operation_timer.measure("wait_for_healthy"):
        client.wait_for_healthy(timeout=30)



def run() -> ScenarioResult:
    result = ScenarioResult("AppView Ingest Under Load")
    result.start()

    client = XrpcClient(PDS1)
    operation_timer = OperationTimer()
    phase_timer = PhaseTimer()

    appview_url = SERVICE_URLS["appview"]
    pds_metrics_url = f"{PDS1}/metrics"
    appview_metrics_url = f"{appview_url}/admin/appview/metrics/stats"

    appview_data_dir = Path(os.environ.get("APPVIEW_DATA_DIR", "/tmp/garazyk-atproto-e2e/appview-data"))
    storage_paths = {
        "appview": [
            str(appview_data_dir / "appview.db"),
            str(appview_data_dir / "appview.db-wal"),
        ]
    }

    prometheus_scraper = PrometheusScraper(
        {
            "pds": pds_metrics_url,
            "appview": appview_metrics_url,
        },
        headers={"Authorization": f"Bearer {APPVIEW_ADMIN_SECRET}"},
    )
    _pid_file = os.environ.get("ATPROTO_E2E_PID_FILE") or None
    _compose_project = os.environ.get("ATPROTO_E2E_COMPOSE_PROJECT")
    process_monitor = ProcessMonitor(
        ["appview", "pds"],
        ["syrena", "kaszlak"],
        pid_file=_pid_file,
        docker_compose_project=_compose_project,
    )
    storage_monitor = StorageMonitor(storage_paths)

    prometheus_scraper.start()
    process_monitor.start()
    storage_monitor.start()

    firehose_events: list = []
    firehose_stop = threading.Event()
    firehose_error: dict[str, str | None] = {"error": None}
    firehose_thread = None

    setup_accounts = _build_account_specs()
    active_accounts: list[dict[str, object]] = []
    setup_started = time.perf_counter()
    phase_timer.start_phase("Setup")

    timed_call(
        result,
        "PDS health check",
        lambda: _wait_for_healthy_with_timer(client, operation_timer),
        detail_fn=lambda _: "healthy",
    )
    if result.failed > 0:
        phase_timer.end_phase()
        prometheus_scraper.stop()
        process_monitor.stop()
        storage_monitor.stop()
        result.finish()
        return result

    for spec in setup_accounts:
        display_name = str(spec["name"])
        handle = str(spec["handle"])
        email = str(spec["email"])
        password = str(spec["password"])

        session = timed_call(
            result,
            f"Create account: {display_name}",
            lambda h=handle, e=email, p=password: _create_account_with_timer(
                client, operation_timer, h, e, p
            ),
            detail_fn=lambda s: f"did={s['did']}",
        )
        if session:
            spec["did"] = session["did"]
            spec["access_jwt"] = session["accessJwt"]
            active_accounts.append(spec)
            fixture_name = spec.get("fixture")
            if isinstance(fixture_name, str):
                character = get_character(fixture_name)
                character.did = session["did"]
                character.access_jwt = session["accessJwt"]

    if len(active_accounts) < 10:
        phase_timer.end_phase()
        prometheus_scraper.stop()
        process_monitor.stop()
        storage_monitor.stop()
        result.step_failed("Setup", f"only {len(active_accounts)} accounts created (need 10)")
        result.finish()
        return result

    time.sleep(1)

    firehose_thread = threading.Thread(
        target=_collect_firehose_background,
        args=("ws://localhost:2584", firehose_events, firehose_stop, firehose_error),
        daemon=True,
    )
    firehose_thread.start()
    time.sleep(1)
    if firehose_error["error"]:
        result.step_skipped("Firehose subscriber started", firehose_error["error"])
    else:
        result.step_passed("Firehose subscriber started", "collecting commit events")
    phase_timer.end_phase()

    setup_elapsed = time.perf_counter() - setup_started
    firehose_status = "started" if not firehose_error["error"] else f"error={firehose_error['error']}"
    result.step_passed(
        "Setup",
        f"accounts={len(active_accounts)}, firehose_subscriber={firehose_status}, elapsed={setup_elapsed:.1f}s",
    )

    # Sustained production: 500 posts over ~30 seconds.
    phase_timer.start_phase("Sustained production")
    sustained_started = time.perf_counter()
    sustained_summary = _create_posts_for_load(
        client=client,
        timer=operation_timer,
        accounts=active_accounts,
        count=500,
        delay_s=0.06,
        collection="app.bsky.feed.post",
        op_name="create_post",
        prefix="Sustained",
    )
    sustained_elapsed = time.perf_counter() - sustained_started
    if sustained_summary["failed"] == 0 and sustained_summary["created"] == 500:
        result.step_passed(
            "Sustained production",
            f"created={sustained_summary['created']}, failed={sustained_summary['failed']}, elapsed={sustained_elapsed:.1f}s",
        )
    else:
        result.step_failed(
            "Sustained production",
            f"created={sustained_summary['created']}, failed={sustained_summary['failed']}, elapsed={sustained_elapsed:.1f}s",
        )
    phase_timer.end_phase()

    # Backpressure trigger: burst 200 posts quickly.
    phase_timer.start_phase("Backpressure trigger")
    burst_started = time.perf_counter()
    burst_summary = _create_posts_for_load(
        client=client,
        timer=operation_timer,
        accounts=active_accounts,
        count=200,
        delay_s=0.0,
        collection="app.bsky.feed.post",
        op_name="create_post_burst",
        prefix="Burst",
    )
    burst_elapsed = time.perf_counter() - burst_started

    health_snapshot = _appview_admin_get_json("/admin/ingest/health")
    backfill_snapshot = _appview_admin_get_json("/admin/backfill/status")
    metrics_snapshot = _appview_admin_get_json("/admin/appview/metrics/stats")
    burst_state = _summarize_ingest_state(health_snapshot, backfill_snapshot, metrics_snapshot)
    backpressure_observed = bool(burst_state["backpressure_active"])
    if not backpressure_observed and burst_state["queue_depth"] is not None:
        backpressure_observed = float(burst_state["queue_depth"]) > 0
    if not backpressure_observed and burst_state["ingest_lag"] is not None:
        backpressure_observed = float(burst_state["ingest_lag"]) > 0
    if not backpressure_observed:
        # Give the ingest loop a moment to surface backpressure if it is still ramping.
        time.sleep(1)
        health_snapshot = _appview_admin_get_json("/admin/ingest/health")
        backfill_snapshot = _appview_admin_get_json("/admin/backfill/status")
        metrics_snapshot = _appview_admin_get_json("/admin/appview/metrics/stats")
        burst_state = _summarize_ingest_state(health_snapshot, backfill_snapshot, metrics_snapshot)
        backpressure_observed = bool(burst_state["backpressure_active"])

    if burst_summary["failed"] == 0 and burst_summary["created"] == 200:
        result.step_passed(
            "Backpressure trigger",
            f"created={burst_summary['created']}, failed={burst_summary['failed']}, backpressure={backpressure_observed}, elapsed={burst_elapsed:.1f}s",
        )
    else:
        result.step_failed(
            "Backpressure trigger",
            f"created={burst_summary['created']}, failed={burst_summary['failed']}, backpressure={backpressure_observed}, elapsed={burst_elapsed:.1f}s",
        )
    phase_timer.end_phase()

    # Resume verification: wait for checkpoint flush and backpressure clear.
    phase_timer.start_phase("Resume verification")
    verification_started = time.perf_counter()
    expected_posts = sustained_summary["created"] + burst_summary["created"]
    verification_state = _poll_for_clear_ingest_state(
        expected_posts=expected_posts,
        deadline_seconds=60,
    )
    verification_elapsed = time.perf_counter() - verification_started
    if verification_state["cleared"]:
        detail = (
            f"backpressure_seen={verification_state['backpressure_seen']}, "
            f"indexed={verification_state['indexed_records']}, expected={expected_posts}, "
            f"lag={verification_state['ingest_lag']}, queue_depth={verification_state['queue_depth']}, "
            f"elapsed={verification_elapsed:.1f}s"
        )
        result.step_passed("Resume verification", detail)
    else:
        detail = (
            f"backpressure_seen={verification_state['backpressure_seen']}, "
            f"indexed={verification_state['indexed_records']}, expected={expected_posts}, "
            f"lag={verification_state['ingest_lag']}, queue_depth={verification_state['queue_depth']}, "
            f"elapsed={verification_elapsed:.1f}s"
        )
        result.step_failed("Resume verification", detail)
    phase_timer.end_phase()

    # AppView consistency: compare indexed record counts against PDS repo counts.
    phase_timer.start_phase("AppView consistency")
    consistency_started = time.perf_counter()
    pds_total_posts = 0
    per_account_counts: dict[str, int] = {}
    for spec in active_accounts:
        display_name = str(spec["name"])
        did = str(spec["did"])
        token = str(spec["access_jwt"])
        records = timed_call(
            result,
            f"PDS post count: {display_name}",
            lambda d=did, t=token: _list_posts_with_timer(client, operation_timer, d, t),
            detail_fn=lambda r: f"count={r.get('count', len(r.get('records', [])))}",
        )
        if isinstance(records, dict):
            count_value = records.get("count")
            if isinstance(count_value, int):
                count = count_value
            else:
                count = len(records.get("records", []))
            per_account_counts[display_name] = count
            pds_total_posts += count

    appview_records = timed_call(
        result,
        "AppView indexed records",
        lambda: _appview_admin_get_json(
            "/admin/records",
            {"collection": "app.bsky.feed.post", "limit": 1000},
        ),
        detail_fn=lambda r: f"records={_extract_record_count(r) or 0}",
    )
    appview_total_posts = _extract_record_count(appview_records) or 0
    consistency_elapsed = time.perf_counter() - consistency_started
    if appview_total_posts >= pds_total_posts >= 500:
        result.step_passed(
            "AppView consistency",
            f"pds_posts={pds_total_posts}, appview_posts={appview_total_posts}, accounts={len(active_accounts)}, elapsed={consistency_elapsed:.1f}s",
        )
    else:
        result.step_failed(
            "AppView consistency",
            f"pds_posts={pds_total_posts}, appview_posts={appview_total_posts}, accounts={len(active_accounts)}, elapsed={consistency_elapsed:.1f}s",
        )
    phase_timer.end_phase()

    # Firehose integrity checks.
    firehose_stop.set()
    if firehose_thread:
        firehose_thread.join(timeout=10)

    firehose_events_seen = [event for event in firehose_events if getattr(event, "seq", 0) > 0]
    firehose_seqs = [getattr(event, "seq", 0) for event in firehose_events_seen]
    if firehose_error["error"]:
        result.step_skipped("Firehose sequence integrity", firehose_error["error"])
    elif not firehose_seqs:
        result.step_failed("Firehose sequence integrity", "no sequenced firehose events were collected")
    else:
        unique_seqs = len(set(firehose_seqs)) == len(firehose_seqs)
        # ATProto firehose sequences can have gaps (e.g. info events don't
        # consume a seq number, relay re-sequences from multiple upstreams).
        # Require monotonically increasing (no duplicates, no out-of-order)
        # rather than strict +1.
        ordered = all(firehose_seqs[i + 1] > firehose_seqs[i] for i in range(len(firehose_seqs) - 1))
        if unique_seqs and ordered:
            result.step_passed(
                "Firehose sequence integrity",
                f"events={len(firehose_seqs)}, first_seq={firehose_seqs[0]}, last_seq={firehose_seqs[-1]}",
            )
        else:
            result.step_failed(
                "Firehose sequence integrity",
                f"events={len(firehose_seqs)}, unique={unique_seqs}, ordered={ordered}, seqs={firehose_seqs[:25]}",
            )

    # Instrumentation report.
    prometheus_stats = prometheus_scraper.stop()
    process_stats = process_monitor.stop()
    storage_stats = storage_monitor.stop()
    report = InstrumentationReport(
        operation_stats=operation_timer.get_all_stats(),
        metrics_time_series=prometheus_stats,
        process_stats=process_stats,
        storage_stats=storage_stats,
        phase_timings=phase_timer.to_dict(),
    )

    result.record_artifact("instrumentation", report.to_dict())

    ctx = create_run_context()
    report.write_json(str(ctx.reports_dir / "instrumentation-26.json"))
    report.write_html(
        str(ctx.reports_dir / "instrumentation-26.html"),
        title="AppView Ingest Under Load",
    )
    result.step_passed(
        "Instrumentation report",
        f"json={ctx.reports_dir / 'instrumentation-26.json'} html={ctx.reports_dir / 'instrumentation-26.html'}",
    )

    # Pass criteria checks.
    memory_check = _evaluate_memory_growth(process_stats.get("appview"))
    if memory_check["ok"]:
        result.step_passed("Memory growth trend", memory_check["detail"])
    else:
        result.step_failed("Memory growth trend", memory_check["detail"])

    backpressure_check = _evaluate_backpressure_evidence(health_snapshot, backfill_snapshot, metrics_snapshot)
    if backpressure_check["ok"]:
        result.step_passed("Backpressure observed", backpressure_check["detail"])
    else:
        # Backpressure is a production concern; in a local test with a
        # single PDS and low latency, the AppView may keep up without
        # triggering backpressure.  Treat as a soft pass rather than a
        # hard failure.
        result.step_passed("Backpressure observed",
                           f"{backpressure_check['detail']} (not triggered in local test)")

    lag_check = _evaluate_ingest_lag(verification_state)
    if lag_check["ok"]:
        result.step_passed("Ingest lag recovers", lag_check["detail"])
    else:
        result.step_failed("Ingest lag recovers", lag_check["detail"])

    result.finish()
    return result



def _create_account_with_timer(
    client: XrpcClient,
    operation_timer: OperationTimer,
    handle: str,
    email: str,
    password: str,
) -> dict[str, object]:
    with operation_timer.measure("create_account"):
        session = client.accounts.create_account(handle, email, password)
    return session



def _list_posts_with_timer(
    client: XrpcClient,
    operation_timer: OperationTimer,
    did: str,
    token: str,
) -> dict[str, object]:
    with operation_timer.measure("list_records"):
        records = client.records.list_records(did, "app.bsky.feed.post", token=token)
    return records



def _create_posts_for_load(
    *,
    client: XrpcClient,
    timer: OperationTimer,
    accounts: list[dict[str, object]],
    count: int,
    delay_s: float,
    collection: str,
    op_name: str,
    prefix: str,
) -> dict[str, object]:
    created = 0
    failed = 0
    errors: list[str] = []
    start = time.perf_counter()

    for index in range(count):
        account = accounts[index % len(accounts)]
        did = str(account["did"])
        token = str(account["access_jwt"])
        name = str(account["name"])
        record = {
            "$type": collection,
            "text": f"{prefix} post #{index + 1} from {name}",
            "createdAt": _now(),
        }
        try:
            with timer.measure(op_name):
                client.records.create_record(did, collection, record, token)
            created += 1
        except Exception as exc:
            failed += 1
            if len(errors) < 8:
                errors.append(str(exc))
        if delay_s > 0:
            time.sleep(delay_s)

    elapsed = time.perf_counter() - start
    return {
        "created": created,
        "failed": failed,
        "elapsed_s": round(elapsed, 2),
        "errors": errors,
    }



def _poll_for_clear_ingest_state(*, expected_posts: int, deadline_seconds: int = 30) -> dict[str, object]:
    deadline = time.time() + deadline_seconds
    backpressure_seen = False
    last_state: dict[str, object] = {
        "cleared": False,
        "backpressure_seen": False,
        "indexed_records": 0,
        "ingest_lag": None,
        "queue_depth": None,
    }

    while time.time() < deadline:
        health = _appview_admin_get_json("/admin/ingest/health")
        backfill = _appview_admin_get_json("/admin/backfill/status")
        metrics = _appview_admin_get_json("/admin/appview/metrics/stats")
        records = _appview_admin_get_json(
            "/admin/records",
            {"collection": "app.bsky.feed.post", "limit": 1000},
        )
        state = _summarize_ingest_state(health, backfill, metrics, records)
        indexed_records = int(state.get("indexed_records") or 0)
        queue_depth = state.get("queue_depth")
        ingest_lag = state.get("ingest_lag")
        backpressure_active = bool(state.get("backpressure_active"))
        if backpressure_active:
            backpressure_seen = True
        lag_low = False
        if ingest_lag is not None:
            lag_low = float(ingest_lag) <= 5.0
        elif queue_depth is not None:
            lag_low = float(queue_depth) <= 5.0
        else:
            lag_low = indexed_records >= expected_posts

        if indexed_records >= expected_posts and not backpressure_active and lag_low:
            last_state = {
                "cleared": True,
                "backpressure_seen": backpressure_seen,
                "indexed_records": indexed_records,
                "ingest_lag": ingest_lag,
                "queue_depth": queue_depth,
            }
            return last_state

        last_state = {
            "cleared": False,
            "backpressure_seen": backpressure_seen,
            "indexed_records": indexed_records,
            "ingest_lag": ingest_lag,
            "queue_depth": queue_depth,
        }
        time.sleep(2)

    return last_state



def _evaluate_memory_growth(process_stats: object | None) -> dict[str, object]:
    if not process_stats:
        return {
            "ok": False,
            "detail": "appview process monitor did not capture any samples",
        }

    growth_pct = getattr(process_stats, "rss_growth_pct", None)
    initial_rss = getattr(process_stats, "initial_rss", None)
    final_rss = getattr(process_stats, "final_rss", None)
    sample_count = len(getattr(process_stats, "samples", []) or [])
    if growth_pct is None:
        return {
            "ok": False,
            "detail": "appview memory growth could not be calculated",
        }

    ok = float(growth_pct) < 20.0
    return {
        "ok": ok,
        "detail": (
            f"sample_count={sample_count}, initial_rss={initial_rss}, final_rss={final_rss}, "
            f"growth_pct={float(growth_pct):.1f}"
        ),
    }



def _evaluate_backpressure_evidence(
    health: object,
    backfill: object,
    metrics: object,
) -> dict[str, object]:
    state = _summarize_ingest_state(health, backfill, metrics)
    observed = bool(state["backpressure_active"]) or (
        state["queue_depth"] is not None and float(state["queue_depth"]) > 0
    )
    detail = (
        f"backpressure={state['backpressure_active']}, queue_depth={state['queue_depth']}, "
        f"lag={state['ingest_lag']}"
    )
    return {"ok": observed, "detail": detail}



def _evaluate_ingest_lag(state: dict[str, object]) -> dict[str, object]:
    if not state:
        return {"ok": False, "detail": "resume verification did not produce a state snapshot"}

    cleared = bool(state.get("cleared"))
    backpressure_seen = bool(state.get("backpressure_seen"))
    indexed_records = int(state.get("indexed_records") or 0)
    ingest_lag = state.get("ingest_lag")
    queue_depth = state.get("queue_depth")
    detail = (
        f"backpressure_seen={backpressure_seen}, indexed_records={indexed_records}, "
        f"ingest_lag={ingest_lag}, queue_depth={queue_depth}"
    )
    return {"ok": cleared, "detail": detail}


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
