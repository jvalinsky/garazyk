"""Scenario 17: "Know Thyself" — Actor Preferences & Discovery

Marcus sets his preferences to developer mode, retrieves them, and
searches for astronomy friends via typeahead. He explores Luna's liked
posts and checks who reposted his content.

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
    result = ScenarioResult("Actor Preferences & Discovery")
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

    # ── Set up profiles with distinctive names ───────────────────────
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

    # ── Marcus sets preferences ──────────────────────────────────────
    if not marcus.access_jwt:
        result.step_failed("Marcus preferences", "Marcus not created")
        result.finish()
        return result

    timed_call(
        result, "Marcus sets preferences",
        lambda: client.feed.put_preferences(
            [{"$type": "app.bsky.actor.defs#personalDetailsPref", "developerMode": True}],
            marcus.access_jwt,
        ),
        skip_on_status={404},
    )

    # ── Marcus gets preferences ─────────────────────────────────────
    timed_call(
        result, "Marcus gets preferences",
        lambda: client.feed.get_preferences(marcus.access_jwt),
        detail_fn=lambda r: f"count={len(r.get('preferences', []))}",
        skip_on_status={404},
    )

    # ── Everyone posts content ──────────────────────────────────────
    luna_posts = []
    for text in [
        "The Orion Nebula through my telescope tonight!",
        "Saturn's rings are visible, come take a look!",
        "New research paper on exoplanet atmospheres",
    ]:
        if luna.did and luna.access_jwt:
            rec = timed_call(
                result, "Luna posts",
                lambda t=text: client.records.create_record(
                    luna.did, "app.bsky.feed.post",
                    {"$type": "app.bsky.feed.post", "text": t, "createdAt": _now()},
                    luna.access_jwt,
                ),
                detail_fn=lambda r: f"uri={r['uri']}",
            )
            if rec:
                luna_posts.append(rec)

    marcus_posts = []
    for text in [
        "Just deployed a new microservice for ATProto relay",
        "Open source contribution: fixed a race condition in the firehose",
    ]:
        if marcus.did and marcus.access_jwt:
            rec = timed_call(
                result, "Marcus posts",
                lambda t=text: client.records.create_record(
                    marcus.did, "app.bsky.feed.post",
                    {"$type": "app.bsky.feed.post", "text": t, "createdAt": _now()},
                    marcus.access_jwt,
                ),
                detail_fn=lambda r: f"uri={r['uri']}",
            )
            if rec:
                marcus_posts.append(rec)

    for name, texts in [("rosa", ["Best pasta recipe ever: cacio e pepe!"]),
                        ("volt", ["New track dropping Friday! #electronic #beats"])]:
        char = get_character(name)
        if char.did and char.access_jwt:
            for text in texts:
                timed_call(
                    result, f"{char.name} posts",
                    lambda c=char, t=text: client.records.create_record(
                        c.did, "app.bsky.feed.post",
                        {"$type": "app.bsky.feed.post", "text": t, "createdAt": _now()},
                        c.access_jwt,
                    ),
                    detail_fn=lambda r: f"uri={r['uri']}",
                )

    # ── Likes: Luna likes posts from others; Marcus likes Luna's ────
    if luna.access_jwt:
        for post_rec in marcus_posts:
            timed_call(
                result, "Luna likes Marcus's post",
                lambda p=post_rec: client.records.create_record(
                    luna.did, "app.bsky.feed.like",
                    {"$type": "app.bsky.feed.like", "subject": {"uri": p["uri"], "cid": p["cid"]}, "createdAt": _now()},
                    luna.access_jwt,
                ),
                skip_on_status={404},
            )

        for target_name in ["rosa", "volt"]:
            target = get_character(target_name)
            if target.did and target.access_jwt:
                posts_for_liking = timed_call(
                    result, f"Get {target.name}'s feed for liking",
                    lambda t=target: client.feed.get_author_feed(t.did, token=t.access_jwt, limit=1),
                    detail_fn=lambda r: f"items={len(r.get('feed', []))}",
                    skip_on_status={404},
                )
                if posts_for_liking:
                    feed_items = posts_for_liking.get("feed", [])
                    if feed_items:
                        post_uri = feed_items[0].get("post", {}).get("uri", "")
                        post_cid = feed_items[0].get("post", {}).get("cid", "")
                        if post_uri:
                            timed_call(
                                result, f"Luna likes {target.name}'s post",
                                lambda u=post_uri, c=post_cid: client.records.create_record(
                                    luna.did, "app.bsky.feed.like",
                                    {"$type": "app.bsky.feed.like", "subject": {"uri": u, "cid": c}, "createdAt": _now()},
                                    luna.access_jwt,
                                ),
                                skip_on_status={404},
                            )

    if marcus.access_jwt:
        for post_rec in luna_posts:
            timed_call(
                result, "Marcus likes Luna's post",
                lambda p=post_rec: client.records.create_record(
                    marcus.did, "app.bsky.feed.like",
                    {"$type": "app.bsky.feed.like", "subject": {"uri": p["uri"], "cid": p["cid"]}, "createdAt": _now()},
                    marcus.access_jwt,
                ),
                skip_on_status={404},
            )

    time.sleep(2)

    # ── Search typeahead ─────────────────────────────────────────────
    for query in ["Lun", "Ro", "zzz nonexistent"]:
        label = f"Typeahead search '{query}'"
        timed_call(
            result, label,
            lambda q=query: client.feed.search_actors_typeahead(q, token=marcus.access_jwt),
            detail_fn=lambda r, q=query: f"found={len(r.get('actors', []))}",
            skip_on_status={404},
        )

    # ── Get actor likes ─────────────────────────────────────────────
    if luna.did:
        timed_call(
            result, "Luna's liked posts",
            lambda: client.feed.get_actor_likes(luna.did, token=marcus.access_jwt),
            detail_fn=lambda r: f"count={len(r.get('likes', r.get('feed', [])))}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Luna's liked posts", "Luna not created")

    # ── Get multiple posts by URI ────────────────────────────────────
    all_post_uris = [p["uri"] for p in luna_posts + marcus_posts if p]
    if all_post_uris:
        timed_call(
            result, "Get multiple posts",
            lambda: client.feed.get_posts(all_post_uris[:2], token=marcus.access_jwt),
            detail_fn=lambda r: f"count={len(r.get('posts', []))}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Get multiple posts", "No post URIs")

    # ── Repost and check getRepostedBy ──────────────────────────────
    if luna_posts and marcus.did and marcus.access_jwt:
        timed_call(
            result, "Marcus reposts Luna's post",
            lambda: client.records.create_record(
                marcus.did, "app.bsky.feed.repost",
                {"$type": "app.bsky.feed.repost", "subject": {"uri": luna_posts[0]["uri"], "cid": luna_posts[0]["cid"]}, "createdAt": _now()},
                marcus.access_jwt,
            ),
            detail_fn=lambda r: f"uri={r['uri']}",
        )

        time.sleep(1)

        timed_call(
            result, "Get reposted by",
            lambda: client.feed.get_reposted_by(luna_posts[0]["uri"], token=marcus.access_jwt),
            detail_fn=lambda r: f"count={len(r.get('repostedBy', []))}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Get reposted by", "Missing posts or Marcus")

    # ── Get suggestions ─────────────────────────────────────────────
    timed_call(
        result, "Get actor suggestions",
        lambda: client.feed.get_suggestions(marcus.access_jwt),
        detail_fn=lambda r: f"count={len(r.get('actors', []))}",
        skip_on_status={404},
    )

    # ── Record artifacts ─────────────────────────────────────────────
    result.record_artifact("accounts", {
        c.name: {"did": get_character(c.name).did}
        for c in [get_character(n) for n in char_names] if c.did
    })
    result.record_artifact("post_count", {
        "luna": len(luna_posts),
        "marcus": len(marcus_posts),
    })
    result.record_artifact("typeahead_queries", ["Lun", "Ro", "zzz nonexistent"])

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
