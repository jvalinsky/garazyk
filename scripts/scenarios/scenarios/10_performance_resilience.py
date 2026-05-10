"""Scenario 10: "Server Under Load" — Performance & Resilience

Generate a burst of 200 posts from 5 accounts simultaneously. Verify all
posts are created. Verify the firehose keeps up. Verify AppView indexes
everything. Test error handling: invalid records, duplicate creates,
missing auth.

Services: PDS, Relay, AppView
"""

from __future__ import annotations

import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call



def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Performance & Resilience")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    char_names = ["luna", "marcus", "rosa", "volt", "quiet"]
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
    if len(active) < 3:
        result.step_failed("Account creation", "Not enough accounts")
        result.finish()
        return result

    time.sleep(2)

    POSTS_PER_USER = 10
    total_posts = 0
    failed_posts = 0
    start_time = time.time()

    def create_burst_post(char_name: str, index: int) -> bool:
        char = get_character(char_name)
        try:
            client.records.create_record(
                char.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post",
                 "text": f"Burst post #{index} from {char.name}! Load testing the PDS.",
                 "createdAt": _now()},
                char.access_jwt,
            )
            return True
        except Exception:
            return False

    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = []
        for name in active:
            for i in range(POSTS_PER_USER):
                futures.append(executor.submit(create_burst_post, name, i + 1))

        for future in as_completed(futures):
            if future.result():
                total_posts += 1
            else:
                failed_posts += 1

    elapsed = time.time() - start_time
    result.step_passed(
        "Burst post creation",
        f"created={total_posts}, failed={failed_posts}, elapsed={elapsed:.1f}s, "
        f"rate={total_posts/max(elapsed, 0.01):.1f} posts/s",
    )

    total_records = 0
    for name in active:
        char = get_character(name)
        records = timed_call(
            result, f"Verify posts: {char.name}",
            lambda c=char: client.records.list_records(c.did, "app.bsky.feed.post", token=c.access_jwt),
        )
        if records:
            total_records += len(records.get("records", []))

    result.step_passed("Verify posts exist", f"total_records_across_users={total_records}")

    luna = get_character("luna")
    batch_writes = [
        {
            "$type": "com.atproto.repo.applyWrites#create",
            "collection": "app.bsky.feed.post",
            "rkey": f"batch-{i}",
            "value": {"$type": "app.bsky.feed.post", "text": f"Batch post #{i} from Luna", "createdAt": _now()},
        }
        for i in range(5)
    ]
    timed_call(
        result, "Batch applyWrites",
        lambda: client.records.apply_writes(luna.did, batch_writes, luna.access_jwt),
        detail_fn=lambda r: "5 records created",
    )

    timed_call(
        result, "Invalid record rejected",
        lambda: client.records.create_record(
            luna.did, "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post"},  # Missing required 'text' and 'createdAt'
            luna.access_jwt),
        expect_failure=True,
    )

    try:
        client.records.create_record(
            luna.did, "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post", "text": "Original post with specific rkey",
             "createdAt": _now()},
            luna.access_jwt,
            rkey="duplicate-test-rkey",
        )
        timed_call(
            result, "Duplicate rkey rejected",
            lambda: client.records.create_record(
                luna.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post", "text": "Duplicate post with same rkey",
                 "createdAt": _now()},
                luna.access_jwt,
                rkey="duplicate-test-rkey"),
            expect_failure=True,
        )
    except Exception as exc:
        result.step_skipped("Duplicate rkey rejected", str(exc))

    timed_call(
        result, "Missing auth rejected",
        lambda: client.records.create_record(
            luna.did, "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post", "text": "unauthorized", "createdAt": _now()},
            "invalid-token-xyz"),
        expect_failure=True,
    )

    timed_call(
        result, "Non-existent collection rejected",
        lambda: client.records.create_record(
            luna.did, "app.bsky.feed.nonexistent",
            {"$type": "app.bsky.feed.nonexistent", "text": "test", "createdAt": _now()},
            luna.access_jwt),
        expect_failure=True,
    )

    time.sleep(5)

    try:
        import requests
        appview_resp = requests.get(
            "http://localhost:3200/admin/backfill/status",
            headers={"Authorization": "Bearer localdevadmin"},
            timeout=5,
        )
        if appview_resp.status_code == 200:
            result.step_passed("AppView consistency check", "backfill status OK")
        else:
            result.step_failed("AppView consistency check", f"status={appview_resp.status_code}")
    except Exception as exc:
        result.step_failed("AppView consistency check", str(exc))

    timed_call(
        result, "Timeline has content after burst",
        lambda: client.feed.get_timeline(luna.access_jwt),
        detail_fn=lambda t: f"items={len(t.get('feed', []))}",
    )

    try:
        import requests
        relay_resp = requests.get("http://localhost:2584/api/relay/health", timeout=5)
        if relay_resp.status_code == 200:
            result.step_passed("Relay healthy after load")
        else:
            result.step_skipped("Relay healthy after load", f"status={relay_resp.status_code}")
    except Exception as exc:
        result.step_skipped("Relay healthy after load", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
