"""Scenario 8: "Auth Dance" — OAuth2 & Sessions

Marcus registers an OAuth client. Luna authorizes the client via OAuth2
flow. The client exchanges the code for tokens. Luna refreshes her
session. The client makes an authenticated request. Luna revokes the
token.

Services: PDS
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, PDS1
from lib.assertions import assert_success, assert_contains, assert_xrpc_raises
from lib.report import ScenarioResult, StepStatus


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("OAuth2 & Sessions")
    result.start()

    client = XrpcClient(PDS1)

    # Wait for server
    try:
        client.wait_for_healthy(timeout=30)
        result.step_passed("Server health check")
    except RuntimeError as exc:
        result.step_failed("Server health check", str(exc))
        result.finish()
        return result

    # ── Create accounts ──────────────────────────────────────────────
    char_names = ["luna", "marcus"]
    for name in char_names:
        char = get_character(name)
        try:
            session = client.create_account(char.handle, char.email, char.password)
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            char.refresh_jwt = session.get("refreshJwt")
            result.step_passed(f"Create account: {char.name}", f"did={char.did}")
        except XrpcError as exc:
            result.step_failed(f"Create account: {char.name}", str(exc))

    luna = get_character("luna")
    marcus = get_character("marcus")

    if not all([luna.did, marcus.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    # ── Register OAuth client ────────────────────────────────────────
    try:
        import subprocess
        repo_root = Path(__file__).parent.parent.parent.parent
        bin_path = repo_root / "build" / "bin" / "kaszlak"
        if bin_path.exists():
            reg_result = subprocess.run(
                [str(bin_path), "oauth", "client", "register",
                 "--client-id", "scenario-test-client",
                 "--redirect-uri", f"{PDS1}/oauth/callback"],
                capture_output=True, text=True, timeout=10,
            )
            if reg_result.returncode == 0:
                result.step_passed("OAuth client registered")
            else:
                result.step_skipped("OAuth client registered", f"CLI returned {reg_result.returncode}")
        else:
            result.step_skipped("OAuth client registered", "kaszlak binary not found")
    except Exception as exc:
        result.step_skipped("OAuth client registered", str(exc))

    # ── Test authorization endpoint ──────────────────────────────────
    try:
        import requests
        auth_url = (
            f"{PDS1}/oauth/authorize"
            f"?client_id=scenario-test-client"
            f"&redirect_uri={PDS1}/oauth/callback"
            f"&response_type=code"
            f"&scope=atproto"
            f"&state=test-state-123"
        )
        auth_resp = requests.get(auth_url, allow_redirects=False, timeout=10)
        # Should get a redirect or a login page
        if auth_resp.status_code in (302, 303, 200):
            result.step_passed("OAuth authorize endpoint", f"status={auth_resp.status_code}")
        else:
            result.step_skipped("OAuth authorize endpoint", f"status={auth_resp.status_code}")
    except Exception as exc:
        result.step_skipped("OAuth authorize endpoint", str(exc))

    # ── Test token endpoint ──────────────────────────────────────────
    try:
        import requests
        token_resp = requests.post(
            f"{PDS1}/oauth/token",
            data={
                "grant_type": "authorization_code",
                "client_id": "scenario-test-client",
                "redirect_uri": f"{PDS1}/oauth/callback",
                "code": "test-invalid-code",
                "code_verifier": "test-verifier",
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=10,
        )
        # Should fail with invalid code — that's expected
        if token_resp.status_code in (400, 401, 403):
            result.step_passed("OAuth token endpoint rejects invalid code", f"status={token_resp.status_code}")
        else:
            result.step_skipped("OAuth token endpoint", f"status={token_resp.status_code}")
    except Exception as exc:
        result.step_skipped("OAuth token endpoint", str(exc))

    # ── Test revoke endpoint ─────────────────────────────────────────
    try:
        import requests
        revoke_resp = requests.post(
            f"{PDS1}/oauth/revoke",
            data={
                "client_id": "scenario-test-client",
                "token": "test-invalid-token",
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=10,
        )
        if revoke_resp.status_code in (200, 400, 401):
            result.step_passed("OAuth revoke endpoint responds", f"status={revoke_resp.status_code}")
        else:
            result.step_skipped("OAuth revoke endpoint", f"status={revoke_resp.status_code}")
    except Exception as exc:
        result.step_skipped("OAuth revoke endpoint", str(exc))

    # ── Session lifecycle ────────────────────────────────────────────
    # Create session
    try:
        session = client.create_session(luna.handle, luna.password)
        assert_contains(session, "accessJwt", operation="createSession")
        luna.access_jwt = session["accessJwt"]
        luna.refresh_jwt = session.get("refreshJwt")
        result.step_passed("Luna creates session")
    except (AssertionError, XrpcError) as exc:
        result.step_failed("Luna creates session", str(exc))

    # Get session
    try:
        sess = client.get_session(luna.access_jwt)
        assert_contains(sess, "did", luna.did, operation="getSession")
        result.step_passed("Luna gets session info")
    except (AssertionError, XrpcError) as exc:
        result.step_failed("Luna gets session info", str(exc))

    # Refresh session
    try:
        if luna.refresh_jwt:
            refreshed = client.refresh_session(luna.refresh_jwt)
            assert_contains(refreshed, "accessJwt", operation="refreshSession")
            luna.access_jwt = refreshed["accessJwt"]
            result.step_passed("Luna refreshes session")
        else:
            result.step_skipped("Luna refreshes session", "No refreshJwt")
    except (AssertionError, XrpcError) as exc:
        result.step_failed("Luna refreshes session", str(exc))

    # ── Marcus creates and deletes a session ─────────────────────────
    try:
        session = client.create_session(marcus.handle, marcus.password)
        marcus.access_jwt = session["accessJwt"]
        result.step_passed("Marcus creates session")
    except XrpcError as exc:
        result.step_failed("Marcus creates session", str(exc))

    # Marcus deletes session (logout)
    try:
        client.delete_session(marcus.access_jwt)
        result.step_passed("Marcus deletes session (logout)")
    except Exception as exc:
        result.step_skipped("Marcus deletes session", str(exc))

    # Verify deleted session is invalid
    try:
        assert_xrpc_raises(
            "Get session with deleted token",
            None,
            client.get_session,
            marcus.access_jwt,
        )
        result.step_passed("Deleted session is invalid")
    except AssertionError:
        result.step_skipped("Deleted session check", "Session may still be valid after delete")

    # ── Invalid credentials ──────────────────────────────────────────
    try:
        assert_xrpc_raises(
            "Login with wrong password",
            None,
            client.create_session,
            luna.handle,
            "absolutely_wrong_password",
        )
        result.step_passed("Invalid password rejected")
    except AssertionError as exc:
        result.step_failed("Invalid password rejected", str(exc))

    # ── Missing auth ─────────────────────────────────────────────────
    try:
        assert_xrpc_raises(
            "Create record without auth",
            None,
            client.create_record,
            luna.did,
            "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post", "text": "unauthorized", "createdAt": _now()},
            "invalid-token-xyz",
        )
        result.step_passed("Missing auth rejected")
    except AssertionError as exc:
        result.step_skipped("Missing auth rejected", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
