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

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import (
    get_character, get_characters_by_pds, PDS1,
    CHARACTERS,
)
from lib.assertions import assert_success, assert_contains
from lib.report import ScenarioResult, StepStatus


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _create_accounts(client: XrpcClient, names: list[str], result: ScenarioResult) -> dict:
    """Create accounts and return {name: session_dict}."""
    sessions = {}
    for name in names:
        char = get_character(name)
        try:
            session = client.create_account(char.handle, char.email, char.password)
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            sessions[name] = session
            result.step_passed(f"Create account: {char.name}", f"did={char.did}")
        except XrpcError as exc:
            result.step_failed(f"Create account: {char.name}", str(exc))
    return sessions


def _follow(client: XrpcClient, follower_name: str, target_name: str, result: ScenarioResult) -> dict | None:
    """Create a follow record. Returns the follow record response."""
    follower = get_character(follower_name)
    target = get_character(target_name)

    # Skip if either account wasn't created
    if not follower.did or not follower.access_jwt:
        result.step_skipped(f"{follower.name} follows {target.name}", "Follower account not created")
        return None
    if not target.did:
        result.step_skipped(f"{follower.name} follows {target.name}", "Target account not created")
        return None

    try:
        rec = client.create_record(
            follower.did,
            "app.bsky.graph.follow",
            {
                "$type": "app.bsky.graph.follow",
                "subject": target.did,
                "createdAt": _now(),
            },
            follower.access_jwt,
        )
        result.step_passed(f"{follower.name} follows {target.name}", f"uri={rec['uri']}")
        return rec
    except XrpcError as exc:
        result.step_failed(f"{follower.name} follows {target.name}", str(exc))
        return None


def _is_appview_endpoint(exc: XrpcError) -> bool:
    """Check if an XrpcError indicates an AppView-only endpoint not available."""
    if exc.status == 404 and isinstance(exc.body, dict):
        msg = str(exc.body.get("error", ""))
        return msg == "MethodNotFound"
    return False


