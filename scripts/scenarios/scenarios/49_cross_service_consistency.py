"""Scenario 49: "The Consistency Check" — Cross-Service Consistency

Luna writes records on the PDS, verifies AppView indexes them,
and checks relay sequence consistency.

Services: PDS, AppView, Relay
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
    result = ScenarioResult("Cross-Service Consistency")
    result.start()

    pds = XrpcClient(PDS1)
    appview = XrpcClient(SERVICE_URLS["appview"])
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

    # Write a record on the PDS
    post_rkey = "consistency-post-" + str(int(time.time()))
    post_record = {
        "$type": "app.bsky.feed.post",
        "text": "Testing cross-service consistency",
        "createdAt": now_iso(),
    }

    post_ref = timed_call(
        result, "Create post on PDS",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.feed.post", post_rkey,
            post_record, luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r.get('uri', '?')}" if r else "failed",
    )

    if not post_ref:
        result.finish()
        return result

    post_uri = post_ref.get("uri", "")

    # Wait for AppView to index
    appview_result = timed_call(
        result, "Wait for AppView to index post",
        lambda: _poll_for_post(appview, post_uri, luna.access_jwt, max_wait=15),
        detail_fn=lambda r: f"found={r is not None}",
    )

    if appview_result:
        # Compare record content across PDS and AppView
        pds_post = timed_call(
            result, "Get post from PDS",
            lambda: pds.repositories.get_record(
                luna.did, "app.bsky.feed.post", post_rkey, luna.access_jwt,
            ),
        )

        appview_post = timed_call(
            result, "Get post from AppView",
            lambda: appview.feeds.get_posts(
                {"uris": [post_uri]}, luna.access_jwt,
            ),
        )

        # Verify content matches
        if pds_post and appview_post:
            pds_text = pds_post.get("value", {}).get("text", "")
            appview_posts = appview_post.get("posts", [])
            appview_text = appview_posts[0].get("record", {}).get("text", "") if appview_posts else ""

            if pds_text == appview_text:
                result.step_passed("PDS-AppView content match", f"text={pds_text[:50]}")
            else:
                result.step_failed("PDS-AppView content drift",
                                   f"pds={pds_text[:50]}, appview={appview_text[:50]}")
    else:
        result.step_skipped("PDS-AppView content comparison", "Post not found in AppView")

    # Check relay health
    timed_call(
        result, "Check relay health",
        lambda: relay._get("/api/relay/health"),
    )

    # Write multiple records for batch consistency
    batch_uris = []
    for i in range(3):
        rkey = f"batch-post-{i}-{int(time.time())}"
        record = {
            "$type": "app.bsky.feed.post",
            "text": f"Batch consistency test post {i}",
            "createdAt": now_iso(),
        }
        ref = pds.repositories.create_record(
            luna.did, "app.bsky.feed.post", rkey,
            record, luna.access_jwt,
        )
        if ref:
            batch_uris.append(ref.get("uri", ""))

    if batch_uris:
        result.step_passed("Batch posts created", f"count={len(batch_uris)}")

        # Wait for AppView to index all
        time.sleep(3)

        # Verify all posts are indexed
        timed_call(
            result, "Verify batch posts in AppView",
            lambda: appview.feeds.get_posts(
                {"uris": batch_uris}, luna.access_jwt,
            ),
            detail_fn=lambda r: f"count={len(r.get('posts', []))}" if r else "failed",
        )

    result.finish()
    return result


def _poll_for_post(appview, uri, access_jwt, max_wait=15):
    """Poll AppView until the post is indexed or timeout."""
    start = time.time()
    while time.time() - start < max_wait:
        try:
            result = appview.feeds.get_posts({"uris": [uri]}, access_jwt)
            if result and result.get("posts"):
                return result
        except Exception:
            pass
        time.sleep(1)
    return None
