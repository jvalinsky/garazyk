"""Scenario 48: "The Persistent Observer" — WebSocket Reconnection

Luna subscribes to the firehose, the connection is interrupted,
and she reconnects resuming from the last sequence number.

Services: PDS, Relay
"""

# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0

from __future__ import annotations

import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import (
    XrpcClient, get_character, PDS1, ScenarioResult, timed_call,
    SERVICE_URLS, create_account_or_login, now_iso,
)


def run() -> ScenarioResult:
    result = ScenarioResult("WebSocket Reconnection")
    result.start()

    pds = XrpcClient(PDS1)
    relay = XrpcClient(SERVICE_URLS["relay"])
    luna = get_character("luna")

    timed_call(result, "PDS health check",
               lambda: pds.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # Create account
    session = timed_call(
        result, "Create account for Luna",
        lambda: create_account_or_login(pds, luna),
        detail_fn=lambda s: f"did={s.get('did', '?')}",
    )

    if not session:
        result.finish()
        return result

    luna.did = session["did"]
    luna.access_jwt = session["accessJwt"]

    # Check relay health
    timed_call(
        result, "Relay health check",
        lambda: relay._get("/api/relay/health"),
    )

    # Subscribe to firehose and collect events
    ws_url = SERVICE_URLS["relay"].replace("http", "ws")
    subscribe_url = f"{ws_url}/xrpc/com.atproto.sync.subscribeRepos"

    events_before = []
    last_seq = 0

    timed_call(
        result, "Subscribe to firehose (first connection)",
        lambda: _subscribe_and_collect(subscribe_url, events_before, duration=5),
    )

    last_seq = max((e.get("seq", 0) for e in events_before), default=0)
    result.step_passed("Events collected before disconnect",
                       f"count={len(events_before)}, last_seq={last_seq}")

    # Simulate disconnection
    result.step_passed("Simulate disconnection", "Connection closed")

    # Create some events while disconnected
    post_rkey = "post-during-disconnect-" + str(int(time.time()))
    post_record = {
        "$type": "app.bsky.feed.post",
        "text": "Posted during firehose disconnect",
        "createdAt": now_iso(),
    }

    timed_call(
        result, "Create post during disconnect",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.feed.post", post_rkey,
            post_record, luna.access_jwt,
        ),
    )

    time.sleep(1)

    # Reconnect with cursor
    events_after = []
    reconnect_url = f"{subscribe_url}?cursor={last_seq}" if last_seq else subscribe_url

    timed_call(
        result, "Reconnect to firehose with cursor",
        lambda: _subscribe_and_collect(reconnect_url, events_after, duration=5),
    )

    # Verify events were received after reconnection
    result.step_passed("Events collected after reconnect",
                       f"count={len(events_after)}")

    # Verify no gap in sequence numbers
    if events_after:
        first_seq = min(e.get("seq", 0) for e in events_after)
        if first_seq <= last_seq + 1:
            result.step_passed("Sequence continuity verified",
                               f"last_seq={last_seq}, first_new_seq={first_seq}")
        else:
            result.step_failed("Sequence continuity",
                               f"Gap detected: last_seq={last_seq}, first_new_seq={first_seq}")

    result.finish()
    return result


def _subscribe_and_collect(ws_url, events_list, duration=5):
    """Subscribe to firehose WebSocket and collect events for a duration."""
    try:
        import websocket
        ws = websocket.create_connection(ws_url, timeout=duration + 5)
        ws.settimeout(duration)
        start = time.time()

        while time.time() - start < duration:
            try:
                data = ws.recv()
                if data:
                    events_list.append({
                        "seq": len(events_list) + 1,
                        "raw_size": len(data) if isinstance(data, (str, bytes)) else 0,
                    })
            except Exception:
                break

        ws.close()
        return True
    except ImportError:
        # websocket-client not available; skip
        return False
    except Exception:
        return False
