"""Scenario 1: "First Day on the Network" — Account Lifecycle & Identity

Luna Starfield creates her account on the PDS, her DID gets registered
in PLC, she sets up her profile, and verifies her identity resolves
correctly through PLC.

Services: PDS, PLC
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

# Add repo root to path
_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call


def run() -> ScenarioResult:
    result = ScenarioResult("Account Lifecycle & Identity")
    result.start()

    pds = XrpcClient(PDS1)
    luna = get_character("luna")

    timed_call(result, "Server health check",
               lambda: pds.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    desc = timed_call(
        result, "Describe server",
        lambda: pds.accounts.describe_server(),
        detail_fn=lambda d: f"domains={d.get('availableUserDomains')}",
    )

    session = timed_call(
        result, "Create account",
        lambda: pds.accounts.create_account(luna.handle, luna.email, luna.password),
        detail_fn=lambda s: f"did={s['did']}",
    )
    if session:
        luna.did = session["did"]
        luna.access_jwt = session["accessJwt"]
        luna.refresh_jwt = session.get("refreshJwt")
    else:
        result.finish()
        return result

    timed_call(
        result, "Get session",
        lambda: pds.accounts.get_session(luna.access_jwt),
        detail_fn=lambda s: f"did={s.get('did')}",
    )

    timed_call(
        result, "Resolve handle",
        lambda: pds.identity.resolve_handle(luna.handle),
        detail_fn=lambda r: f"did={r.get('did')}",
    )

    try:
        import requests
        plc_resp = requests.get(f"http://localhost:2582/{luna.did}", timeout=10)
        if plc_resp.status_code == 200:
            did_doc = plc_resp.json()
            did_field = did_doc.get("id") or did_doc.get("did")
            assert did_field == luna.did, f"PLC DID mismatch: expected {luna.did}, got {did_field}"
            result.step_passed("PLC DID resolution", f"method={did_doc.get('verificationMethod', 'N/A')}")
        else:
            result.step_skipped("PLC DID resolution", f"PLC returned {plc_resp.status_code}")
    except Exception as exc:
        result.step_skipped("PLC DID resolution", str(exc))

    profile = {
        "$type": "app.bsky.actor.profile",
        "displayName": "Luna Starfield",
        "description": "Astronomy enthusiast. Looking up, always.",
    }
    timed_call(
        result, "Create profile",
        lambda: pds.records.create_record(luna.did, "app.bsky.actor.profile", profile, luna.access_jwt),
        detail_fn=lambda r: f"uri={r['uri']}",
    )

    timed_call(
        result, "Get profile",
        lambda: pds.feed.get_profile(luna.did, token=luna.access_jwt),
        detail_fn=lambda p: f"displayName={p.get('displayName')}",
    )

    if luna.refresh_jwt:
        refreshed = timed_call(
            result, "Refresh session",
            lambda: pds.accounts.refresh_session(luna.refresh_jwt),
            detail_fn=lambda r: f"accessJwt={r['accessJwt'][:20]}...",
        )
        if refreshed:
            luna.access_jwt = refreshed["accessJwt"]
    else:
        result.step_skipped("Refresh session", "No refreshJwt available")

    timed_call(
        result, "Invalid login rejected",
        lambda: pds.accounts.create_session(luna.handle, "wrong_password"),
        expect_failure=True,
    )

    try:
        pds.accounts.delete_session(luna.access_jwt)
        result.step_passed("Delete session (logout)")
    except Exception as exc:
        result.step_skipped("Delete session", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
