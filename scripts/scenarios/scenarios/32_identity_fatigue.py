"""Scenario 32: "Identity Fatigue" — PLC Weekly Limits

Test PLC weekly operation limits.
User rosa performs a loop of 101 handle rotations.
Assert that the 101st operation fails with a 400 error from the PLC directory.

Services: PDS, PLC
"""

from __future__ import annotations

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

    # PLC Week Limit is 100 operations per DID.
    # We need to rotate the handle 100 times, then expect the 101st to fail.
    
    ROTATIONS = 100
    print(f"Starting {ROTATIONS} handle rotations to exhaust PLC quota")
    
    # Speed up by using a loop without full timed_call per iteration to avoid cluttering report
    success_count = 0
    try:
        for i in range(ROTATIONS):
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
            
            if (i + 1) % 20 == 0:
                print(f"  ... completed {i+1} rotations")
    except Exception as exc:
        result.step_failed("Exhaust Quota", str(exc))

    result.step_passed("Quota Exhaustion", f"Successfully performed {success_count} rotations")

    # 101st rotation should fail
    if success_count == ROTATIONS:
        print("Attempting 101st rotation (expect failure)")
        new_handle = f"final-{rosa.handle}"
        token_resp = client.raw.xrpc_post("com.atproto.identity.requestPlcOperationSignature", {}, token=rosa.access_jwt)
        token = token_resp.get("token")
        sign_resp = client.raw.xrpc_post("com.atproto.identity.signPlcOperation",
                                        {"token": token, "alsoKnownAs": [f"at://{new_handle}"]},
                                        token=rosa.access_jwt)
        op = sign_resp.get("operation", {})
        op.pop("did", None)
        
        plc_submit = reqs.post(f"http://localhost:2582/{rosa.did}", json=op, timeout=5)
        if plc_submit.status_code == 400:
             result.step_passed("Verify Weekly Limit", "Rejected 101st operation as expected (400 Bad Request)")
        else:
             result.step_failed("Verify Weekly Limit", f"Expected 400 rejection, but got {plc_submit.status_code}: {plc_submit.text}")

    result.finish()
    return result


if __name__ == "__main__":
    res = run()
    res.print_summary()
    sys.exit(res.exit_code)
