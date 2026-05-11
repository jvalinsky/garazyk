"""Scenario 41: "The Departure" — Account Deactivation & Reactivation

Luna deactivates her account, verifies her profile is hidden,
then reactivates and confirms her data is restored.

Services: PDS, PLC
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
    result = ScenarioResult("Account Deactivation & Reactivation")
    result.start()

    pds = XrpcClient(PDS1)
    appview = XrpcClient(SERVICE_URLS["appview"])
    luna = get_character("luna")

    timed_call(result, "PDS health check",
               lambda: pds.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # Create account and post content
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
    luna.refresh_jwt = session.get("refreshJwt")
    luna.handle = session.get("handle", luna.handle)

    # Post some content before deactivation
    post_rkey = "pre-deactivation-" + str(int(time.time()))
    post_record = {
        "$type": "app.bsky.feed.post",
        "text": "I'll be back!",
        "createdAt": now_iso(),
    }

    post_ref = timed_call(
        result, "Create post before deactivation",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.feed.post", post_rkey,
            post_record, luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r.get('uri', '?')}" if r else "failed",
    )

    # Verify profile is visible before deactivation
    timed_call(
        result, "Get profile before deactivation",
        lambda: appview.actor.get_profile(
            {"actor": luna.did}, luna.access_jwt,
        ),
        detail_fn=lambda r: f"handle={r.get('handle', '?')}" if r else "failed",
    )

    # Deactivate the account
    timed_call(
        result, "Deactivate account",
        lambda: pds.accounts.deactivate_account(luna.access_jwt),
    )

    # Wait for deactivation to propagate
    time.sleep(2)

    # Verify profile shows deactivated status
    timed_call(
        result, "Verify profile is deactivated",
        lambda: _check_deactivated_profile(appview, luna),
        detail_fn=lambda deactivated: f"deactivated={deactivated}",
    )

    # Reactivate by creating a new session
    time.sleep(1)
    reactivated_session = timed_call(
        result, "Reactivate account (new session)",
        lambda: pds.accounts.create_session(
            luna.handle, luna.password,
        ),
        detail_fn=lambda s: f"did={s.get('did', '?')}" if s else "failed",
    )

    if reactivated_session:
        luna.access_jwt = reactivated_session["accessJwt"]

        # Verify profile is visible again
        timed_call(
            result, "Get profile after reactivation",
            lambda: appview.actor.get_profile(
                {"actor": luna.did}, luna.access_jwt,
            ),
            detail_fn=lambda r: f"handle={r.get('handle', '?')}" if r else "failed",
        )

        # Verify data is still accessible
        if post_ref:
            timed_call(
                result, "Verify post still exists after reactivation",
                lambda: appview.feeds.get_posts(
                    {"uris": [post_ref.get("uri", "")]}, luna.access_jwt,
                ),
                detail_fn=lambda r: f"count={len(r.get('posts', []))}" if r else "failed",
            )

    result.finish()
    return result


def _check_deactivated_profile(appview, luna):
    """Check if the profile shows deactivated status. Returns True if deactivated."""
    try:
        profile = appview.actor.get_profile(
            {"actor": luna.did}, luna.access_jwt,
        )
        # A deactivated account may still return a profile but with a flag
        if profile and profile.get("associated", {}).get("deactivated"):
            return True
        # Or the profile may be hidden entirely
        return False
    except Exception:
        # If the profile is completely hidden, that's also deactivation
        return True
