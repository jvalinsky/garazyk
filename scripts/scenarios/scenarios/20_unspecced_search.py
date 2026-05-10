"""Scenario 20: "Beyond the Spec" — Unspecced Search & Discovery

Marcus searches across actors, posts, and starter packs using the
unspecced skeleton search endpoints.

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
    result = ScenarioResult("Unspecced Search & Discovery")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # ── Create accounts ──────────────────────────────────────────────
    char_names = ["luna", "marcus", "rosa"]
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
        result.step_failed("Account creation", "Not enough accounts")
        result.finish()
        return result

    # ── Set up profiles with searchable names ────────────────────────
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

    # ── Create searchable posts ─────────────────────────────────────
    for name, texts in [
        ("luna", [
            "The Orion Nebula is absolutely stunning tonight! #astrophotography",
            "Just published my deep space photography guide #astronomy",
        ]),
        ("marcus", [
            "ATProto is the future of decentralized social networking",
            "Building a firehose consumer in Go — streaming thousands of events per second",
        ]),
        ("rosa", [
            "Homemade sourdough with roasted garlic and herbs #baking",
            "The best cacio e pepe recipe you will ever try #cooking",
        ]),
    ]:
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

    # ── Rosa creates a starter pack ──────────────────────────────────
    if rosa.did and rosa.access_jwt and luna.did and marcus.did:
        timed_call(
            result, "Rosa creates starter pack for search",
            lambda: client.records.create_record(
                rosa.did, "app.bsky.graph.starterpack",
                {
                    "$type": "app.bsky.graph.starterpack",
                    "name": "Space & Code Enthusiasts",
                    "description": "Friends who love space and technology",
                    "createdAt": _now(),
                },
                rosa.access_jwt,
            ),
            detail_fn=lambda r: f"uri={r['uri']}",
        )
    else:
        result.step_skipped("Rosa creates starter pack for search", "Missing DIDs")

    time.sleep(2)

    # ── Search actors skeleton ───────────────────────────────────────
    if not marcus.access_jwt:
        result.step_failed("Search", "Marcus not created")
        result.finish()
        return result

    for query in ["nebula", "Luna"]:
        timed_call(
            result, f"Search actors skeleton '{query}'",
            lambda q=query: client.search.search_actors_skeleton(q, token=marcus.access_jwt),
            detail_fn=lambda r, q=query: f"found={len(r.get('actors', []))}",
            skip_on_status={404},
        )

    # ── Search posts skeleton ────────────────────────────────────────
    for query in ["nebula", "sourdough", "zzz nonexistent content"]:
        timed_call(
            result, f"Search posts skeleton '{query}'",
            lambda q=query: client.search.search_posts_skeleton(q, token=marcus.access_jwt),
            detail_fn=lambda r, q=query: f"found={len(r.get('posts', []))}",
            skip_on_status={404},
        )

    # ── Search starter packs skeleton ────────────────────────────────
    timed_call(
        result, "Search starter packs skeleton 'Space'",
        lambda: client.search.search_starter_packs_skeleton("Space", token=marcus.access_jwt),
        detail_fn=lambda r: f"found={len(r.get('starterPacks', []))}",
        skip_on_status={404},
    )

    # ── Record artifacts ─────────────────────────────────────────────
    result.record_artifact("accounts", {
        n: {"did": get_character(n).did}
        for n in char_names if get_character(n).did
    })
    result.record_artifact("search_queries", {
        "actors_skeleton": ["nebula", "Luna"],
        "posts_skeleton": ["nebula", "sourdough", "zzz nonexistent content"],
        "starter_packs_skeleton": ["Space"],
    })

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
