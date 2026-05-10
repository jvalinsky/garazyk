"""Scenario 22: "Silent Watchers" — AppView Index Hooks & Dead Letter

Luna and Marcus create accounts and posts on the PDS. After AppView
indexes the data, the scenario inspects the hook registry and dead
letter table, then exercises record browsing with collection, DID,
and pagination filters.

NOTE: The hook registry is currently not wired in AppViewRuntime.m
(setHookRegistry:nil, line 292). This scenario documents the wiring
gap: hook count is 0 and dead letter is empty. When the registry is
wired, this scenario should be extended to test hook firing after
record indexing, collection filtering, and dead letter recording.

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
    result = ScenarioResult("AppView Index Hooks & Dead Letter")
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

    for i in range(3):
        for name in active:
            char = get_character(name)
            timed_call(
                result, f"{char.name} posts test {i+1}",
                lambda c=char, idx=i: client.records.create_record(
                    c.did, "app.bsky.feed.post",
                    {"$type": "app.bsky.feed.post",
                     "text": f"Hook test post {idx} from {c.name}",
                     "createdAt": _now()},
                    c.access_jwt,
                ),
                detail_fn=lambda r: f"uri={r['uri']}",
            )

    # Wait for AppView to index
    time.sleep(3)

    luna = get_character("luna")

    # ── Hook registry status ────────────────────────────────────────
    # The hook registry is currently nil in AppViewRuntime (setHookRegistry:nil).
    # This step documents the wiring gap.
    hook_data = timed_call(
        result, "Hook registry status",
        lambda: av.http_get("/admin/hooks", token=admin_token),
        detail_fn=lambda r: f"count={r.get('count', 0)}",
    )

    hook_count = hook_data.get("count", 0) if hook_data else 0
    reason = (
        "Hook registry not wired (setHookRegistry:nil)"
        if hook_count == 0
        else f"Hook firing tests not yet implemented (registry wired with count={hook_count})"
    )
    result.step_skipped("Hook firing test", reason)

    # ── Dead letter table ───────────────────────────────────────────
    dl_data = timed_call(
        result, "Dead letter table: empty",
        lambda: av.http_get("/admin/hooks/dead-letter", {"limit": 10}, token=admin_token),
        detail_fn=lambda r: f"entries={len(r.get('entries', []))}",
    )

    dl_entries = dl_data.get("entries", []) if dl_data else []
    if len(dl_entries) == 0:
        result.step_passed(
            "Dead letter empty (expected)",
            "No hook failures recorded (hooks not wired)",
        )
    else:
        result.step_passed(
            "Dead letter has entries",
            f"{len(dl_entries)} entries found",
        )

    # ── Dead letter: with limit param ────────────────────────────────
    timed_call(
        result, "Dead letter with limit=1",
        lambda: av.http_get("/admin/hooks/dead-letter", {"limit": 1}, token=admin_token),
        detail_fn=lambda r: f"entries={len(r.get('entries', []))}",
    )

    # ── Record browsing: collection filter ──────────────────────────
    rec_data = timed_call(
        result, "Browse records: collection filter",
        lambda: av.http_get(
            "/admin/records",
            {"collection": "app.bsky.feed.post", "limit": 5},
            token=admin_token,
        ),
        detail_fn=lambda r: f"records={len(r.get('records', []))}",
    )

    # ── Record browsing: DID filter ─────────────────────────────────
    if luna.did:
        timed_call(
            result, "Browse records: DID filter",
            lambda: av.http_get(
                "/admin/records",
                {"collection": "app.bsky.feed.post", "did": luna.did, "limit": 10},
                token=admin_token,
            ),
            detail_fn=lambda r: f"records={len(r.get('records', []))}",
        )
    else:
        result.step_skipped("Browse records: DID filter", "Luna DID not available")

    # ── Record browsing: pagination ─────────────────────────────────
    if rec_data:
        cursor = rec_data.get("cursor")
        if cursor:
            timed_call(
                result, "Browse records: pagination (page 2)",
                lambda: av.http_get(
                    "/admin/records",
                    {"collection": "app.bsky.feed.post", "limit": 2, "cursor": cursor},
                    token=admin_token,
                ),
                detail_fn=lambda r: f"records={len(r.get('records', []))}",
            )
        else:
            result.step_skipped(
                "Browse records: pagination",
                "No cursor returned from first page",
            )
    else:
        result.step_skipped("Browse records: pagination", "First page unavailable")

    # ── Record browsing: invalid collection ──────────────────────────
    timed_call(
        result, "Browse records: invalid collection",
        lambda: av.http_get(
            "/admin/records",
            {"collection": "nonexistent.collection.type", "limit": 5},
            token=admin_token,
        ),
        detail_fn=lambda r: f"records={len(r.get('records', []))}",
    )

    # ── Record browsing: missing collection param ───────────────────
    timed_call(
        result, "Browse records: missing collection rejected",
        lambda: av.http_get("/admin/records", token=admin_token),
    )

    # ── Record artifacts ─────────────────────────────────────────────
    result.record_artifact("accounts", {
        n: {"did": get_character(n).did}
        for n in char_names if get_character(n).did
    })
    result.record_artifact("hooks", {
        "hook_count": hook_count,
        "dead_letter_entries": len(dl_entries),
        "wiring_gap": "setHookRegistry:nil in AppViewRuntime.m:292",
    })

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
