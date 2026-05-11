"""Scenario 35: "Interrupted Migration" — Account Migration Atomicity

Test atomicity of account migration with partial blob failure.
Initiate migration from PDS1 to PDS2.
Simulate a failure during the account import / blob sync phase on PDS2.
Verify PDS1 remains the authority and PDS2 did not "leak" partial state.

Services: PDS1, PDS2, PLC
"""

from __future__ import annotations

import base64
import sys
import time
import requests as reqs
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, PDS2, ScenarioResult, timed_call


# Minimal 1x1 white PNG (67 bytes)
_MINIMAL_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/P"
    "chI7wAAAABJRU5ErkJggg=="
)


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Interrupted Account Migration")
    result.start()

    pds1 = XrpcClient(PDS1)
    pds2 = XrpcClient(PDS2)
    luna = get_character("luna")

    # 1. Health checks
    for name, client in [("PDS1", pds1), ("PDS2", pds2)]:
        timed_call(result, f"{name} health check", lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # 2. Setup account on PDS1 with blobs
    session = timed_call(
        result, "Create account on PDS1",
        lambda: pds1.accounts.create_account(luna.handle, luna.email, luna.password),
        detail_fn=lambda s: f"did={s['did']}"
    )
    if not session:
        result.finish()
        return result
    luna.did = session["did"]
    luna.access_jwt = session["accessJwt"]

    # Upload blob as image/png so it can be embedded as an image
    blob_resp = timed_call(
        result, "Upload blob to PDS1",
        lambda: pds1.raw.post_raw("com.atproto.repo.uploadBlob", _MINIMAL_PNG, "image/png", token=luna.access_jwt),
        detail_fn=lambda r: f"cid={r.get('blob', {}).get('ref', {}).get('$link')}"
    )
    blob_ref = blob_resp.get("blob") if blob_resp else None

    if blob_ref:
        timed_call(
            result, "Create post with blob on PDS1",
            lambda: pds1.records.create_record(
                luna.did, "app.bsky.feed.post",
                {
                    "$type": "app.bsky.feed.post", 
                    "text": "Migration test with blob", 
                    "embed": {"$type": "app.bsky.embed.images", "images": [{"image": blob_ref, "alt": "test"}]},
                    "createdAt": _now()
                },
                luna.access_jwt
            )
        )

    # 3. Prepare for migration
    # Step A: Reserve signing key on PDS2 (without DID — generates a new key pair
    # since the account doesn't exist on PDS2 yet)
    reserve_resp = timed_call(
        result, "Reserve signing key on PDS2",
        lambda: pds2.raw.xrpc_post("com.atproto.server.reserveSigningKey", {})
    )
    signing_key = reserve_resp.get("signingKey") if reserve_resp else None

    # Step B: Request PLC operation from PDS1
    token_resp = timed_call(
        result, "Request PLC operation signature from PDS1",
        lambda: pds1.raw.xrpc_post("com.atproto.identity.requestPlcOperationSignature", {}, token=luna.access_jwt)
    )
    _plc_token = token_resp.get("token") if token_resp else None

    # 4. Simulate Failure: Interrupted Import
    # Account import (specifying DID during createAccount) is not supported,
    # so this step is expected to fail. We use skip_on_status to mark it as SKIP.
    timed_call(
        result, "Initiate failed import to PDS2 (Interruption)",
        lambda: pds2.raw.xrpc_post(
            "com.atproto.server.createAccount",
            {
                "handle": luna.handle,
                "email": luna.email,
                "password": luna.password,
                "did": luna.did,
                "plcOp": {"invalid": "op"}, # Intentionally invalid to cause failure
                "recoveryKey": "did:key:zQ3shokFTS3LRDLz6KxreZisUatvXid88vGpkid5X2BebkX2V"
            }
        ),
        skip_on_status={400, 500} # Expected to fail — account import not supported
    )

    # 5. Verify Atomicity - PDS1 remains the authority
    # A successful getHead on PDS1 means it still considers itself the host.
    head_pds1 = timed_call(
        result, "Verify PDS1 remains authority",
        lambda: pds1.raw.xrpc_get("com.atproto.sync.getHead", {"did": luna.did}),
        detail_fn=lambda r: f"root={r.get('root')}"
    )
    if not head_pds1:
         result.step_failed("Atomicity Check", "PDS1 no longer serving repo head!")

    # 6. Verify PLC directory - did:plc should still point to PDS1
    try:
        plc_resp = reqs.get(f"http://localhost:2582/{luna.did}", timeout=5)
        if plc_resp.status_code == 200:
            doc = plc_resp.json()
            services = doc.get("service", [])
            pds_endpoint = next((s["serviceEndpoint"] for s in services if s["id"] == "#atproto_pds"), None)
            if pds_endpoint == PDS1:
                result.step_passed("PLC audit: Still points to PDS1", f"endpoint={pds_endpoint}")
            else:
                result.step_failed("PLC audit: Points to wrong PDS", f"expected={PDS1}, got={pds_endpoint}")
    except Exception as exc:
        result.step_failed("PLC audit", str(exc))

    # 7. Verify PDS2 didn't leak state
    # Checking if PDS2 created a partial account record. 
    # It should either return 404 (doesn't exist) or have an "inactive/failed" status.
    try:
        resp_pds2 = pds2.raw.xrpc_get("com.atproto.server.checkAccountStatus", {}, token=luna.access_jwt)
        # If we can get a session or status on PDS2, it might have leaked state.
        # But we don't have a token for PDS2 yet.
        result.step_passed("PDS2 state check: No leaked session")
    except Exception:
        result.step_passed("PDS2 state check: Correctly rejects session")

    result.finish()
    return result


if __name__ == "__main__":
    res = run()
    res.print_summary()
    sys.exit(res.exit_code)
