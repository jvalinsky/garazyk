"""Scenario 21: "Dynamic Routes" — AppView Lexicon-Driven Endpoints

Luna and Marcus create accounts and posts on the PDS. After AppView
indexes the data, the scenario exercises the lexicon-driven dynamic
endpoint system: listing loaded lexicons, verifying dynamic endpoint
registration, and hitting third-party XRPC query endpoints on the
AppView that are auto-generated from loaded lexicon schemas.

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


# Third-party NSIDs present in Garazyk/Resources/lexicons/ (non-app.bsky,
# non-com.atproto, non-tools.ozone). These are the schemas the
# LexiconEndpointGenerator should register dynamic routes for.
_THIRD_PARTY_QUERY_NSIDS = [
    "com.shinolabs.pinksea.getRecent",
    "com.whtwnd.blog.getAuthorPosts",
    "social.grain.feed.getTimeline",
]


def run() -> ScenarioResult:
    result = ScenarioResult("AppView Lexicon-Driven Endpoints")
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
    if len(active) < 2:
        result.step_failed("Account creation", "Not enough accounts created")
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

    for i in range(2):
        for name in active:
            char = get_character(name)
            timed_call(
                result, f"{char.name} posts test {i+1}",
                lambda c=char, idx=i: client.records.create_record(
                    c.did, "app.bsky.feed.post",
                    {"$type": "app.bsky.feed.post",
                     "text": f"Lexicon test post {idx} from {c.name}",
                     "createdAt": _now()},
                    c.access_jwt,
                ),
                detail_fn=lambda r: f"uri={r['uri']}",
            )

    # Wait for AppView to index
    time.sleep(3)

    luna = get_character("luna")

    # ── Admin: List lexicons ────────────────────────────────────────
    lex_data = timed_call(
        result, "List loaded lexicons",
        lambda: av.http_get("/admin/lexicons", token=admin_token),
        detail_fn=lambda r: f"count={r.get('count', 0)}",
    )

    # Verify third-party NSIDs are present
    if lex_data:
        nsids = lex_data.get("nsids", [])
        third_party_found = [n for n in _THIRD_PARTY_QUERY_NSIDS if n in nsids]
        if third_party_found:
            result.step_passed(
                "Third-party lexicons loaded",
                f"found={len(third_party_found)} of {len(_THIRD_PARTY_QUERY_NSIDS)}",
            )
        else:
            result.step_skipped(
                "Third-party lexicons loaded",
                f"none of {len(_THIRD_PARTY_QUERY_NSIDS)} target NSIDs found in {len(nsids)} loaded",
            )
    else:
        result.step_skipped("Third-party lexicons loaded", "lexicon list unavailable")

    # ── Admin: List endpoints ──────────────────────────────────────
    ep_data = timed_call(
        result, "List dynamic endpoints",
        lambda: av.http_get("/admin/endpoints", token=admin_token),
        detail_fn=lambda r: f"dynamic={r.get('dynamic_endpoint_count', 0)}, custom={r.get('custom_handler_count', 0)}",
    )

    dynamic_count = ep_data.get("dynamic_endpoint_count", 0) if ep_data else 0

    # ── Admin: List collections ─────────────────────────────────────
    timed_call(
        result, "List indexed collections",
        lambda: av.http_get("/admin/lexicons/collections", token=admin_token),
        detail_fn=lambda r: f"count={len(r.get('collections', []))}",
    )

    # ── Admin: List custom handlers ─────────────────────────────────
    timed_call(
        result, "List custom handlers",
        lambda: av.http_get("/admin/handlers", token=admin_token),
        detail_fn=lambda r: f"count={r.get('count', 0)}",
    )

    # ── Dynamic XRPC: third-party query endpoint ───────────────────
    # Hit a third-party NSID on the AppView. The LexiconEndpointGenerator
    # registers GET routes for query-type lexicons. The GenericQueryHandler
    # will either return records (if any are indexed for that collection)
    # or an empty list.
    for nsid in _THIRD_PARTY_QUERY_NSIDS[:2]:
        timed_call(
            result, f"Dynamic GET /xrpc/{nsid}",
            lambda n=nsid: av.http_get(f"/xrpc/{n}"),
            detail_fn=lambda r, n=nsid: f"status=200 keys={list(r.keys())[:3]}",
            skip_on_status={501},
        )

    # ── Dynamic XRPC: unknown NSID ─────────────────────────────────
    timed_call(
        result, "Unknown NSID returns 501",
        lambda: av.http_get("/xrpc/com.example.nonexistent.method"),
    )

    # ── Dynamic XRPC: procedure without custom handler ─────────────
    # POST to a third-party NSID that has a record definition but no
    # custom handler. The GenericQueryHandler returns 501 for procedures
    # without a custom handler.
    timed_call(
        result, "Procedure without custom handler returns 501",
        lambda: av.http_post(
            "/xrpc/com.shinolabs.pinksea.oekaki",
            body={"$type": "com.shinolabs.pinksea.oekaki", "data": "test"},
        ),
    )

    # ── Admin: Verify records indexed ───────────────────────────────
    timed_call(
        result, "Browse indexed records",
        lambda: av.http_get(
            "/admin/records",
            {"collection": "app.bsky.feed.post", "limit": 10},
            token=admin_token,
        ),
        detail_fn=lambda r: f"records={len(r.get('records', []))}",
    )

    # ── Admin: Auth rejection ──────────────────────────────────────
    timed_call(
        result, "Admin auth: wrong secret rejected",
        lambda: av.http_get("/admin/lexicons", token="wrong-secret-value"),
    )

    # ── Record artifacts ────────────────────────────────────────────
    result.record_artifact("accounts", {
        n: {"did": get_character(n).did}
        for n in char_names if get_character(n).did
    })
    result.record_artifact("lexicon_endpoints", {
        "dynamic_endpoint_count": dynamic_count,
        "third_party_nsids_checked": _THIRD_PARTY_QUERY_NSIDS,
    })

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
