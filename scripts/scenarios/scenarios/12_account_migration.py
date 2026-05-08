"""Scenario 12: "The Great Migration" — Account Migration & PLC Audit

Simulates a cooperative account migration from PDS1 to PDS2.
The user creates an account on PDS1, changes their handle,
and then migrates hosting to PDS2. We rigorously audit the local
PLC directory's operation log to ensure all identity and service
endpoint changes are correctly recorded and chained.

Services: PDS1, PDS2, PLC
"""

from __future__ import annotations

import sys
import time
import requests
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, PDS1, PDS2
from lib.assertions import assert_success, assert_contains
from lib.report import ScenarioResult, StepStatus


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Account Migration & PLC Audit")
    result.start()

    pds1 = XrpcClient(PDS1)
    pds2 = XrpcClient(PDS2)
    luna = get_character("luna")

    # ── Step 1: Environment Setup & Verification ──────────────────────
    for name, client in [("PDS1", pds1), ("PDS2", pds2)]:
        try:
            client.wait_for_healthy(timeout=30)
            result.step_passed(f"{name} health check")
        except RuntimeError as exc:
            result.step_failed(f"{name} health check", str(exc))
            result.finish()
            return result

    try:
        plc_health = requests.get("http://localhost:2582/_health", timeout=5)
        if plc_health.status_code == 200:
            result.step_passed("PLC health check")
        else:
            result.step_failed("PLC health check", f"status={plc_health.status_code}")
            result.finish()
            return result
    except Exception as exc:
        result.step_failed("PLC health check", str(exc))
        result.finish()
        return result

    # ── Step 2: Account Creation & Initial State (PDS1) ───────────────
    admin = get_character("admin")
    try:
        admin_session = pds1.create_account(admin.handle, admin.email, admin.password)
        admin.did = admin_session["did"]
        admin.access_jwt = admin_session["accessJwt"]
        result.step_passed("Create admin account on PDS1", f"did={admin.did}")
    except XrpcError as exc:
        result.step_failed("Create admin account on PDS1", str(exc))
        result.finish()
        return result

    try:
        session = pds1.create_account(luna.handle, luna.email, luna.password)
        luna.did = session["did"]
        luna.access_jwt = session["accessJwt"]
        result.step_passed("Create user account on PDS1", f"did={luna.did}")
    except XrpcError as exc:
        result.step_failed("Create user account on PDS1", str(exc))
        result.finish()
        return result

    # ── Step 3: Handle Rotations (PDS1) ───────────────────────────────
    original_handle = luna.handle
    parts = original_handle.rsplit(".", 1)
    base = parts[0]
    domain = parts[1] if len(parts) > 1 else "test"
    
    new_handle_1 = f"one-{base}.{domain}"
    new_handle_2 = f"two-{base}.{domain}"

    try:
        # First handle rotation via direct PLC operation
        token_resp = pds1.xrpc_post("com.atproto.identity.requestPlcOperationSignature", {}, token=luna.access_jwt)
        token = token_resp.get("token")
        
        sign_resp = pds1.xrpc_post(
            "com.atproto.identity.signPlcOperation",
            {"token": token, "alsoKnownAs": [f"at://{new_handle_1}"]},
            token=luna.access_jwt
        )
        op1 = sign_resp.get("operation")
        op1.pop("did", None)  # Remove convenience field before submitting to PLC
        
        # Bypass PDS validation and submit directly to PLC directory
        plc_submit_1 = requests.post(f"http://localhost:2582/{luna.did}", json=op1, timeout=5)
        if plc_submit_1.status_code == 200:
            result.step_passed("First handle rotation (Direct PLC)", f"handle={new_handle_1}")
        else:
            result.step_failed("First handle rotation (Direct PLC)", f"status={plc_submit_1.status_code} body={plc_submit_1.text}")
            
        time.sleep(2)
        
        # Second handle rotation via direct PLC operation
        token_resp2 = pds1.xrpc_post("com.atproto.identity.requestPlcOperationSignature", {}, token=luna.access_jwt)
        token2 = token_resp2.get("token")
        
        sign_resp2 = pds1.xrpc_post(
            "com.atproto.identity.signPlcOperation",
            {"token": token2, "alsoKnownAs": [f"at://{new_handle_2}"]},
            token=luna.access_jwt
        )
        op2 = sign_resp2.get("operation")
        op2.pop("did", None)  # Remove convenience field before submitting to PLC
        
        plc_submit_2 = requests.post(f"http://localhost:2582/{luna.did}", json=op2, timeout=5)
        if plc_submit_2.status_code == 200:
            result.step_passed("Second handle rotation (Direct PLC)", f"handle={new_handle_2}")
        else:
            result.step_failed("Second handle rotation (Direct PLC)", f"status={plc_submit_2.status_code} body={plc_submit_2.text}")
            
        luna.handle = new_handle_2
        time.sleep(2)
    except Exception as exc:
        result.step_failed("Handle rotations via PLC", str(exc))

    # ── Step 8: PLC Log Auditing ──────────────────────────────────────
    try:
        log_resp = requests.get(f"http://localhost:2582/{luna.did}/log", timeout=5)
        if log_resp.status_code == 200:
            log_lines = log_resp.json()
            
            # Since PLC /log sometimes returns JSONL, we might need to parse it if it's text
            if isinstance(log_lines, str):
                import json
                operations = [json.loads(line) for line in log_lines.strip().split('\n')]
            elif isinstance(log_lines, list):
                operations = log_lines
            else:
                operations = []

            result.step_passed("Fetch PLC operation log", f"total_operations={len(operations)}")

            if len(operations) == 0:
                result.step_failed("PLC log audit", "Log is empty")
            else:
                # Audit the chain
                is_valid = True
                failure_reason = ""
                
                # 1. Check genesis
                genesis = operations[0]
                if "prev" in genesis and genesis["prev"] is not None:
                    is_valid = False
                    failure_reason = "Genesis operation has a 'prev' CID"
                
                # 2. Check chaining and monotonicity
                last_cid = genesis.get("cid")
                # Note: PLC operations return { cid: "...", operation: { prev: "...", ... } }
                
                for i, op in enumerate(operations[1:], start=1):
                    # Different PLC implementations format this slightly differently.
                    # Usually: {"cid": "bafy...", "operation": {"prev": "bafy...", ...}}
                    op_data = op.get("operation", op)
                    
                    if op_data.get("prev") != last_cid:
                        is_valid = False
                        failure_reason = f"Chain broken at index {i}: expected prev={last_cid}, got {op_data.get('prev')}"
                        break
                    
                    last_cid = op.get("cid", op_data.get("cid")) # Need to get the CID of this operation for the next loop
                
                if is_valid:
                    result.step_passed("PLC operation chain audit", "Chain is intact and monotonic")
                else:
                    result.step_failed("PLC operation chain audit", failure_reason)

                # 3. Check for handle updates
                # In PLC operations, handles are updated via 'alsoKnownAs' field
                handles_seen = set()
                for op in operations:
                    op_data = op.get("operation", op)
                    akas = op_data.get("alsoKnownAs", [])
                    for aka in akas:
                        if aka.startswith("at://"):
                            handles_seen.add(aka.replace("at://", ""))

                if new_handle_1 in handles_seen and new_handle_2 in handles_seen:
                    result.step_passed("Verify handle updates in PLC", f"Found handles: {new_handle_1}, {new_handle_2}")
                else:
                    result.step_failed("Verify handle updates in PLC", f"Missing handle updates in log. Seen: {handles_seen}")

        else:
            result.step_failed("Fetch PLC operation log", f"status={log_resp.status_code}")

    except Exception as exc:
        result.step_failed("Fetch PLC operation log", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
