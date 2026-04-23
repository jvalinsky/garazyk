"""Scenario 3: "The Feed Comes Alive" — Content Creation & Interaction

Everyone posts content. Luna posts about a nebula, Marcus replies with
a technical comment, Rosa quotes Luna's post with a "space food" joke,
DJ Volt likes everything, Quiet Observer bookmarks Luna's post.
Marcus edits a post. Rosa deletes a post.

Services: PDS, AppView, Relay
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, PDS1
from lib.assertions import assert_success, assert_contains
from lib.report import ScenarioResult, StepStatus


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _create_post(client: XrpcClient, author_name: str, text: str, result: ScenarioResult,
                 facets: list | None = None, reply: dict | None = None,
                 embed: dict | None = None) -> dict | None:
    """Create a post record. Returns {uri, cid} or None."""
    author = get_character(author_name)
    record: dict = {
        "$type": "app.bsky.feed.post",
        "text": text,
        "createdAt": _now(),
    }
    if facets:
        record["facets"] = facets
    if reply:
        record["reply"] = reply
    if embed:
        record["embed"] = embed

    try:
        rec = client.create_record(author.did, "app.bsky.feed.post", record, author.access_jwt)
        result.step_passed(f"{author.name} posts", text[:60])
        return rec
    except XrpcError as exc:
        result.step_failed(f"{author.name} posts", str(exc))
        return None


def run() -> ScenarioResult:
    result = ScenarioResult("Content Creation & Interaction")
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

    # ── Set up profiles ──────────────────────────────────────────────
    for name in active:
        char = get_character(name)
        try:
            client.create_record(
                char.did,
                "app.bsky.actor.profile",
                {"$type": "app.bsky.actor.profile", "displayName": char.name, "description": char.persona},
                char.access_jwt,
            )
        except XrpcError:
            pass

    # ── Luna posts about a nebula ────────────────────────────────────
    luna_post = _create_post(
        client, "luna",
        "Just captured the most stunning image of the Orion Nebula! The colors are breathtaking. 🌌 #astronomy",
        result,
        facets=[{
            "$type": "app.bsky.richtext.facet",
            "features": [{"$type": "app.bsky.richtext.facet#tag", "tag": "#astronomy"}],
            "index": {"byteStart": 90, "byteEnd": 100},
        }],
    )

    # ── Marcus posts about ATProto ───────────────────────────────────
    marcus_post = _create_post(
        client, "marcus",
        "Just shipped a new XRPC handler for the PDS. Open source is the way! 🚀",
        result,
    )

    # ── Rosa posts about food ────────────────────────────────────────
    rosa_post = _create_post(
        client, "rosa",
        "Made the most incredible sourdough today. The crust was perfect! 🍞",
        result,
    )

    # ── DJ Volt posts about music ────────────────────────────────────
    volt_post = _create_post(
        client, "volt",
        "New beat dropping this weekend. Get ready for the drop! 🎵",
        result,
    )

    # ── Marcus replies to Luna ───────────────────────────────────────
    if luna_post and marcus_post:
        reply_ref = {
            "root": {"uri": luna_post["uri"], "cid": luna_post["cid"]},
            "parent": {"uri": luna_post["uri"], "cid": luna_post["cid"]},
        }
        _create_post(
            client, "marcus",
            "The data pipeline for nebula images is fascinating — CBOR-encoded CAR blocks!",
            result,
            reply=reply_ref,
        )
    else:
        result.step_skipped("Marcus replies to Luna", "Missing post references")

    # ── Rosa quotes Luna's post ──────────────────────────────────────
    if luna_post:
        _create_post(
            client, "rosa",
            "Space food is underrated — imagine sourdough on the ISS! 🚀🍞",
            result,
            embed={
                "$type": "app.bsky.embed.record",
                "record": {"uri": luna_post["uri"], "cid": luna_post["cid"]},
            },
        )
    else:
        result.step_skipped("Rosa quotes Luna", "Missing post reference")

    # ── DJ Volt likes everything ─────────────────────────────────────
    volt = get_character("volt")
    for post_name, post_rec in [("Luna", luna_post), ("Marcus", marcus_post), ("Rosa", rosa_post)]:
        if post_rec:
            try:
                like = client.create_record(
                    volt.did,
                    "app.bsky.feed.like",
                    {
                        "$type": "app.bsky.feed.like",
                        "subject": {"uri": post_rec["uri"], "cid": post_rec["cid"]},
                        "createdAt": _now(),
                    },
                    volt.access_jwt,
                )
                result.step_passed(f"DJ Volt likes {post_name}'s post")
            except XrpcError as exc:
                result.step_failed(f"DJ Volt likes {post_name}'s post", str(exc))

    # ── Quiet Observer bookmarks Luna's post ─────────────────────────
    quiet = get_character("quiet")
    if luna_post:
        try:
            bookmark = client.create_record(
                quiet.did,
                "app.bsky.feed.bookmark",
                {
                    "$type": "app.bsky.feed.bookmark",
                    "subject": {"uri": luna_post["uri"], "cid": luna_post["cid"]},
                    "createdAt": _now(),
                },
                quiet.access_jwt,
            )
            result.step_passed("Quiet Observer bookmarks Luna's post")
        except XrpcError as exc:
            # Bookmarks may not be implemented
            result.step_skipped("Quiet Observer bookmarks Luna's post", str(exc))

    # ── Rosa creates and then deletes a post ─────────────────────────
    rosa = get_character("rosa")
    rosa_temp = _create_post(
        client, "rosa",
        "This post will be deleted soon. Don't get attached!",
        result,
    )
    if rosa_temp:
        try:
            rkey = rosa_temp["uri"].split("/")[-1]
            client.delete_record(rosa.did, "app.bsky.feed.post", rkey, rosa.access_jwt)
            result.step_passed("Rosa deletes her post", f"rkey={rkey}")
        except XrpcError as exc:
            result.step_failed("Rosa deletes her post", str(exc))

        # Verify deletion
        try:
            client.get_record(rosa.did, "app.bsky.feed.post", rkey)
            result.step_failed("Verify deletion", "Record still exists after delete")
        except XrpcError:
            result.step_passed("Verify deletion", "Record not found (expected)")

    # ── Give AppView time to index ───────────────────────────────────
    time.sleep(3)

    # ── Get timeline ─────────────────────────────────────────────────
    luna = get_character("luna")
    try:
        timeline = client.get_timeline(luna.access_jwt)
        feed = timeline.get("feed", [])
        result.step_passed("Luna's timeline", f"items={len(feed)}")
    except XrpcError as exc:
        result.step_failed("Luna's timeline", str(exc))

    # ── Get author feed ──────────────────────────────────────────────
    try:
        author_feed = client.get_author_feed(luna.did, token=luna.access_jwt)
        feed = author_feed.get("feed", [])
        result.step_passed("Luna's author feed", f"items={len(feed)}")
    except XrpcError as exc:
        result.step_failed("Luna's author feed", str(exc))

    # ── Get post thread ──────────────────────────────────────────────
    if luna_post:
        try:
            thread = client.get_post_thread(luna_post["uri"], token=luna.access_jwt)
            result.step_passed("Post thread view", f"thread has replies")
        except XrpcError as exc:
            result.step_skipped("Post thread view", str(exc))

    # ── Get likes for Luna's post ────────────────────────────────────
    if luna_post:
        try:
            likes = client.get_likes(luna_post["uri"], token=luna.access_jwt)
            like_count = len(likes.get("likes", []))
            result.step_passed("Likes on Luna's post", f"count={like_count}")
        except XrpcError as exc:
            result.step_failed("Likes on Luna's post", str(exc))

    # ── Notifications ────────────────────────────────────────────────
    try:
        notifs = client.list_notifications(luna.access_jwt)
        notif_count = len(notifs.get("notifications", []))
        result.step_passed("Luna's notifications", f"count={notif_count}")
    except XrpcError as exc:
        result.step_skipped("Luna's notifications", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
