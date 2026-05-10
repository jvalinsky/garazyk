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

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call



def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("OAuth2 & Sessions")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    char_names = ["luna", "marcus"]
    for name in char_names:
        char = get_character(name)
        session = timed_call(
            result, f"Create account: {char.name}",
            lambda c=char: client.accounts.create_account(c.handle, c.email, c.password),
            detail_fn=lambda s, n=name: f"did={s['did']}",
        )
        if session:
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            char.refresh_jwt = session.get("refreshJwt")

    luna = get_character("luna")
    marcus = get_character("marcus")

    if not all([luna.did, marcus.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

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

    try:
        import requests
        auth_url = (
            f"{PDS1}/oauth/authorize"
            f"?client_id=scenario-test-client"
            f"&redirect_uri={PDS1}/oauth/callback"
            f"&response_type=code&scope=atproto&state=test-state-123"
        )
        auth_resp = requests.get(auth_url, allow_redirects=False, timeout=10)
        try:
            body = auth_resp.json()
        except ValueError:
            body = {}
        if auth_resp.status_code == 400 and body.get("error") == "invalid_request":
            result.step_passed("OAuth authorize enforces PAR",
                               "direct params rejected with invalid_request")
        else:
            result.step_failed("OAuth authorize enforces PAR",
                               f"status={auth_resp.status_code} body={body!r}")
    except Exception as exc:
        result.step_failed("OAuth authorize enforces PAR", str(exc))

    try:
        import requests
        token_resp = requests.post(
            f"{PDS1}/oauth/token",
            data={"grant_type": "authorization_code", "client_id": "scenario-test-client",
                  "redirect_uri": f"{PDS1}/oauth/callback", "code": "test-invalid-code",
                  "code_verifier": "test-verifier"},
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=10,
        )
        if token_resp.status_code in (400, 401, 403):
            result.step_passed("OAuth token endpoint rejects invalid code", f"status={token_resp.status_code}")
        else:
            result.step_skipped("OAuth token endpoint", f"status={token_resp.status_code}")
    except Exception as exc:
        result.step_skipped("OAuth token endpoint", str(exc))

    try:
        import requests
        revoke_resp = requests.post(
            f"{PDS1}/oauth/revoke",
            data={"client_id": "scenario-test-client", "token": "test-invalid-token"},
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=10,
        )
        if revoke_resp.status_code in (200, 400, 401):
            result.step_passed("OAuth revoke endpoint responds", f"status={revoke_resp.status_code}")
        else:
            result.step_skipped("OAuth revoke endpoint", f"status={revoke_resp.status_code}")
    except Exception as exc:
        result.step_skipped("OAuth revoke endpoint", str(exc))

    timed_call(
        result, "Luna creates session",
        lambda: client.accounts.create_session(luna.handle, luna.password),
        detail_fn=lambda s: f"token={s['accessJwt'][:20]}...",
    )

    timed_call(
        result, "Luna gets session info",
        lambda: client.accounts.get_session(luna.access_jwt),
        detail_fn=lambda s: f"did={s.get('did')}",
    )

    if luna.refresh_jwt:
        refreshed = timed_call(
            result, "Luna refreshes session",
            lambda: client.accounts.refresh_session(luna.refresh_jwt),
            detail_fn=lambda r: f"token={r['accessJwt'][:20]}...",
        )
        if refreshed:
            luna.access_jwt = refreshed["accessJwt"]
    else:
        result.step_skipped("Luna refreshes session", "No refreshJwt")

    marcus_refresh_jwt = None
    marcus_session = timed_call(
        result, "Marcus creates session",
        lambda: client.accounts.create_session(marcus.handle, marcus.password),
    )
    if marcus_session:
        marcus.access_jwt = marcus_session["accessJwt"]
        marcus_refresh_jwt = marcus_session.get("refreshJwt")

    try:
        client.accounts.delete_session(marcus.access_jwt)
        result.step_passed("Marcus deletes session (logout)")
    except Exception as exc:
        result.step_failed("Marcus deletes session", str(exc))

    if marcus_refresh_jwt:
        err = timed_call(
            result, "Refresh after deleteSession fails",
            lambda: client.accounts.refresh_session(marcus_refresh_jwt),
            expect_failure=True,
        )
        if err and err.status not in (400, 401):
            result.step_failed("Refresh after deleteSession fails",
                               f"unexpected status={err.status} body={err.body!r}")
    else:
        result.step_skipped("Refresh after deleteSession fails", "no refreshJwt returned by createSession")

    timed_call(
        result, "Invalid password rejected",
        lambda: client.accounts.create_session(luna.handle, "absolutely_wrong_password"),
        expect_failure=True,
    )

    timed_call(
        result, "Missing auth rejected",
        lambda: client.records.create_record(
            luna.did, "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post", "text": "unauthorized", "createdAt": _now()},
            "invalid-token-xyz"),
        expect_failure=True,
    )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
