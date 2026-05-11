"""Scenario 32: "Identity Fatigue" — PLC Hourly Rate Limits

Test PLC hourly operation rate limits.
The PLC auditor enforces three tiers (configurable via env vars):
  - Hourly: PLC_HOURLY_LIMIT (default 5 in test scenarios)
  - Daily:  PLC_DAILY_LIMIT  (default 15 in test scenarios)
  - Weekly: PLC_WEEKLY_LIMIT (default 50 in test scenarios)

User rosa performs PLC_HOURLY_LIMIT handle rotations.
Assert that the next operation fails with a 400 error from the PLC directory
containing "Too many operations within last hour".

Services: PDS, PLC
"""

from __future__ import annotations

import os
import sys
import time
import requests as reqs
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call


def run() -> ScenarioResult:
    result = ScenarioResult("Identity Fatigue")
    result.start()

    client = XrpcClient(PDS1)
    rosa = get_character("rosa")

    timed_call(result, "PDS health check", lambda: client.wait_for_healthy(timeout=30))
    
    session = timed_call(
        result, "Create account: rosa",
        lambda: client.accounts.create_account(rosa.handle, rosa.email, rosa.password),
        detail_fn=lambda s: f"did={s['did']}",
    )
    if not session:
        result.finish()
        return result
    rosa.did = session["did"]
    rosa.access_jwt = session["accessJwt"]

    # Read the configured hourly limit (set by setup_local_network.sh)
    hourly_limit = int(os.environ.get("PLC_HOURLY_LIMIT", "5"))
    
    # Account creation already consumed one PLC operation, so we can do
    # (hourly_limit - 1) more rotations before hitting the limit.
    rotations = hourly_limit - 1
    print(f"Starting {rotations} handle rotations (account creation already used 1 of {hourly_limit} hourly ops)")
    
    success_count = 0
    try:
        for i in range(rotations):
            new_handle = f"rev-{i}-{rosa.handle}"
            
            # 1. Request signature
            token_resp = client.raw.xrpc_post("com.atproto.identity.requestPlcOperationSignature", {}, token=rosa.access_jwt)
            token = token_resp.get("token")
            
            # 2. Sign operation
            sign_resp = client.raw.xrpc_post("com.atproto.identity.signPlcOperation",
                                            {"token": token, "alsoKnownAs": [f"at://{new_handle}"]},
                                            token=rosa.access_jwt)
            op = sign_resp.get("operation", {})
            op.pop("did", None)
            
            # 3. Submit to PLC
            plc_url = f"http://localhost:2582/{rosa.did}"
            plc_submit = reqs.post(plc_url, json=op, timeout=5)
            
            if plc_submit.status_code == 200:
                success_count += 1
            else:
                result.step_failed("Exhaust Quota", f"Failed at iteration {i}: {plc_submit.status_code} {plc_submit.text}")
                break
            
            if (i + 1) % 5 == 0:
                print(f"  ... completed {i+1} rotations")
    except Exception as exc:
        result.step_failed("Exhaust Quota", str(exc))

    result.step_passed("Quota Exhaustion", f"Successfully performed {success_count} rotations")

    # The next rotation should fail (hourly limit reached)
    if success_count == rotations:
        print(f"Attempting rotation #{rotations + 1} (expect failure — hourly limit reached)")
        new_handle = f"final-{rosa.handle}"
        token_resp = client.raw.xrpc_post("com.atproto.identity.requestPlcOperationSignature", {}, token=rosa.access_jwt)
        token = token_resp.get("token")
        sign_resp = client.raw.xrpc_post("com.atproto.identity.signPlcOperation",
                                        {"token": token, "alsoKnownAs": [f"at://{new_handle}"]},
                                        token=rosa.access_jwt)
        op = sign_resp.get("operation", {})
        op.pop("did", None)
        
        plc_submit = reqs.post(f"http://localhost:2582/{rosa.did}", json=op, timeout=5)
        if plc_submit.status_code == 400 and "Too many operations" in plc_submit.text:
             result.step_passed("Verify Hourly Limit", f"Rejected operation after {hourly_limit} total ops as expected (400)")
        else:
             result.step_failed("Verify Hourly Limit", f"Expected 400 rejection, but got {plc_submit.status_code}: {plc_submit.text}")

    result.finish()
    return result


if __name__ == "__main__":
    res = run()
    res.print_summary()
    sys.exit(res.exit_code)