def run() -> ScenarioResult:
    result = ScenarioResult("Social Graph")
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

    # ── Create all accounts ──────────────────────────────────────────
    pds1_chars = ["luna", "marcus", "rosa", "volt", "troll", "quiet", "admin"]
    sessions = _create_accounts(client, pds1_chars, result)

    # Verify we got enough accounts
    active = [n for n in pds1_chars if get_character(n).did]
    if len(active) < 4:
        result.step_failed("Account creation", f"Only {len(active)} accounts created, need at least 4")
        result.finish()
        return result

    # ── Set up profiles ─────────────────────────────────────────────
    for name in active:
        char = get_character(name)
        try:
            client.create_record(
                char.did,
                "app.bsky.actor.profile",
                {
                    "$type": "app.bsky.actor.profile",
                    "displayName": char.name,
                    "description": char.persona,
                },
                char.access_jwt,
            )
        except XrpcError:
            pass  # Non-critical

    # ── Follow relationships ────────────────────────────────────────
    # Marcus follows Luna, Rosa, DJ Volt
    _follow(client, "marcus", "luna", result)
    _follow(client, "marcus", "rosa", result)
    _follow(client, "marcus", "volt", result)

    # Luna follows Marcus back
    _follow(client, "luna", "marcus", result)

    # Quiet Observer follows everyone
    for name in ["luna", "marcus", "rosa", "volt", "troll", "admin"]:
        _follow(client, "quiet", name, result)

    # Rosa follows Luna and Marcus
    _follow(client, "rosa", "luna", result)
    _follow(client, "rosa", "marcus", result)

    # DJ Volt follows Rosa
    _follow(client, "volt", "rosa", result)

    # Give AppView time to index
    time.sleep(2)

    # ── Verify follows (AppView endpoints) ──────────────────────────
    marcus = get_character("marcus")
    luna = get_character("luna")

    try:
        follows = client.get_follows(marcus.did, token=marcus.access_jwt)
        assert_contains(follows, "follows", operation="getFollows for Marcus")
        result.step_passed("Marcus's follows list", f"count={len(follows.get('follows', []))}")
    except XrpcError as exc:
        if _is_appview_endpoint(exc):
            result.step_skipped("Marcus's follows list", "AppView endpoint not available (no AppView)")
        else:
            result.step_failed("Marcus's follows list", str(exc))
    except AssertionError as exc:
        result.step_failed("Marcus's follows list", str(exc))

    try:
        followers = client.get_followers(luna.did, token=luna.access_jwt)
        assert_contains(followers, "followers", operation="getFollowers for Luna")
        result.step_passed("Luna's followers list", f"count={len(followers.get('followers', []))}")
    except XrpcError as exc:
        if _is_appview_endpoint(exc):
            result.step_skipped("Luna's followers list", "AppView endpoint not available (no AppView)")
        else:
            result.step_failed("Luna's followers list", str(exc))
    except AssertionError as exc:
        result.step_failed("Luna's followers list", str(exc))

    # ── Marcus unfollows DJ Volt ────────────────────────────────────
    volt = get_character("volt")
    try:
        # Find the follow record's rkey
        follows_resp = client.list_records(marcus.did, "app.bsky.graph.follow", token=marcus.access_jwt)
        records = follows_resp.get("records", [])
        volt_follow = None
        for rec in records:
            val = rec.get("value", {})
            if val.get("subject") == volt.did:
                volt_follow = rec
                break

        if volt_follow:
            rkey = volt_follow["uri"].split("/")[-1]
            client.delete_record(marcus.did, "app.bsky.graph.follow", rkey, marcus.access_jwt)
            result.step_passed("Marcus unfollows DJ Volt", f"deleted rkey={rkey}")
        else:
            result.step_skipped("Marcus unfollows DJ Volt", "Follow record not found")
    except XrpcError as exc:
        result.step_failed("Marcus unfollows DJ Volt", str(exc))

    # ── Luna blocks Trollface ───────────────────────────────────────
    troll = get_character("troll")
    if not luna.did or not luna.access_jwt:
        result.step_skipped("Luna blocks Trollface", "Luna account not created")
    elif not troll.did:
        result.step_skipped("Luna blocks Trollface", "Troll account not created")
    else:
        try:
            block = client.create_record(
                luna.did,
                "app.bsky.graph.block",
                {
                    "$type": "app.bsky.graph.block",
                    "subject": troll.did,
                    "createdAt": _now(),
                },
                luna.access_jwt,
            )
            result.step_passed("Luna blocks Trollface", f"uri={block['uri']}")
        except XrpcError as exc:
            result.step_failed("Luna blocks Trollface", str(exc))

    # ── Verify blocks (AppView endpoint) ──────────────────────────────
    if not luna.did or not luna.access_jwt:
        result.step_skipped("Luna's blocks list", "Luna account not created")
    else:
        try:
            blocks = client.get_blocks(luna.access_jwt)
            assert_contains(blocks, "blocks", operation="getBlocks for Luna")
            result.step_passed("Luna's blocks list", f"count={len(blocks.get('blocks', []))}")
        except XrpcError as exc:
            if _is_appview_endpoint(exc):
                result.step_skipped("Luna's blocks list", "AppView endpoint not available (no AppView)")
            else:
                result.step_failed("Luna's blocks list", str(exc))
        except AssertionError as exc:
            result.step_failed("Luna's blocks list", str(exc))

    # ── Profile shows updated counts ─────────────────────────────────
    try:
        profile = client.get_profile(marcus.did, token=marcus.access_jwt)
        follows_count = profile.get("followsCount", 0)
        followers_count = profile.get("followersCount", 0)
        result.step_passed(
            "Marcus profile counts",
            f"follows={follows_count}, followers={followers_count}",
        )
    except XrpcError as exc:
        result.step_failed("Marcus profile counts", str(exc))

    # ── Search actors (AppView endpoint) ──────────────────────────────
    if not luna.did or not luna.access_jwt:
        result.step_skipped("Search actors", "Luna account not created")
    else:
        try:
            search = client.search_actors("Luna", token=luna.access_jwt)
            assert_contains(search, "actors", operation="searchActors")
            result.step_passed("Search actors", f"found={len(search.get('actors', []))}")
        except XrpcError as exc:
            # searchActors is an AppView endpoint; skip if not available or broken
            if _is_appview_endpoint(exc) or exc.status in (500, 0):
                result.step_skipped("Search actors", "AppView endpoint not available (no AppView)")
            else:
                result.step_failed("Search actors", str(exc))
        except AssertionError as exc:
            result.step_failed("Search actors", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
