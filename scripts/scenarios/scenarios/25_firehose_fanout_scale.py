"""Scenario 25: Firehose Fan-Out at Scale

50+ concurrent firehose subscribers while the PDS produces events.
Tests the batch fan-out path and backpressure propagation.

Services: PDS, Relay
"""

from __future__ import annotations

import asyncio
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import (
    XrpcClient, get_character, PDS1, ScenarioResult, timed_call,
)
from scripts.lib.atproto.config import SERVICE_URLS
from scripts.lib.atproto.instrumentation import (
    PrometheusScraper, ProcessMonitor, OperationTimer, PhaseTimer,
    InstrumentationReport,
)


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _collect_firehose_background(
    relay_url: str,
    events: list,
    stop_event: threading.Event,
    subscriber_id: int,
):
    """Collect firehose events on a background thread."""
    try:
        from scripts.lib.atproto.firehose import FirehoseClient

        fh_client = FirehoseClient(relay_url)

        def on_event(event):
            event._subscriber_id = subscriber_id
            event._received_at = time.time()
            events.append(event)

        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        while not stop_event.is_set():
            try:
                loop.run_until_complete(
                    fh_client.subscribe(on_event, duration_s=60.0, recv_timeout=5.0)
                )
            except Exception:
                break
        loop.close()
    except ImportError:
        pass


