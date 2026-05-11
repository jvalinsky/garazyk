"""Scenario 40: "The Gated Conversation" — Thread Gating & Reply Controls

Luna creates posts with various reply restrictions and verifies
that unauthorized replies are rejected.

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
    result = ScenarioResult("Thread Gating & Reply Controls")
    result.start()

    pds = XrpcClient(PDS1)
    appview = XrpcClient(SERVICE_URLS["appview"])
    luna = get_character("luna")
    bob = get_character("bob")

    timed_call(result, "PDS health check",
               lambda: pds.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # Create accounts
    luna_session = timed_call(
        result, "Create account for Luna",
        lambda: create_account_or_login(pds, luna),
        detail_fn=lambda s: f"did={s.get('did', '?')}",
    )
    bob_session = timed_call(
        result, "Create account for Bob",
        lambda: create_account_or_login(pds, bob),
        detail_fn=lambda s: f"did={s.get('did', '?')}",
    )

    if not luna_session or not bob_session:
        result.finish()
        return result

    luna.did = luna_session["did"]
    luna.access_jwt = luna_session["accessJwt"]
    bob.did = bob_session["did"]
    bob.access_jwt = bob_session["accessJwt"]

    # Post 1: Nobody can reply
    gated_post_rkey = "post-nobody-" + str(int(time.time()))
    gated_post = {
        "$type": "app.bsky.feed.post",
        "text": "This post has no replies allowed",
        "createdAt": now_iso(),
    }

    gated_ref = timed_call(
        result, "Create post with no-reply gate",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.feed.post", gated_post_rkey,
            gated_post, luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r.get('uri', '?')}" if r else "failed",
    )

    if gated_ref:
        gated_uri = gated_ref.get("uri", "")
        gated_cid = gated_ref.get("cid", "")

        # Create the thread gate record
        gate_rkey = "gate-" + str(int(time.time()))
        gate_record = {
            "$type": "app.bsky.feed.threadgate",
            "post": gated_uri,
            "allow": [],  # Empty allow = nobody can reply
            "createdAt": now_iso(),
        }

        timed_call(
            result, "Create thread gate (nobody)",
            lambda: pds.repositories.create_record(
                luna.did, "app.bsky.feed.threadgate", gate_rkey,
                gate_record, luna.access_jwt,
            ),
        )

        # Bob tries to reply — should be rejected
        reply_rkey = "reply-rejected-" + str(int(time.time()))
        reply_record = {
            "$type": "app.bsky.feed.post",
            "text": "This reply should be rejected",
            "createdAt": now_iso(),
            "reply": {
                "root": {"uri": gated_uri, "cid": gated_cid},
                "parent": {"uri": gated_uri, "cid": gated_cid},
            },
        }

        timed_call(
            result, "Verify Bob's reply rejected (nobody gate)",
            lambda: _expect_reply_rejected(pds, bob, reply_rkey, reply_record),
            detail_fn=lambda ok: "rejected" if ok else "unexpectedly accepted",
        )

    # Post 2: Followers only
    followers_post_rkey = "post-followers-" + str(int(time.time()))
    followers_post = {
        "$type": "app.bsky.feed.post",
        "text": "Only followers can reply",
        "createdAt": now_iso(),
    }

    followers_ref = timed_call(
        result, "Create post with followers-only gate",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.feed.post", followers_post_rkey,
            followers_post, luna.access_jwt,
        ),
    )

    if followers_ref:
        f_uri = followers_ref.get("uri", "")
        f_cid = followers_ref.get("cid", "")
        gate_rkey2 = "gate-followers-" + str(int(time.time()))
        gate_record2 = {
            "$type": "app.bsky.feed.threadgate",
            "post": f_uri,
            "allow": [{"$type": "app.bsky.feed.threadgate#followerRule"}],
            "createdAt": now_iso(),
        }

        timed_call(
            result, "Create thread gate (followers only)",
            lambda: pds.repositories.create_record(
                luna.did, "app.bsky.feed.threadgate", gate_rkey2,
                gate_record2, luna.access_jwt,
            ),
        )

    # Post 3: Mention only
    mention_post_rkey = "post-mention-" + str(int(time.time()))
    mention_post = {
        "$type": "app.bsky.feed.post",
        "text": "Only mentioned users can reply",
        "createdAt": now_iso(),
    }

    mention_ref = timed_call(
        result, "Create post with mention-only gate",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.feed.post", mention_post_rkey,
            mention_post, luna.access_jwt,
        ),
    )

    if mention_ref:
        m_uri = mention_ref.get("uri", "")
        gate_rkey3 = "gate-mention-" + str(int(time.time()))
        gate_record3 = {
            "$type": "app.bsky.feed.threadgate",
            "post": m_uri,
            "allow": [{"$type": "app.bsky.feed.threadgate#mentionRule"}],
            "createdAt": now_iso(),
        }

        timed_call(
            result, "Create thread gate (mention only)",
            lambda: pds.repositories.create_record(
                luna.did, "app.bsky.feed.threadgate", gate_rkey3,
                gate_record3, luna.access_jwt,
            ),
        )

    # Verify thread gates via AppView
    time.sleep(1)
    if gated_ref:
        timed_call(
            result, "Get thread with gate from AppView",
            lambda: appview.feeds.get_post_thread(
                {"uri": gated_ref.get("uri", "")}, luna.access_jwt,
            ),
        )

    result.finish()
    return result


def _expect_reply_rejected(pds, bob, rkey, record):
    """Return True if the reply is rejected (expected), False if accepted."""
    try:
        resp = pds.repositories.create_record(
            bob.did, "app.bsky.feed.post", rkey,
            record, bob.access_jwt,
        )
        # If we get here, the reply was accepted — that's unexpected
        # Try to clean up
        try:
            pds.repositories.delete_record(
                bob.did, "app.bsky.feed.post", rkey, bob.access_jwt,
            )
        except Exception:
            pass
        return False
    except Exception:
        # Reply was rejected — expected behavior
        return True
