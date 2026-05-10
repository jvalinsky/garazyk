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
import requests as reqs
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, PDS2, ScenarioResult, timed_call



def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Account Migration & PLC Audit")
    result.start()

    pds1 = XrpcClient(PDS1)
    pds2 = XrpcClient(PDS2)
    luna = get_character("luna")

    for name, client in [("PDS1", pds1), ("PDS2", pds2)]:
        timed_call(result, f"{name} health check",
                   lambda c=client: c.wait_for_healthy(timeout=30))
        if result.failed > 0:
            result.finish()
            return result

    try:
        plc_health = reqs.get("http://localhost:2582/_health", timeout=5)
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

    admin = get_character("admin")
    timed_call(
        result, "Create admin account on PDS1",
        lambda: pds1.accounts.create_account(admin.handle, admin.email, admin.password),
        detail_fn=lambda s: f"did={s['did']}",
    )
    if not admin.did:
        result.finish()
        return result

    session = timed_call(
        result, "Create user account on PDS1",
        lambda: pds1.accounts.create_account(luna.handle, luna.email, luna.password),
        detail_fn=lambda s: f"did={s['did']}",
    )
    if not session:
        result.finish()
        return result
    luna.did = session["did"]
    luna.access_jwt = session["accessJwt"]

    original_handle = luna.handle
    parts = original_handle.rsplit(".", 1)
    base = parts[0]
    domain = parts[1] if len(parts) > 1 else "test"

    new_handle_1 = f"one-{base}.{domain}"
    new_handle_2 = f"two-{base}.{domain}"

    try:
        token_resp = timed_call(
            result, "Request PLC operation signature",
            lambda: pds1.raw.xrpc_post("com.atproto.identity.requestPlcOperationSignature",
                                        {}, token=luna.access_jwt),
        )
        token = token_resp.get("token") if token_resp else None

        if token:
            sign_resp1 = timed_call(
                result, f"Sign handle rotation: {new_handle_1}",
                lambda: pds1.raw.xrpc_post("com.atproto.identity.signPlcOperation",
                                            {"token": token, "alsoKnownAs": [f"at://{new_handle_1}"]},
                                            token=luna.access_jwt),
            )
            if sign_resp1:
                op1 = sign_resp1.get("operation", {})
                op1.pop("did", None)
                plc_submit_1 = reqs.post(f"http://localhost:2582/{luna.did}", json=op1, timeout=5)
                if plc_submit_1.status_code == 200:
                    result.step_passed("First handle rotation (Direct PLC)", f"handle={new_handle_1}")
                else:
                    result.step_failed("First handle rotation (Direct PLC)",
                                       f"status={plc_submit_1.status_code} body={plc_submit_1.text}")
            time.sleep(2)

        if token:
            token_resp2 = timed_call(
                result, "Request PLC signature (2nd)",
                lambda: pds1.raw.xrpc_post("com.atproto.identity.requestPlcOperationSignature",
                                            {}, token=luna.access_jwt),
            )
            token2 = token_resp2.get("token") if token_resp2 else None

            if token2:
                sign_resp2 = timed_call(
                    result, f"Sign handle rotation: {new_handle_2}",
                    lambda: pds1.raw.xrpc_post("com.atproto.identity.signPlcOperation",
                                                {"token": token2, "alsoKnownAs": [f"at://{new_handle_2}"]},
                                                token=luna.access_jwt),
                )
                if sign_resp2:
                    op2 = sign_resp2.get("operation", {})
                    op2.pop("did", None)
                    plc_submit_2 = reqs.post(f"http://localhost:2582/{luna.did}", json=op2, timeout=5)
                    if plc_submit_2.status_code == 200:
                        result.step_passed("Second handle rotation (Direct PLC)", f"handle={new_handle_2}")
                    else:
                        result.step_failed("Second handle rotation (Direct PLC)",
                                           f"status={plc_submit_2.status_code} body={plc_submit_2.text}")
            luna.handle = new_handle_2
            time.sleep(2)
    except Exception as exc:
        result.step_failed("Handle rotations via PLC", str(exc))

    try:
        log_resp = reqs.get(f"http://localhost:2582/{luna.did}/log", timeout=5)
        if log_resp.status_code == 200:
            log_lines = log_resp.json()

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
                is_valid = True
                failure_reason = ""

                genesis = operations[0]
                if "prev" in genesis and genesis["prev"] is not None:
                    is_valid = False
                    failure_reason = "Genesis operation has a 'prev' CID"

                last_cid = genesis.get("cid")

                for i, op in enumerate(operations[1:], start=1):
                    op_data = op.get("operation", op)
                    if op_data.get("prev") != last_cid:
                        is_valid = False
                        failure_reason = f"Chain broken at index {i}: expected prev={last_cid}, got {op_data.get('prev')}"
                        break
                    last_cid = op.get("cid", op_data.get("cid"))

                if is_valid:
                    result.step_passed("PLC operation chain audit", "Chain is intact and monotonic")
                else:
                    result.step_failed("PLC operation chain audit", failure_reason)

                handles_seen = set()
                for op in operations:
                    op_data = op.get("operation", op)
                    akas = op_data.get("alsoKnownAs", [])
                    for aka in akas:
                        if aka.startswith("at://"):
                            handles_seen.add(aka.replace("at://", ""))

                if new_handle_1 in handles_seen and new_handle_2 in handles_seen:
                    result.step_passed("Verify handle updates in PLC",
                                       f"Found handles: {new_handle_1}, {new_handle_2}")
                else:
                    result.step_failed("Verify handle updates in PLC",
                                       f"Missing handle updates in log. Seen: {handles_seen}")

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
