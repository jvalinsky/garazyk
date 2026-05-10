"""Scenario 2: "Making Friends" — Social Graph

Marcus follows Luna, Rosa, and DJ Volt. Luna follows Marcus back.
Quiet Observer follows everyone. Rosa follows Luna and Marcus.
DJ Volt follows Rosa. Marcus unfollows DJ Volt. Luna blocks Trollface.

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


def _create_accounts(client: XrpcClient, names: list[str], result: ScenarioResult) -> dict:
    sessions = {}
    for name in names:
        char = get_character(name)
        session = timed_call(
            result, f"Create account: {char.name}",
            lambda c=char: client.accounts.create_account(c.handle, c.email, c.password),
            detail_fn=lambda s, n=name: f"did={s['did']}",
        )
        if session:
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            sessions[name] = session
    return sessions


def _follow(client: XrpcClient, follower_name: str, target_name: str, result: ScenarioResult) -> dict | None:
    follower = get_character(follower_name)
    target = get_character(target_name)

    if not follower.did or not follower.access_jwt:
        result.step_skipped(f"{follower.name} follows {target.name}", "Follower account not created")
        return None
    if not target.did:
        result.step_skipped(f"{follower.name} follows {target.name}", "Target account not created")
        return None

    rec = timed_call(
        result, f"{follower.name} follows {target.name}",
        lambda: client.records.create_record(
            follower.did, "app.bsky.graph.follow",
            {"$type": "app.bsky.graph.follow", "subject": target.did, "createdAt": _now()},
            follower.access_jwt),
        detail_fn=lambda r: f"uri={r['uri']}",
    )
    return rec


def run() -> ScenarioResult:
    result = ScenarioResult("Social Graph")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    pds1_chars = ["luna", "marcus", "rosa", "volt", "troll", "quiet", "admin"]
    _create_accounts(client, pds1_chars, result)

    active = [n for n in pds1_chars if get_character(n).did]
    if len(active) < 4:
        result.step_failed("Account creation", f"Only {len(active)} accounts created, need at least 4")
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
            skip_on_status={404},
        )

    _follow(client, "marcus", "luna", result)
    _follow(client, "marcus", "rosa", result)
    _follow(client, "marcus", "volt", result)
    _follow(client, "luna", "marcus", result)
    for name in ["luna", "marcus", "rosa", "volt", "troll", "admin"]:
        _follow(client, "quiet", name, result)
    _follow(client, "rosa", "luna", result)
    _follow(client, "rosa", "marcus", result)
    _follow(client, "volt", "rosa", result)

    time.sleep(2)

    marcus = get_character("marcus")
    luna = get_character("luna")

    timed_call(
        result, "Marcus's follows list",
        lambda: client.graph.get_follows(marcus.did, token=marcus.access_jwt),
        detail_fn=lambda f: f"count={len(f.get('follows', []))}",
    )

    timed_call(
        result, "Luna's followers list",
        lambda: client.graph.get_followers(luna.did, token=luna.access_jwt),
        detail_fn=lambda f: f"count={len(f.get('followers', []))}",
    )

    volt = get_character("volt")
    follows_resp = timed_call(
        result, "Marcus lists follow records (for unfollow)",
        lambda: client.records.list_records(marcus.did, "app.bsky.graph.follow", token=marcus.access_jwt),
    )
    if follows_resp:
        records = follows_resp.get("records", [])
        volt_follow = None
        for rec in records:
            val = rec.get("value", {})
            if val.get("subject") == volt.did:
                volt_follow = rec
                break
        if volt_follow:
            rkey = volt_follow["uri"].split("/")[-1]
            timed_call(
                result, "Marcus unfollows DJ Volt",
                lambda: client.records.delete_record(marcus.did, "app.bsky.graph.follow", rkey, marcus.access_jwt),
                detail_fn=lambda r: f"deleted rkey={rkey}",
            )
        else:
            result.step_skipped("Marcus unfollows DJ Volt", "Follow record not found")

    troll = get_character("troll")
    if not luna.did or not luna.access_jwt:
        result.step_skipped("Luna blocks Trollface", "Luna account not created")
    elif not troll.did:
        result.step_skipped("Luna blocks Trollface", "Troll account not created")
    else:
        timed_call(
            result, "Luna blocks Trollface",
            lambda: client.records.create_record(
                luna.did, "app.bsky.graph.block",
                {"$type": "app.bsky.graph.block", "subject": troll.did, "createdAt": _now()},
                luna.access_jwt),
            detail_fn=lambda r: f"uri={r['uri']}",
        )

    if not luna.did or not luna.access_jwt:
        result.step_skipped("Luna's blocks list", "Luna account not created")
    else:
        timed_call(
            result, "Luna's blocks list",
            lambda: client.graph.get_blocks(luna.access_jwt),
            detail_fn=lambda b: f"count={len(b.get('blocks', []))}",
        )

    timed_call(
        result, "Marcus profile counts",
        lambda: client.feed.get_profile(marcus.did, token=marcus.access_jwt),
        detail_fn=lambda p: f"follows={p.get('followsCount', 0)}, followers={p.get('followersCount', 0)}",
    )

    if not luna.did or not luna.access_jwt:
        result.step_failed("Search actors", "Luna account not created")
    else:
        timed_call(
            result, "Search actors",
            lambda: client.feed.search_actors("Luna", token=luna.access_jwt),
            detail_fn=lambda s: f"found={len(s.get('actors', []))}",
        )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
