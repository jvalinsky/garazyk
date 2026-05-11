"""Scenario 43: "The Multi-Device User" — Multi-Device Session Management

Luna creates multiple sessions, verifies concurrent access,
deletes one session, and confirms the other is unaffected.

Services: PDS
"""

# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0

from __future__ import annotations

import sys
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import (
    XrpcClient, get_character, PDS1, ScenarioResult, timed_call,
    create_account_or_login,
)


def run() -> ScenarioResult:
    result = ScenarioResult("Multi-Device Session Management")
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
    luna.handle = session.get("handle", luna.handle)

    # Create session on "device 1"
    device1_session = timed_call(
        result, "Create session on device 1",
        lambda: pds.accounts.create_session(luna.handle, luna.password),
        detail_fn=lambda s: f"did={s.get('did', '?')}" if s else "failed",
    )

    # Create session on "device 2"
    device2_session = timed_call(
        result, "Create session on device 2",
        lambda: pds.accounts.create_session(luna.handle, luna.password),
        detail_fn=lambda s: f"did={s.get('did', '?')}" if s else "failed",
    )

    if not device1_session or not device2_session:
        result.finish()
        return result

    d1_token = device1_session["accessJwt"]
    d2_token = device2_session["accessJwt"]

    # Verify both sessions are valid
    timed_call(
        result, "Verify device 1 session valid",
        lambda: pds.accounts.get_session(d1_token),
        detail_fn=lambda s: f"did={s.get('did', '?')}" if s else "failed",
    )

    timed_call(
        result, "Verify device 2 session valid",
        lambda: pds.accounts.get_session(d2_token),
        detail_fn=lambda s: f"did={s.get('did', '?')}" if s else "failed",
    )

    # List sessions
    timed_call(
        result, "List sessions",
        lambda: pds.accounts.list_sessions(luna.access_jwt),
    )

    # Delete session from device 1
    timed_call(
        result, "Delete device 1 session",
        lambda: pds.accounts.delete_session(d1_token),
    )

    # Verify device 2 session is still valid
    timed_call(
        result, "Verify device 2 session still valid",
        lambda: pds.accounts.get_session(d2_token),
        detail_fn=lambda s: f"did={s.get('did', '?')}" if s else "failed",
    )

    # Verify device 1 session is no longer valid
    timed_call(
        result, "Verify device 1 session invalid",
        lambda: _expect_session_invalid(pds, d1_token),
        detail_fn=lambda invalid: f"invalid={invalid}",
    )

    result.finish()
    return result


def _expect_session_invalid(pds, token):
    """Return True if the session is invalid (expected after deletion)."""
    try:
        pds.accounts.get_session(token)
        return False  # Session still valid — unexpected
    except Exception:
        return True  # Session invalid — expected
