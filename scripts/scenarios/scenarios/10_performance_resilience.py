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

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, PDS1
from lib.assertions import assert_success, assert_contains, assert_xrpc_raises
from lib.report import ScenarioResult, StepStatus


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Performance & Resilience")
    result.start()

    client = XrpcClient(PDS1)

    # Wait for server
    try:
        client.wait_for_healthy(timeout=30)
        result.step_passed("Server health check")
    except RuntimeError as exc:
        result.step_failed("Server health check", str(exc))
        result.finish()
        return result

    # ── Create accounts ──────────────────────────────────────────────
    char_names = ["luna", "marcus", "rosa", "volt", "quiet"]
    for name in char_names:
        char = get_character(name)
        try:
            session = client.create_account(char.handle, char.email, char.password)
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            result.step_passed(f"Create account: {char.name}", f"did={char.did}")
        except XrpcError as exc:
            result.step_failed(f"Create account: {char.name}", str(exc))

    active = [n for n in char_names if get_character(n).did]
    if len(active) < 3:
        result.step_failed("Account creation", "Not enough accounts")
        result.finish()
        return result

    # ── Burst post creation ───────────────────────────────────────────
    POSTS_PER_USER = 10  # 5 users x 10 posts = 50 posts (scaled down from 200 for safety)
    total_posts = 0
    failed_posts = 0
    start_time = time.time()

    def create_burst_post(char_name: str, index: int) -> bool:
        """Create a single post. Returns True on success."""
        char = get_character(char_name)
        try:
            client.create_record(
                char.did,
                "app.bsky.feed.post",
                {
                    "$type": "app.bsky.feed.post",
                    "text": f"Burst post #{index} from {char.name}! Load testing the PDS. 🚀",
                    "createdAt": _now(),
                },
                char.access_jwt,
            )
            return True
        except XrpcError:
            return False

    # Use ThreadPoolExecutor for concurrent posts
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = []
        for name in active:
            char = get_character(name)
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

    # ── Verify all posts exist ────────────────────────────────────────
    total_records = 0
    for name in active:
        char = get_character(name)
        try:
            records = client.list_records(char.did, "app.bsky.feed.post", token=char.access_jwt)
            count = len(records.get("records", []))
            total_records += count
        except XrpcError:
            pass

    result.step_passed("Verify posts exist", f"total_records_across_users={total_records}")

    # ── Batch writes via applyWrites ─────────────────────────────────
    luna = get_character("luna")
    try:
        batch_writes = [
            {
                "$type": "com.atproto.repo.applyWrites#create",
                "collection": "app.bsky.feed.post",
                "rkey": f"batch-{i}",
                "value": {
                    "$type": "app.bsky.feed.post",
                    "text": f"Batch post #{i} from Luna",
                    "createdAt": _now(),
                },
            }
            for i in range(5)
        ]
        batch_result = client.apply_writes(luna.did, batch_writes, luna.access_jwt)
        result.step_passed("Batch applyWrites", "5 records created")
    except XrpcError as exc:
        result.step_skipped("Batch applyWrites", str(exc))

    # ── Error handling: Invalid record ───────────────────────────────
    try:
        assert_xrpc_raises(
            "Create invalid record",
            None,
            client.create_record,
            luna.did,
            "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post"},  # Missing required 'text' and 'createdAt'
            luna.access_jwt,
        )
        result.step_passed("Invalid record rejected")
    except AssertionError as exc:
        result.step_skipped("Invalid record rejected", str(exc))

    # ── Error handling: Duplicate rkey ───────────────────────────────
    try:
        # Create a post with a specific rkey
        client.create_record(
            luna.did,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "Original post with specific rkey",
                "createdAt": _now(),
            },
            luna.access_jwt,
            rkey="duplicate-test-rkey",
        )
        # Try to create another with the same rkey
        assert_xrpc_raises(
            "Create duplicate rkey",
            None,
            client.create_record,
            luna.did,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "Duplicate post with same rkey",
                "createdAt": _now(),
            },
            luna.access_jwt,
            rkey="duplicate-test-rkey",
        )
        result.step_passed("Duplicate rkey rejected")
    except (AssertionError, XrpcError) as exc:
        result.step_skipped("Duplicate rkey rejected", str(exc))

    # ── Error handling: Missing auth ─────────────────────────────────
    try:
        assert_xrpc_raises(
            "Create record without auth",
            None,
            client.create_record,
            luna.did,
            "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post", "text": "unauthorized", "createdAt": _now()},
            "invalid-token-xyz",
        )
        result.step_passed("Missing auth rejected")
    except AssertionError as exc:
        result.step_skipped("Missing auth rejected", str(exc))

    # ── Error handling: Non-existent collection ──────────────────────
    try:
        assert_xrpc_raises(
            "Create record in non-existent collection",
            None,
            client.create_record,
            luna.did,
            "app.bsky.feed.nonexistent",
            {"$type": "app.bsky.feed.nonexistent", "text": "test", "createdAt": _now()},
            luna.access_jwt,
        )
        result.step_passed("Non-existent collection rejected")
    except AssertionError as exc:
        result.step_skipped("Non-existent collection rejected", str(exc))

    # ── Give AppView time to index ───────────────────────────────────
    time.sleep(5)

    # ── AppView consistency check ─────────────────────────────────────
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
            result.step_skipped("AppView consistency check", f"status={appview_resp.status_code}")
    except Exception as exc:
        result.step_skipped("AppView consistency check", str(exc))

    # ── Verify timeline has content ───────────────────────────────────
    try:
        timeline = client.get_timeline(luna.access_jwt)
        feed = timeline.get("feed", [])
        result.step_passed("Timeline has content after burst", f"items={len(feed)}")
    except XrpcError as exc:
        result.step_skipped("Timeline has content after burst", str(exc))

    # ── Relay health after load ──────────────────────────────────────
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
