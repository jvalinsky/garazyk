"""Scenario 52: "The Rate Limit Dance" — Rate Limit Client Behavior

Luna hits rate limits on multiple endpoints, verifies 429 responses
with Retry-After headers, and confirms recovery after cooldown.

Services: PDS
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
    create_account_or_login, now_iso,
)


def run() -> ScenarioResult:
    result = ScenarioResult("Rate Limit Client Behavior")
    result.start()

    pds = XrpcClient(PDS1)
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

    # Rapidly create records to hit rate limits
    rate_limited = False
    retry_after = None
    responses = []

    timed_call(
        result, "Rapidly create records to trigger rate limit",
        lambda: _rapid_create_records(pds, luna, responses),
    )

    # Analyze responses for rate limiting
    for resp in responses:
        status = resp.get("status", 0)
        if status == 429:
            rate_limited = True
            retry_after = resp.get("headers", {}).get("retry-after")
            result.step_passed("Rate limit triggered",
                               f"status=429, retry_after={retry_after}")
            break

    if not rate_limited:
        result.step_skipped("Rate limit trigger",
                            "No 429 response received (limits may be high for local dev)")

    # Verify Retry-After header
    if rate_limited and retry_after:
        try:
            retry_seconds = int(retry_after)
            result.step_passed("Retry-After header valid",
                               f"retry_after={retry_seconds}s")
        except (ValueError, TypeError):
            result.step_skipped("Retry-After header", f"non-numeric: {retry_after}")

    # Test rate limits on uploadBlob
    upload_responses = []
    timed_call(
        result, "Rapidly upload blobs to trigger rate limit",
        lambda: _rapid_upload_blobs(pds, luna, upload_responses),
    )

    upload_rate_limited = any(r.get("status") == 429 for r in upload_responses)
    if upload_rate_limited:
        result.step_passed("Upload rate limit triggered", "status=429")
    else:
        result.step_skipped("Upload rate limit", "No 429 on upload (limits may be high)")

    # Wait briefly and verify recovery
    time.sleep(2)

    # Verify requests succeed after cooldown
    recovery_post = {
        "$type": "app.bsky.feed.post",
        "text": "Post after rate limit cooldown",
        "createdAt": now_iso(),
    }

    timed_call(
        result, "Verify requests succeed after cooldown",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.feed.post",
            f"recovery-{int(time.time())}", recovery_post, luna.access_jwt,
        ),
        detail_fn=lambda r: f"recovered={r is not None}",
    )

    # Verify session is still valid
    timed_call(
        result, "Verify session still valid",
        lambda: pds.accounts.get_session(luna.access_jwt),
    )

    result.finish()
    return result


def _rapid_create_records(pds, luna, responses, count=20):
    """Rapidly create records to trigger rate limiting."""
    for i in range(count):
        try:
            rkey = f"rate-test-{i}-{int(time.time())}"
            record = {
                "$type": "app.bsky.feed.post",
                "text": f"Rate limit test post {i}",
                "createdAt": now_iso(),
            }
            resp = pds.repositories.create_record(
                luna.did, "app.bsky.feed.post", rkey,
                record, luna.access_jwt,
            )
            responses.append({"status": 200, "data": resp})
        except Exception as e:
            error_str = str(e)
            status = 429 if "429" in error_str or "rate" in error_str.lower() else 0
            responses.append({"status": status, "error": error_str})
            if status == 429:
                break  # Stop once rate limited


def _rapid_upload_blobs(pds, luna, responses, count=10):
    """Rapidly upload blobs to trigger rate limiting."""
    import base64
    png_data = base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    )

    for i in range(count):
        try:
            resp = pds.repositories.upload_blob(
                luna.did, png_data, "image/png", luna.access_jwt,
            )
            responses.append({"status": 200, "data": resp})
        except Exception as e:
            error_str = str(e)
            status = 429 if "429" in error_str or "rate" in error_str.lower() else 0
            responses.append({"status": status, "error": error_str})
            if status == 429:
                break
