"""Scenario 23: "Pass-Through" — AppView Write Proxy & OAuth2 Middleware

Luna creates an account and posts on the PDS. The scenario then
exercises the AppView's write proxy surface (currently unwired —
procedures return 501 without a custom handler) and OAuth2 middleware
behavior through existing domain-specific endpoints.

NOTE: The write proxy and OAuth2 middleware are not wired in
AppViewRuntime.m. This scenario documents the current behavior and
will be extended when the features are wired.

Services: PDS, AppView, Relay
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, SERVICE_URLS, APPVIEW_ADMIN_SECRET, ScenarioResult, timed_call



def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("AppView Write Proxy & OAuth2")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "PDS health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # Admin HTTP client pointed at the AppView
    av_url = SERVICE_URLS["appview"]
    admin_token = APPVIEW_ADMIN_SECRET
    av = XrpcClient(av_url)

    # ── AppView health check ────────────────────────────────────────
    timed_call(
        result, "AppView health check",
        lambda: av.http_get("/admin/backfill/status", token=admin_token),
        detail_fn=lambda r: f"enabled={r.get('enabled', False)}",
    )

    # ── Create accounts and posts ───────────────────────────────────
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

    active = [n for n in char_names if get_character(n).did]
    if len(active) < 1:
        result.step_failed("Account creation", "No accounts created")
        result.finish()
        return result

    # Set profiles and create posts
    for name in active:
        char = get_character(name)
        timed_call(result, f"Set profile: {char.name}",
                   lambda c=char: client.records.create_record(
                       c.did, "app.bsky.actor.profile",
                       {"$type": "app.bsky.actor.profile", "displayName": c.name},
                       c.access_jwt),
                   skip_on_status={404})

    luna = get_character("luna")
    if luna.did and luna.access_jwt:
        timed_call(
            result, "Luna creates a post",
            lambda: client.records.create_record(
                luna.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post",
                 "text": "Write proxy test post from Luna",
                 "createdAt": _now()},
                luna.access_jwt,
            ),
            detail_fn=lambda r: f"uri={r['uri']}",
        )

    # Wait for AppView to index
    time.sleep(3)

    # ── AppView backfill status ─────────────────────────────────────
    timed_call(
        result, "Backfill status",
        lambda: av.http_get("/admin/backfill/status", token=admin_token),
        detail_fn=lambda r: f"enabled={r.get('enabled', False)}",
    )

    # ── AppView ingest health ───────────────────────────────────────
    timed_call(
        result, "Ingest engine health",
        lambda: av.http_get("/admin/ingest/health", token=admin_token),
        detail_fn=lambda r: f"running={r.get('running', False)}",
    )

    # ── Write proxy surface: procedure on AppView ──────────────────
    # The write proxy is not wired in AppViewRuntime.m. The
    # GenericQueryHandler returns 501 for procedures without a custom
    # handler. This documents the current behavior.
    if luna.did and luna.access_jwt:
        timed_call(
            result, "Write proxy: createRecord on AppView (unwired)",
            lambda: av.http_post(
                "/xrpc/com.atproto.repo.createRecord",
                body={
                    "repo": luna.did,
                    "collection": "app.bsky.feed.post",
                    "record": {
                        "$type": "app.bsky.feed.post",
                        "text": "Proxied post attempt",
                        "createdAt": _now(),
                    },
                },
                token=luna.access_jwt,
            ),
        )
    else:
        result.step_skipped(
            "Write proxy: createRecord on AppView",
            "Luna account not available",
        )

    # ── OAuth2 middleware: Bearer token passthrough ────────────────
    # Domain-specific handlers (AppViewXRpcRoutePack) validate JWTs
    # themselves. This tests that the AppView accepts and forwards
    # valid PDS-issued access tokens.
    if luna.did and luna.access_jwt:
        timed_call(
            result, "OAuth2: valid Bearer token on AppView",
            lambda: av.http_get(
                f"/xrpc/app.bsky.actor.getProfile",
                {"actor": luna.did},
                token=luna.access_jwt,
            ),
            detail_fn=lambda r: f"handle={r.get('handle', 'unknown')}",
            skip_on_status={404},
        )
    else:
        result.step_skipped(
            "OAuth2: valid Bearer token on AppView",
            "Luna account not available",
        )

    # ── OAuth2 middleware: DID-as-token ─────────────────────────────
    # AppViewOAuth2Middleware accepts raw DIDs as Bearer tokens for
    # dev/testing. This only works if the OAuth2 middleware is wired
    # as a middleware layer. Domain-specific handlers use their own
    # JWT validation, so raw DID tokens won't work for those endpoints.
    # We test the endpoint behavior regardless.
    if luna.did:
        timed_call(
            result, "OAuth2: DID-as-token on AppView",
            lambda: av.http_get(
                f"/xrpc/app.bsky.actor.getProfile",
                {"actor": luna.did},
                token=luna.did,
            ),
            detail_fn=lambda r: f"status=200 (middleware bypass accepted)",
            skip_on_status={401, 403},
        )
    else:
        result.step_skipped("OAuth2: DID-as-token on AppView", "Luna DID not available")

    # ── OAuth2 middleware: invalid token ────────────────────────────
    timed_call(
        result, "OAuth2: invalid Bearer token on AppView",
        lambda: av.http_get(
            "/xrpc/app.bsky.actor.getProfile",
            {"actor": luna.did or "did:plc:unknown"},
            token="invalid-garbage-token-xyz",
        ),
    )

    # ── Admin: endpoint counts after operations ─────────────────────
    ep_data = timed_call(
        result, "Endpoint counts after operations",
        lambda: av.http_get("/admin/endpoints", token=admin_token),
        detail_fn=lambda r: f"dynamic={r.get('dynamic_endpoint_count', 0)}, custom={r.get('custom_handler_count', 0)}",
    )

    # ── Admin: metrics ──────────────────────────────────────────────
    timed_call(
        result, "AppView metrics",
        lambda: av.http_get("/admin/appview/metrics/stats", token=admin_token),
        detail_fn=lambda r: f"repos_total={r.get('repos', {}).get('total', 0)}, queue_depth={r.get('queue_depth', 0)}",
    )

    # ── Record artifacts ─────────────────────────────────────────────
    result.record_artifact("accounts", {
        n: {"did": get_character(n).did}
        for n in char_names if get_character(n).did
    })
    result.record_artifact("write_proxy_oauth2", {
        "write_proxy_wired": False,
        "oauth2_middleware_wired": False,
        "wiring_gap": "AppViewWriteProxy and AppViewOAuth2Middleware not instantiated in AppViewRuntime.m",
    })

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
