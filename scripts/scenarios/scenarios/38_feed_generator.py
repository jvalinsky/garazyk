"""Scenario 38: "The Curator's Workshop" — Feed Generator Lifecycle

Luna creates a feed generator, verifies AppView indexes it, and
subscribes to the custom feed.

Services: PDS, AppView
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
    result = ScenarioResult("Feed Generator Lifecycle")
    result.start()

    pds = XrpcClient(PDS1)
    appview = XrpcClient(SERVICE_URLS["appview"])
    luna = get_character("luna")

    timed_call(result, "PDS health check",
               lambda: pds.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

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

    # Create a feed generator record
    feed_gen_did = luna.did  # Self-hosted generator for testing
    feed_rkey = "test-feed-" + str(int(time.time()))

    feed_record = {
        "$type": "app.bsky.feed.generator",
        "did": feed_gen_did,
        "displayName": "Luna's Test Feed",
        "description": "A curated feed for testing feed generator lifecycle",
        "createdAt": now_iso(),
    }

    feed_ref = timed_call(
        result, "Create feed generator record",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.feed.generator", feed_rkey,
            feed_record, luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r.get('uri', '?')}" if r else "failed",
    )

    if not feed_ref:
        result.finish()
        return result

    feed_uri = feed_ref.get("uri", "")

    # Wait for AppView to index
    time.sleep(2)

    # Verify AppView indexes the generator
    timed_call(
        result, "Get feed generator from AppView",
        lambda: appview.feeds.get_feed_generator(
            {"feed": feed_uri}, luna.access_jwt,
        ),
        detail_fn=lambda r: f"viewing={r.get('view', {}).get('displayName', '?')}" if r else "not found",
    )

    # List feed generators
    timed_call(
        result, "Get feed generators",
        lambda: appview.feeds.get_feed_generators(
            {"feeds": [feed_uri]}, luna.access_jwt,
        ),
        detail_fn=lambda r: f"count={len(r.get('generators', []))}" if r else "failed",
    )

    # Subscribe to the custom feed
    timed_call(
        result, "Get custom feed",
        lambda: appview.feeds.get_feed(
            {"feed": feed_uri, "limit": 10}, luna.access_jwt,
        ),
        detail_fn=lambda r: f"cursor={r.get('cursor', 'none')}" if r else "failed",
    )

    # Get feed suggestions
    timed_call(
        result, "Get feed suggestions",
        lambda: appview.feeds.get_suggestions(
            {"limit": 10}, luna.access_jwt,
        ),
    )

    result.finish()
    return result
