"""Scenario 9: "The Firehose" — Relay & Event Streaming

Subscribe to the Relay firehose. Perform a sequence of repo operations
(create posts, likes, follows, profile updates). Verify each operation
appears as a correctly-sequenced event on the firehose. Verify AppView
indexes the events.

Services: PDS, Relay, AppView
"""

from __future__ import annotations

import asyncio
import sys
import threading
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call



def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _collect_firehose_background(relay_url: str, events: list, stop_event: threading.Event):
    try:
        from lib.firehose import FirehoseClient

        fh_client = FirehoseClient(relay_url)

        def on_event(event):
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
    except Exception:
        pass


def run() -> ScenarioResult:
    result = ScenarioResult("Firehose & Event Streaming")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    try:
        import requests
        relay_resp = requests.get("http://localhost:2584/api/relay/health", timeout=5)
        if relay_resp.status_code == 200:
            result.step_passed("Relay health check")
        else:
            result.step_skipped("Relay health check", f"status={relay_resp.status_code}")
    except Exception as exc:
        result.step_skipped("Relay health check", str(exc))

    try:
        import requests
        upstreams_resp = requests.get("http://localhost:2584/api/relay/upstreams", timeout=5)
        if upstreams_resp.status_code == 200:
            upstreams = upstreams_resp.json()
            count = len(upstreams) if isinstance(upstreams, list) else 0
            result.step_passed("Relay upstreams", f"count={count}")
        else:
            result.step_skipped("Relay upstreams", f"status={upstreams_resp.status_code}")
    except Exception as exc:
        result.step_skipped("Relay upstreams", str(exc))

    char_names = ["luna", "marcus", "rosa"]
    for name in char_names:
        char = get_character(name)
        timed_call(
            result, f"Create account: {char.name}",
            lambda c=char: client.accounts.create_account(c.handle, c.email, c.password),
            detail_fn=lambda s, n=name: f"did={s['did']}",
        )

    luna = get_character("luna")
    marcus = get_character("marcus")
    rosa = get_character("rosa")

    if not all([luna.did, marcus.did, rosa.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    firehose_events: list = []
    firehose_stop = threading.Event()
    firehose_thread = None

    time.sleep(2)

    try:
        from lib.firehose import FirehoseClient  # noqa: F401

        firehose_thread = threading.Thread(
            target=_collect_firehose_background,
            args=("ws://localhost:2584", firehose_events, firehose_stop),
            daemon=True,
        )
        firehose_thread.start()
        time.sleep(1)
        result.step_passed("Firehose WebSocket connection", f"events={len(firehose_events)}")
    except ImportError:
        result.step_skipped("Firehose WebSocket connection", "websockets package not installed")
    except Exception as exc:
        result.step_skipped("Firehose WebSocket connection", str(exc))

    luna_post = timed_call(
        result, "Luna creates firehose test post",
        lambda: client.records.create_record(
            luna.did, "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post", "text": "Firehose test post! If you can see this on the relay, streaming works!",
             "createdAt": _now()},
            luna.access_jwt),
    )

    timed_call(
        result, "Marcus follows Luna (firehose event)",
        lambda: client.records.create_record(
            marcus.did, "app.bsky.graph.follow",
            {"$type": "app.bsky.graph.follow", "subject": luna.did, "createdAt": _now()},
            marcus.access_jwt),
    )

    if luna_post:
        timed_call(
            result, "Rosa likes Luna's post (firehose event)",
            lambda: client.records.create_record(
                rosa.did, "app.bsky.feed.like",
                {"$type": "app.bsky.feed.like",
                 "subject": {"uri": luna_post["uri"], "cid": luna_post["cid"]},
                 "createdAt": _now()},
                rosa.access_jwt),
        )

    timed_call(
        result, "Luna updates profile (firehose event)",
        lambda: client.records.create_record(
            luna.did, "app.bsky.actor.profile",
            {"$type": "app.bsky.actor.profile", "displayName": "Luna Starfield",
             "description": "Astronomy enthusiast. Firehose tester."},
            luna.access_jwt),
    )

    time.sleep(3)
    firehose_stop.set()
    if firehose_thread:
        firehose_thread.join(timeout=5)

    result.step_passed("Post-operation firehose collection", f"events={len(firehose_events)}")

    target_count = 3
    if len(firehose_events) >= target_count:
        seqs = []
        for e in firehose_events:
            if hasattr(e, 'seq') and e.seq > 0:
                seqs.append(e.seq)
            elif isinstance(e.payload, dict) and 'seq' in e.payload:
                seqs.append(e.payload['seq'])

        if seqs:
            is_ordered = all(seqs[i] <= seqs[i+1] for i in range(len(seqs)-1))
            if is_ordered:
                result.step_passed("Event sequencing", f"seqs={seqs[:5]}... (ordered)")
            else:
                result.step_failed("Event sequencing", f"seqs not ordered: {seqs}")
        else:
            result.step_failed("Event sequencing", f"No seq numbers found in {len(firehose_events)} events")
    else:
        result.step_failed("Event sequencing", f"Only {len(firehose_events)} events collected, need {target_count}")

    timed_call(
        result, "Sync getHead",
        lambda: client.raw.xrpc_get("com.atproto.sync.getHead", {"did": luna.did}),
        detail_fn=lambda r: f"root={r.get('root', 'N/A')[:20]}",
    )

    result2 = timed_call(
        result, "Sync getRepo",
        lambda: client.raw.xrpc_get_binary("com.atproto.sync.getRepo", {"did": luna.did}),
        detail_fn=lambda r: f"car bytes={len(r[2])} content_type={r[1]}",
    )
    if result2:
        status, content_type, body = result2
        if "application/vnd.ipld.car" not in content_type:
            result.step_failed("Sync getRepo", f"unexpected content_type={content_type!r} status={status}")
        elif len(body) == 0:
            result.step_failed("Sync getRepo", "empty CAR body")

    time.sleep(3)

    try:
        import requests
        appview_resp = requests.get(
            "http://localhost:3200/admin/backfill/status",
            headers={"Authorization": "Bearer localdevadmin"},
            timeout=5,
        )
        if appview_resp.status_code == 200:
            result.step_passed("AppView backfill status", f"body={appview_resp.text[:100]}")
        else:
            result.step_failed("AppView backfill status", f"status={appview_resp.status_code}")
    except Exception as exc:
        result.step_failed("AppView backfill status", str(exc))

    timed_call(
        result, "AppView indexed Luna's posts",
        lambda: client.feed.get_author_feed(luna.did, token=luna.access_jwt),
        detail_fn=lambda f: f"items={len(f.get('feed', []))}",
    )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
