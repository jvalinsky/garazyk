"""Scenario 31: "Noisy Neighbor" — Rate Limiting Isolation

Verify per-DID rate limiting isolation.
User troll (Trollface) performs a burst of 60 rapid getProfile requests.
Assert that subsequent requests return 429.
User luna performs a single getProfile request at the same time.
Assert it returns 200 OK.

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


def run() -> ScenarioResult:
    result = ScenarioResult("Rate Limiting Isolation")
    result.start()

    client = XrpcClient(PDS1)

    # 1. Health check — PDS should already be running with rate limiting
    # enabled (configured in pds-config.json: did_limit=60, did_window_seconds=60)
    timed_call(result, "PDS health check", lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # 2. Setup accounts
    troll = get_character("troll")
    luna = get_character("luna")

    for char in [troll, luna]:
        session = timed_call(
            result, f"Create account: {char.name}",
            lambda c=char: client.accounts.create_account(c.handle, c.email, c.password),
            detail_fn=lambda s: f"did={s['did']}",
        )
        if session:
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]

    if not troll.did or not luna.did:
        result.step_failed("Setup", "Failed to create test accounts")
        result.finish()
        return result

    # 3. Troll performs 60 rapid requests (should all succeed within limit)
    print("Troll performing 60 rapid getProfile requests")
    success_count = 0
    for i in range(60):
        try:
            client.raw.xrpc_get("app.bsky.actor.getProfile", {"actor": troll.did}, token=troll.access_jwt)
            success_count += 1
        except Exception as e:
            print(f"Request {i+1} failed: {e}")
            break
    
    if success_count == 60:
        result.step_passed("Troll burst completion", f"success_count={success_count}")
    else:
        result.step_failed("Troll burst completion", f"Expected 60 successes, got {success_count}")

    # 4. Troll's 61st request should fail with 429 RateLimitExceeded
    timed_call(
        result, "Troll's 61st request (Expect 429 RateLimitExceeded)",
        lambda: client.raw.xrpc_get("app.bsky.actor.getProfile", {"actor": troll.did}, token=troll.access_jwt),
        expect_failure="RateLimitExceeded",
    )

    # 5. Luna's request should succeed (Isolation)
    timed_call(
        result, "Luna's request (Expect 200 OK)",
        lambda: client.raw.xrpc_get("app.bsky.actor.getProfile", {"actor": luna.did}, token=luna.access_jwt),
        detail_fn=lambda r: "Success (Isolated)"
    )

    result.finish()
    return result


if __name__ == "__main__":
    res = run()
    res.print_summary()
    sys.exit(res.exit_code)
