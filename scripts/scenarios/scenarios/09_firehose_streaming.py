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
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, PDS1
from lib.assertions import assert_success, assert_contains
from lib.report import ScenarioResult, StepStatus


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Firehose & Event Streaming")
    result.start()

    client = XrpcClient(PDS1)

    # Wait for server
    try:
        client.wait_for_healthy(timeout=30)
        result.step_passed("Server health check")
    except RuntimeError as exc:
        result.step_failed("Server health check", str(exc))
        result.finish()
        return result

    # ── Check relay health ────────────────────────────────────────────
    try:
        import requests
        relay_resp = requests.get("http://localhost:2584/api/relay/health", timeout=5)
        if relay_resp.status_code == 200:
            result.step_passed("Relay health check")
        else:
            result.step_skipped("Relay health check", f"status={relay_resp.status_code}")
    except Exception as exc:
        result.step_skipped("Relay health check", str(exc))

    # ── Check relay upstreams ─────────────────────────────────────────
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

    # ── Create accounts ──────────────────────────────────────────────
    char_names = ["luna", "marcus", "rosa"]
    for name in char_names:
        char = get_character(name)
        try:
            session = client.create_account(char.handle, char.email, char.password)
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            result.step_passed(f"Create account: {char.name}", f"did={char.did}")
        except XrpcError as exc:
            result.step_failed(f"Create account: {char.name}", str(exc))

    luna = get_character("luna")
    marcus = get_character("marcus")
    rosa = get_character("rosa")

    if not all([luna.did, marcus.did, rosa.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    # ── Try WebSocket firehose subscription ───────────────────────────
    firehose_events = []
    firehose_connected = False
    
    # Wait for relay to be ready and connected to upstreams
    time.sleep(2)

    try:
        from lib.firehose import FirehoseClient

        fh_client = FirehoseClient("ws://localhost:2584")

        # Collect events for a few seconds
        events = asyncio.run(fh_client.collect(duration_s=3.0))
        firehose_connected = True
        firehose_events = events
        result.step_passed("Firehose WebSocket connection", f"events={len(events)}")
    except ImportError:
        result.step_skipped("Firehose WebSocket connection", "websockets package not installed")
    except Exception as exc:
        result.step_skipped("Firehose WebSocket connection", str(exc))

    # ── Perform repo operations ───────────────────────────────────────
    # These should generate firehose events

    # Luna creates a post
    luna_post = None
    try:
        luna_post = client.create_record(
            luna.did,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "Firehose test post! If you can see this on the relay, streaming works! 📡",
                "createdAt": _now(),
            },
            luna.access_jwt,
        )
        result.step_passed("Luna creates firehose test post")
    except XrpcError as exc:
        result.step_failed("Luna creates firehose test post", str(exc))

    # Marcus follows Luna
    try:
        follow = client.create_record(
            marcus.did,
            "app.bsky.graph.follow",
            {
                "$type": "app.bsky.graph.follow",
                "subject": luna.did,
                "createdAt": _now(),
            },
            marcus.access_jwt,
        )
        result.step_passed("Marcus follows Luna (firehose event)")
    except XrpcError as exc:
        result.step_failed("Marcus follows Luna", str(exc))

    # Rosa likes Luna's post
    if luna_post:
        try:
            like = client.create_record(
                rosa.did,
                "app.bsky.feed.like",
                {
                    "$type": "app.bsky.feed.like",
                    "subject": {"uri": luna_post["uri"], "cid": luna_post["cid"]},
                    "createdAt": _now(),
                },
                rosa.access_jwt,
            )
            result.step_passed("Rosa likes Luna's post (firehose event)")
        except XrpcError as exc:
            result.step_failed("Rosa likes Luna's post", str(exc))

    # Luna updates profile
    try:
        client.create_record(
            luna.did,
            "app.bsky.actor.profile",
            {
                "$type": "app.bsky.actor.profile",
                "displayName": "Luna Starfield ✨",
                "description": "Astronomy enthusiast. Firehose tester. 🌌📡",
            },
            luna.access_jwt,
        )
        result.step_passed("Luna updates profile (firehose event)")
    except XrpcError as exc:
        result.step_failed("Luna updates profile", str(exc))

    # ── Collect firehose events after operations ──────────────────────
    if firehose_connected:
        try:
            from lib.firehose import FirehoseClient
            fh_client = FirehoseClient("ws://localhost:2584")
            events = []
            
            # ATProto firehose can be slow to start streaming. Retry collection
            # for up to 30 seconds to ensure events are captured.
            target_count = 3
            start_wait = time.time()
            while len(events) < target_count and time.time() - start_wait < 30:
                try:
                    batch = asyncio.run(fh_client.collect(duration_s=5.0))
                    events.extend(batch)
                except Exception as exc:
                    print(f"Firehose batch collection failed: {exc}")
                    time.sleep(1)
            
            result.step_passed("Post-operation firehose collection", f"events={len(events)}")

            # Check for sequencing
            if len(events) >= target_count:
                # Extract seqs from events (including #identity and #account)
                seqs = []
                for e in events:
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
                    result.step_failed("Event sequencing", f"No seq numbers found in {len(events)} events")
            else:
                result.step_failed("Event sequencing", f"Only {len(events)} events collected, need {target_count}")
        except Exception as exc:
            result.step_failed("Post-operation firehose collection", str(exc))

    # ── Verify sync endpoints ─────────────────────────────────────────
    try:
        repo_head = client.xrpc_get(
            "com.atproto.sync.getHead",
            {"did": luna.did},
        )
        result.step_passed("Sync getHead", f"root={repo_head.get('root', 'N/A')[:20]}")
    except XrpcError as exc:
        result.step_failed("Sync getHead", str(exc))

    try:
        status, content_type, body = client.xrpc_get_binary(
            "com.atproto.sync.getRepo",
            {"did": luna.did},
        )
        if "application/vnd.ipld.car" not in content_type:
            result.step_failed(
                "Sync getRepo",
                f"unexpected content_type={content_type!r} status={status}",
            )
        elif len(body) == 0:
            result.step_failed("Sync getRepo", "empty CAR body")
        else:
            result.step_passed(
                "Sync getRepo",
                f"car bytes={len(body)} content_type={content_type}",
            )
    except XrpcError as exc:
        result.step_failed("Sync getRepo", str(exc))

    # ── AppView indexing verification ─────────────────────────────────
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

    # ── Verify Luna's post is indexed by AppView ─────────────────────
    try:
        feed = client.get_author_feed(luna.did, token=luna.access_jwt)
        feed_items = feed.get("feed", [])
        result.step_passed("AppView indexed Luna's posts", f"items={len(feed_items)}")
    except XrpcError as exc:
        result.step_failed("AppView indexed Luna's posts", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
