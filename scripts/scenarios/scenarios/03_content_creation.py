"""Scenario 3: "The Feed Comes Alive" — Content Creation & Interaction

Everyone posts content. Luna posts about a nebula, Marcus replies with
a technical comment, Rosa quotes Luna's post with a "space food" joke,
DJ Volt likes everything. Marcus edits a post. Rosa deletes a post.

Services: PDS, AppView, Relay
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


def _create_post(client: XrpcClient, author_name: str, text: str, result: ScenarioResult,
                 facets: list | None = None, reply: dict | None = None,
                 embed: dict | None = None) -> dict | None:
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

    rec = timed_call(
        result, f"{author.name} posts",
        lambda: client.records.create_record(author.did, "app.bsky.feed.post", record, author.access_jwt),
        detail_fn=lambda r: text[:60],
    )
    return rec


def run() -> ScenarioResult:
    result = ScenarioResult("Content Creation & Interaction")
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
        timed_call(
            result, f"Create account: {char.name}",
            lambda c=char: client.accounts.create_account(c.handle, c.email, c.password),
            detail_fn=lambda s, n=name: f"did={s['did']}",
        )

    active = [n for n in char_names if get_character(n).did]
    if len(active) < 3:
        result.step_failed("Account creation", "Not enough accounts")
        result.finish()
        return result

    for name in active:
        char = get_character(name)
        timed_call(
            result, f"Set profile: {char.name}",
            lambda c=char: client.records.create_record(
                c.did, "app.bsky.actor.profile",
                {"$type": "app.bsky.actor.profile", "displayName": c.name, "description": c.persona},
                c.access_jwt),
        )

    luna_post = _create_post(
        client, "luna",
        "Just captured the most stunning image of the Orion Nebula! The colors are breathtaking. #astronomy",
        result,
    )

    marcus_post = _create_post(
        client, "marcus",
        "Just shipped a new XRPC handler for the PDS. Open source is the way!",
        result,
    )

    rosa_post = _create_post(
        client, "rosa",
        "Made the most incredible sourdough today. The crust was perfect!",
        result,
    )

    volt_post = _create_post(
        client, "volt",
        "New beat dropping this weekend. Get ready for the drop!",
        result,
    )

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

    if luna_post:
        _create_post(
            client, "rosa",
            "Space food is underrated — imagine sourdough on the ISS!",
            result,
            embed={
                "$type": "app.bsky.embed.record",
                "record": {"uri": luna_post["uri"], "cid": luna_post["cid"]},
            },
        )
    else:
        result.step_skipped("Rosa quotes Luna", "Missing post reference")

    volt = get_character("volt")
    for post_name, post_rec in [("Luna", luna_post), ("Marcus", marcus_post), ("Rosa", rosa_post)]:
        if post_rec:
            timed_call(
                result, f"DJ Volt likes {post_name}'s post",
                lambda p=post_rec: client.records.create_record(
                    volt.did, "app.bsky.feed.like",
                    {"$type": "app.bsky.feed.like",
                     "subject": {"uri": p["uri"], "cid": p["cid"]},
                     "createdAt": _now()},
                    volt.access_jwt),
            )

    quiet = get_character("quiet")
    if luna_post:
        timed_call(
            result, "Quiet Observer bookmarks Luna's post",
            lambda: client.raw.xrpc_post(
                "app.bsky.bookmark.createBookmark",
                {"uri": luna_post["uri"], "cid": luna_post["cid"]},
                token=quiet.access_jwt),
        )

    rosa = get_character("rosa")
    rosa_temp = _create_post(
        client, "rosa",
        "This post will be deleted soon. Don't get attached!",
        result,
    )
    if rosa_temp:
        rkey = rosa_temp["uri"].split("/")[-1]
        timed_call(
            result, "Rosa deletes her post",
            lambda: client.records.delete_record(rosa.did, "app.bsky.feed.post", rkey, rosa.access_jwt),
            detail_fn=lambda r: f"rkey={rkey}",
        )

        timed_call(
            result, "Verify deletion",
            lambda: client.records.get_record(rosa.did, "app.bsky.feed.post", rkey),
            expect_failure=True,
        )

    time.sleep(3)

    luna = get_character("luna")
    timed_call(
        result, "Luna's timeline",
        lambda: client.feed.get_timeline(luna.access_jwt),
        detail_fn=lambda t: f"items={len(t.get('feed', []))}",
        skip_on_status={404},
    )

    timed_call(
        result, "Luna's author feed",
        lambda: client.feed.get_author_feed(luna.did, token=luna.access_jwt),
        detail_fn=lambda f: f"items={len(f.get('feed', []))}",
        skip_on_status={404},
    )

    if luna_post:
        timed_call(
            result, "Post thread view",
            lambda: client.feed.get_post_thread(luna_post["uri"], token=luna.access_jwt),
            skip_on_status={404},
        )

    if luna_post:
        timed_call(
            result, "Likes on Luna's post",
            lambda: client.feed.get_likes(luna_post["uri"], token=luna.access_jwt),
            detail_fn=lambda l: f"count={len(l.get('likes', []))}",
        )

    timed_call(
        result, "Luna's notifications",
        lambda: client.notifications.list_notifications(luna.access_jwt),
        detail_fn=lambda n: f"count={len(n.get('notifications', []))}",
    )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
