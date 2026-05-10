"""Scenario 18: "Under the Hood" — AppView Admin Operations

Admin Sentinel inspects the AppView: backfill status, ingest health,
metrics, lexicons, collections, records, hooks, endpoints, and handlers.

Services: AppView (admin HTTP on port 3200)
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
    result = ScenarioResult("AppView Admin Operations")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # Admin HTTP client
    av_url = SERVICE_URLS["appview"]
    admin_token = APPVIEW_ADMIN_SECRET
    av = XrpcClient(av_url)

    # ── Seed a little data first ─────────────────────────────────────
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
    if active:
        for name in active:
            char = get_character(name)
            timed_call(result, f"Set profile: {char.name}",
                       lambda c=char: client.records.create_record(
                           c.did, "app.bsky.actor.profile",
                           {"$type": "app.bsky.actor.profile", "displayName": c.name},
                           c.access_jwt),
                       skip_on_status={404})

        for i in range(3):
            for name in active:
                char = get_character(name)
                timed_call(
                    result, f"{char.name} posts test {i+1}",
                    lambda c=char, n=name, idx=i: client.records.create_record(
                        c.did, "app.bsky.feed.post",
                        {"$type": "app.bsky.feed.post", "text": f"Test post {idx} from {n}", "createdAt": _now()},
                        c.access_jwt,
                    ),
                    detail_fn=lambda r: f"uri={r['uri']}",
                )

        time.sleep(2)

    # ── 1. Ingest health ─────────────────────────────────────────────
    timed_call(
        result, "Ingest engine health",
        lambda: av.http_get("/admin/ingest/health", token=admin_token),
        detail_fn=lambda r: f"running={r.get('running', False)}",
    )

    # ── 2. Backfill status ───────────────────────────────────────────
    timed_call(
        result, "Backfill status",
        lambda: av.http_get("/admin/backfill/status", token=admin_token),
        detail_fn=lambda r: f"enabled={r.get('enabled', False)}",
    )

    # ── 3. Backfill queue ────────────────────────────────────────────
    timed_call(
        result, "Backfill queue",
        lambda: av.http_get("/admin/backfill/queue", {"limit": 10}, token=admin_token),
        detail_fn=lambda r: f"entries={len(r.get('entries', []))}, total={r.get('total', 0)}",
    )

    # ── 4. Metrics stats ─────────────────────────────────────────────
    timed_call(
        result, "Metrics stats",
        lambda: av.http_get("/admin/appview/metrics/stats", token=admin_token),
        detail_fn=lambda r: f"repos_total={r.get('repos', {}).get('total', 0)}, queue_depth={r.get('queue_depth', 0)}",
    )

    # ── 5. List lexicons ─────────────────────────────────────────────
    timed_call(
        result, "List lexicons",
        lambda: av.http_get("/admin/lexicons", token=admin_token),
        detail_fn=lambda r: f"count={r.get('count', 0)}",
    )

    # ── 6. List collections ──────────────────────────────────────────
    timed_call(
        result, "List collections",
        lambda: av.http_get("/admin/lexicons/collections", token=admin_token),
        detail_fn=lambda r: f"count={len(r.get('collections', []))}",
    )

    # ── 7. Browse records ────────────────────────────────────────────
    timed_call(
        result, "Browse records",
        lambda: av.http_get("/admin/records", {"collection": "app.bsky.feed.post", "limit": 10}, token=admin_token),
        detail_fn=lambda r: f"records={len(r.get('records', []))}",
    )

    # ── 8. Browse records error path (no collection) ────────────────
    timed_call(
        result, "Browse records without collection rejected",
        lambda: av.http_get("/admin/records", token=admin_token),
    )

    # ── 9. List endpoints ────────────────────────────────────────────
    timed_call(
        result, "List endpoints",
        lambda: av.http_get("/admin/endpoints", token=admin_token),
        detail_fn=lambda r: f"dynamic={r.get('dynamic_endpoint_count', 0)}, custom={r.get('custom_handler_count', 0)}",
    )

    # ── 10. List hooks ───────────────────────────────────────────────
    timed_call(
        result, "List hooks",
        lambda: av.http_get("/admin/hooks", token=admin_token),
        detail_fn=lambda r: f"count={r.get('count', 0)}",
    )

    # ── 11. Dead letter hooks ────────────────────────────────────────
    timed_call(
        result, "Dead letter hooks",
        lambda: av.http_get("/admin/hooks/dead-letter", {"limit": 10}, token=admin_token),
        detail_fn=lambda r: f"entries={len(r.get('entries', []))}",
    )

    # ── 12. List handlers ────────────────────────────────────────────
    timed_call(
        result, "List handlers",
        lambda: av.http_get("/admin/handlers", token=admin_token),
        detail_fn=lambda r: f"count={r.get('count', 0)}",
    )

    # ── 13. Backfill scope rebuild ───────────────────────────────────
    timed_call(
        result, "Backfill scope rebuild",
        lambda: av.http_post("/admin/backfill/scope/rebuild", token=admin_token),
        detail_fn=lambda r: f"success={r.get('success', False)}",
    )

    # ── 14. Unauthorized access ──────────────────────────────────────
    timed_call(
        result, "Admin access without token",
        lambda: av.http_get("/admin/backfill/status"),
    )

    # ── Record artifacts ─────────────────────────────────────────────
    result.record_artifact("accounts", {
        n: {"did": get_character(n).did}
        for n in char_names if get_character(n).did
    })
    result.record_artifact("admin_endpoints_checked", [
        "ingest/health", "backfill/status", "backfill/queue",
        "metrics/stats", "lexicons", "collections", "records",
        "endpoints", "hooks", "hooks/dead-letter", "handlers",
        "backfill/scope/rebuild", "unauthorized",
    ])

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
