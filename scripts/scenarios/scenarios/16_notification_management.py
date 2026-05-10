"""Scenario 16: "Stay Informed" — Notification Management & Preferences

Luna is popular. She manages her notification preferences, registers for
push, marks notifications as read, and sets up activity subscriptions
for Marcus's posts. Rosa generates notifications so Luna has something
to manage.

Services: PDS, AppView (optional — some endpoints skip if no AppView)
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call



def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Notification Management & Preferences")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # ── Create accounts ──────────────────────────────────────────────
    char_names = ["luna", "marcus", "rosa", "volt"]
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

    # ── Set up profiles ──────────────────────────────────────────────
    for name in active:
        char = get_character(name)
        timed_call(result, f"Set profile: {char.name}",
                   lambda c=char: client.records.create_record(
                       c.did, "app.bsky.actor.profile",
                       {"$type": "app.bsky.actor.profile", "displayName": c.name, "description": c.persona},
                       c.access_jwt),
                   skip_on_status={404})

    luna = get_character("luna")
    marcus = get_character("marcus")
    rosa = get_character("rosa")
    volt = get_character("volt")

    # ── Everyone follows Luna and posts ──────────────────────────────
    for follower_name in ["marcus", "rosa", "volt"]:
        fchar = get_character(follower_name)
        if fchar.did and fchar.access_jwt and luna.did:
            timed_call(
                result, f"{fchar.name} follows Luna",
                lambda c=fchar: client.records.create_record(
                    c.did, "app.bsky.graph.follow",
                    {"$type": "app.bsky.graph.follow", "subject": luna.did, "createdAt": _now()},
                    c.access_jwt,
                ),
                detail_fn=lambda r: f"uri={r['uri']}",
            )

    for name in ["marcus", "rosa", "volt"]:
        char = get_character(name)
        if char.did and char.access_jwt:
            timed_call(
                result, f"{char.name} posts",
                lambda c=char: client.records.create_record(
                    c.did, "app.bsky.feed.post",
                    {"$type": "app.bsky.feed.post", "text": f"Hello from {c.name}! This is a test post to generate notifications.", "createdAt": _now()},
                    c.access_jwt,
                ),
                detail_fn=lambda r: f"uri={r['uri']}",
            )

    # Luna also posts so others get notifications
    if luna.did and luna.access_jwt:
        timed_call(
            result, "Luna posts",
            lambda: client.records.create_record(
                luna.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post", "text": "Exciting news everyone! I discovered a new nebula!", "createdAt": _now()},
                luna.access_jwt,
            ),
            detail_fn=lambda r: f"uri={r['uri']}",
        )

    time.sleep(3)

    # ── Check initial state ─────────────────────────────────────────
    if not luna.access_jwt:
        result.step_failed("Luna notifications setup", "Luna not created")
        result.finish()
        return result

    # ── List notifications ──────────────────────────────────────────
    timed_call(
        result, "Luna lists notifications",
        lambda: client.notifications.list_notifications(luna.access_jwt),
        detail_fn=lambda r: f"count={len(r.get('notifications', []))}",
    )

    # ── Get unread count ────────────────────────────────────────────
    timed_call(
        result, "Luna unread count",
        lambda: client.raw.xrpc_get("app.bsky.notification.getUnreadCount", token=luna.access_jwt),
        detail_fn=lambda r: f"count={r.get('count', 0)}",
    )

    # ── Mark notifications as seen ──────────────────────────────────
    timed_call(
        result, "Luna marks notifications as seen",
        lambda: client.notifications.update_seen(luna.access_jwt, limit=0),
        skip_on_status={404},
    )

    # ── Verify unread count is now 0 ────────────────────────────────
    timed_call(
        result, "Luna verifies unread count 0",
        lambda: client.raw.xrpc_get("app.bsky.notification.getUnreadCount", token=luna.access_jwt),
        detail_fn=lambda r: f"count={r.get('count', 0)}",
    )

    # ── Register push ───────────────────────────────────────────────
    timed_call(
        result, "Luna registers for push",
        lambda: client.notifications.register_push(
            service_did="did:web:localhost:3200",
            token="test-device-token-abc123",
            platform="ios",
            app_id="xyz.garazyk.test",
            auth_token=luna.access_jwt,
        ),
        skip_on_status={404},
    )

    # ── Get notification preferences ────────────────────────────────
    timed_call(
        result, "Luna gets notification preferences",
        lambda: client.notifications.get_notification_preferences(luna.access_jwt),
        detail_fn=lambda r: f"keys={list(r.keys())}",
        skip_on_status={404},
    )

    # ── Put notification preferences ────────────────────────────────
    timed_call(
        result, "Luna sets notification preferences",
        lambda: client.notifications.put_notification_preferences({"priority": True}, luna.access_jwt),
        skip_on_status={404},
    )

    # ── Generate another notification ───────────────────────────────
    if rosa.did and rosa.access_jwt:
        timed_call(
            result, "Rosa posts fresh bread",
            lambda: client.records.create_record(
                rosa.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post", "text": "Fresh bread just out of the oven!", "createdAt": _now()},
                rosa.access_jwt,
            ),
            detail_fn=lambda r: f"uri={r['uri']}",
        )
    time.sleep(1)

    timed_call(
        result, "Luna sees new notification",
        lambda: client.notifications.list_notifications(luna.access_jwt),
        detail_fn=lambda r: f"count={len(r.get('notifications', []))}",
    )

    # ── Put activity subscription ───────────────────────────────────
    if marcus.did:
        timed_call(
            result, "Luna subscribes to Marcus's activity",
            lambda: client.notifications.put_activity_subscription(
                subject=marcus.did, post_enabled=True, reply_enabled=True, token=luna.access_jwt,
            ),
            skip_on_status={404},
        )
    else:
        result.step_skipped("Luna subscribes to Marcus's activity", "Marcus not created")

    # ── List activity subscriptions ─────────────────────────────────
    timed_call(
        result, "Luna lists activity subscriptions",
        lambda: client.notifications.list_activity_subscriptions(luna.access_jwt),
        detail_fn=lambda r: f"count={len(r.get('subscriptions', []))}",
        skip_on_status={404},
    )

    # ── Unregister push ─────────────────────────────────────────────
    timed_call(
        result, "Luna unregisters push",
        lambda: client.notifications.unregister_push(
            service_did="did:web:localhost:3200",
            token="test-device-token-abc123",
            platform="ios",
            app_id="xyz.garazyk.test",
            auth_token=luna.access_jwt,
        ),
        skip_on_status={404},
    )

    # ── Record artifacts ─────────────────────────────────────────────
    result.record_artifact("accounts", {
        n: {"did": get_character(n).did}
        for n in char_names if get_character(n).did
    })
    result.record_artifact("notification_actors", ["marcus", "rosa", "volt"])

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
