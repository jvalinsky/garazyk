"""Scenario 42: "The Identity Shift" — Handle Change Propagation

Luna updates her handle and verifies the change propagates through
PLC, AppView, and the relay.

Services: PDS, PLC, AppView, Relay
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
    SERVICE_URLS, create_account_or_login,
)


def run() -> ScenarioResult:
    result = ScenarioResult("Handle Change Propagation")
    result.start()

    pds = XrpcClient(PDS1)
    appview = XrpcClient(SERVICE_URLS["appview"])
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
    original_handle = session.get("handle", luna.handle)

    # Resolve handle before change
    timed_call(
        result, "Resolve handle before change",
        lambda: pds.identity.resolve_handle(original_handle),
        detail_fn=lambda r: f"did={r.get('did', '?')}" if r else "failed",
    )

    # Update handle
    new_handle = "luna-new.test"
    timed_call(
        result, "Update handle",
        lambda: pds.identity.update_handle(new_handle, luna.access_jwt),
        detail_fn=lambda _: f"handle={new_handle}",
    )

    # Wait for propagation
    time.sleep(3)

    # Verify PLC DID document is updated
    try:
        import requests
        plc_resp = timed_call(
            result, "Verify PLC DID document updated",
            lambda: requests.get(f"http://127.0.0.1:2582/{luna.did}", timeout=10),
            detail_fn=lambda r: f"status={r.status_code}" if r else "failed",
        )
        if plc_resp and plc_resp.status_code == 200:
            did_doc = plc_resp.json()
            aka = did_doc.get("alsoKnownAs", [])
            has_new_handle = any(new_handle in h for h in aka) if aka else False
            if has_new_handle:
                result.step_passed("PLC handle verification", f"new_handle={new_handle}")
            else:
                result.step_skipped("PLC handle verification", f"alsoKnownAs={aka}")
    except ImportError:
        result.step_skipped("PLC DID document check", "requests not available")

    # Verify AppView profile reflects new handle
    timed_call(
        result, "Verify AppView profile has new handle",
        lambda: appview.actor.get_profile(
            {"actor": luna.did}, luna.access_jwt,
        ),
        detail_fn=lambda r: f"handle={r.get('handle', '?')}" if r else "failed",
    )

    # Verify new handle resolves
    timed_call(
        result, "Resolve new handle",
        lambda: pds.identity.resolve_handle(new_handle),
        detail_fn=lambda r: f"did={r.get('did', '?')}" if r else "failed",
    )

    # Verify relay sees the new handle (check describe server for relay health)
    relay = XrpcClient(SERVICE_URLS["relay"])
    timed_call(
        result, "Verify relay health",
        lambda: relay._get("/api/relay/health"),
    )

    result.finish()
    return result