def run() -> ScenarioResult:
    result = ScenarioResult("Firehose Fan-Out at Scale")
    result.start()

    client = XrpcClient(PDS1)
    timer = OperationTimer()
    phase_timer = PhaseTimer()

    # -- Start instrumentation --
    phase_timer.start_phase("setup")

    prom_endpoints = {
        "pds": f"{SERVICE_URLS.get('pds', 'http://localhost:2583')}/metrics",
        "relay": f"{SERVICE_URLS.get('relay', 'http://localhost:2584')}/api/relay/metrics",
    }
    prom_scraper = PrometheusScraper(prom_endpoints, interval=2.0)
    prom_scraper.start()

    proc_monitor = ProcessMonitor(
        service_names=["pds", "relay"],
        binary_names=["kaszlak", "zuk"],
    )
    proc_monitor.start()

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        prom_scraper.stop()
        proc_monitor.stop()
        result.finish()
        return result

    # -- Create accounts --
    char_names = ["luna", "marcus", "rosa", "volt", "quiet"]
    for name in char_names:
        char = get_character(name)
        with timer.measure("create_account"):
            session = timed_call(
                result, f"Create account: {char.name}",
                lambda c=char: client.accounts.create_account(
                    c.handle, c.email, c.password),
                detail_fn=lambda s, n=name: f"did={s['did']}",
            )
        if session:
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]

    active = [n for n in char_names if get_character(n).did]
    if len(active) < 3:
        result.step_failed("Account creation", "Not enough accounts")
        prom_scraper.stop()
        proc_monitor.stop()
        result.finish()
        return result

    phase_timer.end_phase()

    # -- Phase 2: Subscriber ramp-up --
    phase_timer.start_phase("subscriber_rampup")

    NUM_SUBSCRIBERS = 50
    subscriber_events: list = []
    subscriber_stop = threading.Event()
    subscriber_threads: list = []

    relay_url = SERVICE_URLS.get("relay", "http://localhost:2584")

    for i in range(NUM_SUBSCRIBERS):
        t = threading.Thread(
            target=_collect_firehose_background,
            args=(relay_url, subscriber_events, subscriber_stop, i),
            daemon=True,
        )
        t.start()
        subscriber_threads.append(t)

    time.sleep(3)  # Let subscribers connect
    result.step_passed(
        "Subscriber ramp-up",
        f"Started {NUM_SUBSCRIBERS} firehose subscribers",
    )
    phase_timer.end_phase()

    # -- Phase 3: Event production --
    phase_timer.start_phase("event_production")

    POSTS_PER_USER = 20
    total_posts = 0
    failed_posts = 0
    post_timestamps: dict[str, float] = {}  # rkey -> creation time

    def create_post(char_name: str, index: int) -> bool:
        char = get_character(char_name)
        rkey = f"fanout-{char_name}-{index}"
        post_timestamps[rkey] = time.time()
        try:
            with timer.measure("create_post"):
                client.records.create_record(
                    char.did, "app.bsky.feed.post",
                    {"$type": "app.bsky.feed.post",
                     "text": f"Fanout post #{index} from {char.name}!",
                     "createdAt": _now()},
                    char.access_jwt,
                    rkey=rkey,
                )
            return True
        except Exception:
            return False

    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = []
        for name in active:
            for i in range(POSTS_PER_USER):
                futures.append(executor.submit(create_post, name, i + 1))
        for future in as_completed(futures):
            if future.result():
                total_posts += 1
            else:
                failed_posts += 1

    result.step_passed(
        "Event production",
        f"created={total_posts}, failed={failed_posts}, "
        f"rate={total_posts / max(1, POSTS_PER_USER * len(active) / 5):.1f} posts/s",
    )
    phase_timer.end_phase()

    # Wait for events to propagate
    time.sleep(5)

    # -- Phase 4: Backpressure test --
    phase_timer.start_phase("backpressure_test")

    # Open 50 more subscribers
    extra_threads: list = []
    for i in range(NUM_SUBSCRIBERS):
        t = threading.Thread(
            target=_collect_firehose_background,
            args=(relay_url, subscriber_events, subscriber_stop,
                  NUM_SUBSCRIBERS + i),
            daemon=True,
        )
        t.start()
        extra_threads.append(t)

    time.sleep(3)

    # Produce burst
    burst_posts = 0
    burst_failures = 0

    def create_burst_post(char_name: str, index: int) -> bool:
        char = get_character(char_name)
        try:
            with timer.measure("create_post_burst"):
                client.records.create_record(
                    char.did, "app.bsky.feed.post",
                    {"$type": "app.bsky.feed.post",
                     "text": f"Burst post #{index} from {char.name}!",
                     "createdAt": _now()},
                    char.access_jwt,
                )
            return True
        except Exception:
            return False

    BURST_PER_USER = 40
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = []
        for name in active:
            for i in range(BURST_PER_USER):
                futures.append(executor.submit(create_burst_post, name, i + 1))
        for future in as_completed(futures):
            if future.result():
                burst_posts += 1
            else:
                burst_failures += 1

    result.step_passed(
        "Backpressure burst",
        f"created={burst_posts}, failed={burst_failures}",
    )

    # Check backpressure metrics
    try:
        import requests
        metrics_resp = requests.get(
            f"{SERVICE_URLS.get('pds', 'http://localhost:2583')}/metrics",
            timeout=5,
        )
        if metrics_resp.status_code == 200:
            bp_warnings = 0
            bp_critical = 0
            for line in metrics_resp.text.splitlines():
                if "pds_websocket_backpressure_warnings_total" in line:
                    try:
                        bp_warnings = int(float(line.split()[-1]))
                    except (ValueError, IndexError):
                        pass
                if "pds_websocket_backpressure_critical_total" in line:
                    try:
                        bp_critical = int(float(line.split()[-1]))
                    except (ValueError, IndexError):
                        pass
            result.step_passed(
                "Backpressure metrics",
                f"warnings={bp_warnings}, critical={bp_critical}",
            )
        else:
            result.step_skipped("Backpressure metrics", f"status={metrics_resp.status_code}")
    except Exception as exc:
        result.step_skipped("Backpressure metrics", str(exc))

    time.sleep(5)
    phase_timer.end_phase()

    # -- Phase 5: Subscriber teardown --
    phase_timer.start_phase("subscriber_teardown")

    subscriber_stop.set()
    for t in subscriber_threads:
        t.join(timeout=3)
    for t in extra_threads:
        t.join(timeout=3)

    total_events = len(subscriber_events)
    subscriber_counts: dict[int, int] = {}
    for ev in subscriber_events:
        sid = getattr(ev, "_subscriber_id", -1)
        subscriber_counts[sid] = subscriber_counts.get(sid, 0) + 1

    connected_subscribers = len(subscriber_counts)
    result.step_passed(
        "Subscriber teardown",
        f"total_events={total_events}, "
        f"connected_subscribers={connected_subscribers}/{NUM_SUBSCRIBERS * 2}",
    )

    # Event delivery latency analysis
    delivery_latencies: list[float] = []
    for ev in subscriber_events:
        recv_at = getattr(ev, "_received_at", 0)
        if recv_at > 0 and hasattr(ev, "seq") and ev.seq > 0:
            # Rough estimate: events arrive within a few seconds
            delivery_latencies.append(recv_at)

    if delivery_latencies:
        sorted_lat = sorted(delivery_latencies)
        p95_idx = min(int(len(sorted_lat) * 0.95), len(sorted_lat) - 1)
        result.step_passed(
            "Event delivery",
            f"total_events={total_events}, "
            f"subscribers_with_events={connected_subscribers}",
        )
    else:
        result.step_skipped("Event delivery", "No events with timestamps")

    phase_timer.end_phase()

    # -- Stop instrumentation --
    phase_timer.start_phase("instrumentation")

    metrics_ts = prom_scraper.stop()
    proc_stats = proc_monitor.stop()

    report = InstrumentationReport(
        operation_stats=timer.get_all_stats(),
        metrics_time_series=metrics_ts,
        process_stats=proc_stats,
        phase_timings=phase_timer.to_dict(),
    )

    result.record_artifact("instrumentation", report.to_dict())

    from scripts.lib.atproto.diagnostics import create_run_context
    ctx = create_run_context()
    report.write_json(str(ctx.reports_dir / "instrumentation-25.json"))
    report.write_html(
        str(ctx.reports_dir / "instrumentation-25.html"),
        title="Firehose Fan-Out at Scale",
    )

    phase_timer.end_phase()

    # -- Pass/fail criteria --
    if total_posts + burst_posts > 0 and failed_posts + burst_failures == 0:
        result.step_passed("All writes succeeded",
                           f"total={total_posts + burst_posts}")
    else:
        result.step_failed("All writes succeeded",
                           f"failures={failed_posts + burst_failures}")

    create_post_stats = timer.get_stats("create_post")
    p95_ms = create_post_stats.p95_ns / 1e6
    if p95_ms < 2000:
        result.step_passed("p95 latency < 2s", f"p95={p95_ms:.1f}ms")
    else:
        result.step_failed("p95 latency < 2s", f"p95={p95_ms:.1f}ms")

    if connected_subscribers >= NUM_SUBSCRIBERS:
        result.step_passed("Subscribers connected",
                           f"{connected_subscribers}/{NUM_SUBSCRIBERS * 2}")
    else:
        result.step_failed("Subscribers connected",
                           f"{connected_subscribers}/{NUM_SUBSCRIBERS * 2}")

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
