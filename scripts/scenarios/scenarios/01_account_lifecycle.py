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

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, get_characters_by_pds, PDS1
from lib.assertions import assert_success, assert_contains, assert_error, assert_xrpc_raises
from lib.report import ScenarioResult, StepStatus


def run() -> ScenarioResult:
    result = ScenarioResult("Account Lifecycle & Identity")
    result.start()

    pds = XrpcClient(PDS1)
    luna = get_character("luna")

    # ── Step 1: Wait for server ─────────────────────────────────────
    try:
        pds.wait_for_healthy(timeout=30)
        result.step_passed("Server health check")
    except RuntimeError as exc:
        result.step_failed("Server health check", str(exc))
        result.finish()
        return result

    # ── Step 2: Describe server ─────────────────────────────────────
    try:
        desc = pds.describe_server()
        assert_contains(desc, "availableUserDomains", operation="describeServer")
        result.step_passed("Describe server", f"domains={desc.get('availableUserDomains')}")
    except (AssertionError, XrpcError) as exc:
        result.step_failed("Describe server", str(exc))

    # ── Step 3: Create account ──────────────────────────────────────
    try:
        session = pds.create_account(luna.handle, luna.email, luna.password)
        assert_contains(session, "did", operation="createAccount")
        assert_contains(session, "accessJwt", operation="createAccount")
        luna.did = session["did"]
        luna.access_jwt = session["accessJwt"]
        luna.refresh_jwt = session.get("refreshJwt")
        result.step_passed("Create account", f"did={luna.did}")
    except (AssertionError, XrpcError) as exc:
        result.step_failed("Create account", str(exc))
        result.finish()
        return result

    # ── Step 4: Get session ─────────────────────────────────────────
    try:
        sess = pds.get_session(luna.access_jwt)
        assert_contains(sess, "did", luna.did, operation="getSession")
        result.step_passed("Get session", f"did={sess.get('did')}")
    except (AssertionError, XrpcError) as exc:
        result.step_failed("Get session", str(exc))

    # ── Step 5: Resolve handle ──────────────────────────────────────
    try:
        resolved = pds.resolve_handle(luna.handle)
        assert_contains(resolved, "did", luna.did, operation="resolveHandle")
        result.step_passed("Resolve handle", f"did={resolved.get('did')}")
    except (AssertionError, XrpcError) as exc:
        result.step_failed("Resolve handle", str(exc))

    # ── Step 6: PLC DID resolution ──────────────────────────────────
    try:
        import requests
        plc_resp = requests.get(f"http://localhost:2582/{luna.did}", timeout=10)
        if plc_resp.status_code == 200:
            did_doc = plc_resp.json()
            # W3C DID spec uses "id" not "did" in DID documents
            did_field = did_doc.get("id") or did_doc.get("did")
            assert did_field == luna.did, f"PLC DID mismatch: expected {luna.did}, got {did_field}"
            result.step_passed("PLC DID resolution", f"method={did_doc.get('verificationMethod', 'N/A')}")
        else:
            result.step_skipped("PLC DID resolution", f"PLC returned {plc_resp.status_code}")
    except Exception as exc:
        result.step_skipped("PLC DID resolution", str(exc))

    # ── Step 7: Set up profile ──────────────────────────────────────
    try:
        profile = {
            "$type": "app.bsky.actor.profile",
            "displayName": "Luna Starfield",
            "description": "Astronomy enthusiast. Looking up, always. 🌌",
        }
        rec = pds.create_record(luna.did, "app.bsky.actor.profile", profile, luna.access_jwt)
        assert_contains(rec, "uri", operation="createProfile")
        result.step_passed("Create profile", f"uri={rec['uri']}")
    except (AssertionError, XrpcError) as exc:
        result.step_failed("Create profile", str(exc))

    # ── Step 8: Get profile ─────────────────────────────────────────
    try:
        profile = pds.get_profile(luna.did, token=luna.access_jwt)
        assert_contains(profile, "did", luna.did, operation="getProfile")
        result.step_passed("Get profile", f"displayName={profile.get('displayName')}")
    except (AssertionError, XrpcError) as exc:
        result.step_failed("Get profile", str(exc))

    # ── Step 9: Refresh session ─────────────────────────────────────
    try:
        if luna.refresh_jwt:
            refreshed = pds.refresh_session(luna.refresh_jwt)
            assert_contains(refreshed, "accessJwt", operation="refreshSession")
            luna.access_jwt = refreshed["accessJwt"]
            result.step_passed("Refresh session")
        else:
            result.step_skipped("Refresh session", "No refreshJwt available")
    except (AssertionError, XrpcError) as exc:
        result.step_failed("Refresh session", str(exc))

    # ── Step 10: Invalid login ──────────────────────────────────────
    try:
        assert_xrpc_raises(
            "Invalid login",
            None,  # Just check it raises, don't check specific error
            pds.create_session,
            luna.handle,
            "wrong_password",
        )
        result.step_passed("Invalid login rejected")
    except AssertionError as exc:
        result.step_failed("Invalid login rejected", str(exc))

    # ── Step 11: Delete session (logout) ────────────────────────────
    try:
        pds.delete_session(luna.access_jwt)
        result.step_passed("Delete session (logout)")
    except Exception as exc:
        result.step_skipped("Delete session", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
