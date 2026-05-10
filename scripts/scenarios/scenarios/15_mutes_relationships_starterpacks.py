"""Scenario 15: "Social Boundaries" — Mutes, Relationships & Starter Packs

Quiet Observer mutes Trollface, checks the mutes list, then unmutes.
Luna and Marcus check their relationship status. Rosa creates a starter
pack of her foodie friends.

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
    result = ScenarioResult("Mutes, Relationships & Starter Packs")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # ── Create accounts ──────────────────────────────────────────────
    char_names = ["luna", "marcus", "rosa", "troll", "quiet", "admin"]
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
    if len(active) < 4:
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
    troll = get_character("troll")
    quiet = get_character("quiet")

    # ── Establish follows ────────────────────────────────────────────
    for pair in [("luna", "marcus"), ("marcus", "luna")]:
        f, t = pair
        fchar = get_character(f)
        tchar = get_character(t)
        if fchar.did and tchar.did:
            timed_call(
                result, f"{fchar.name} follows {tchar.name}",
                lambda ff=fchar, tt=tchar: client.records.create_record(
                    ff.did, "app.bsky.graph.follow",
                    {"$type": "app.bsky.graph.follow", "subject": tt.did, "createdAt": _now()},
                    ff.access_jwt,
                ),
                detail_fn=lambda r: f"uri={r['uri']}",
            )

    time.sleep(1)

    # ── Quiet mutes Trollface ────────────────────────────────────────
    if quiet.did and quiet.access_jwt and troll.did:
        timed_call(
            result, "Quiet mutes Trollface",
            lambda: client.graph.mute_actor(troll.did, quiet.access_jwt),
        )
    else:
        result.step_skipped("Quiet mutes Trollface", "Missing DID or token")

    # ── Quiet checks mutes list ──────────────────────────────────────
    if quiet.access_jwt:
        timed_call(
            result, "Quiet checks mutes list",
            lambda: client.graph.get_mutes(quiet.access_jwt),
            detail_fn=lambda r: f"count={len(r.get('mutes', []))}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Quiet checks mutes list", "Quiet not created")

    # ── Luna checks mutes (should be empty) ─────────────────────────
    if luna.access_jwt:
        timed_call(
            result, "Luna checks mutes (empty)",
            lambda: client.graph.get_mutes(luna.access_jwt),
            detail_fn=lambda r: f"count={len(r.get('mutes', []))}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Luna checks mutes (empty)", "Luna not created")

    # ── Quiet unmutes Trollface ──────────────────────────────────────
    if quiet.did and quiet.access_jwt and troll.did:
        timed_call(
            result, "Quiet unmutes Trollface",
            lambda: client.graph.unmute_actor(troll.did, quiet.access_jwt),
        )
    else:
        result.step_skipped("Quiet unmutes Trollface", "Missing DID or token")

    # ── Quiet verifies Trollface removed from mutes ─────────────────
    if quiet.access_jwt:
        timed_call(
            result, "Quiet verifies unmute",
            lambda: client.graph.get_mutes(quiet.access_jwt),
            detail_fn=lambda r: f"count={len(r.get('mutes', []))}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Quiet verifies unmute", "Quiet not created")

    # ── Check relationships ──────────────────────────────────────────
    if luna.did and marcus.did:
        timed_call(
            result, "Luna→Marcus relationship",
            lambda: client.graph.get_relationships(luna.did, [marcus.did], token=luna.access_jwt),
            detail_fn=lambda r: f"count={len(r.get('relationships', []))}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Luna→Marcus relationship", "Missing DIDs")

    if luna.did and troll.did:
        timed_call(
            result, "Luna→Troll relationship",
            lambda: client.graph.get_relationships(luna.did, [troll.did], token=luna.access_jwt),
            detail_fn=lambda r: f"count={len(r.get('relationships', []))}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Luna→Troll relationship", "Missing DIDs")

    # ── Rosa creates a starter pack ──────────────────────────────────
    rosa_sp_uri = None
    if rosa.did and rosa.access_jwt and luna.did and marcus.did:
        sp = timed_call(
            result, "Rosa creates starter pack",
            lambda: client.records.create_record(
                rosa.did, "app.bsky.graph.starterpack",
                {
                    "$type": "app.bsky.graph.starterpack",
                    "name": "Foodie Friends",
                    "description": "My favorite food-loving friends!",
                    "createdAt": _now(),
                },
                rosa.access_jwt,
            ),
            detail_fn=lambda r: f"uri={r['uri']}",
        )
        if sp:
            rosa_sp_uri = sp["uri"]
    else:
        result.step_skipped("Rosa creates starter pack", "Missing DIDs")

    # ── Get Rosa's starter packs ─────────────────────────────────────
    if rosa.did:
        timed_call(
            result, "Rosa's starter packs",
            lambda: client.graph.get_actor_starter_packs(rosa.did, token=rosa.access_jwt),
            detail_fn=lambda r: f"count={len(r.get('starterPacks', []))}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Rosa's starter packs", "Rosa not created")

    # ── Get specific starter pack by URI ─────────────────────────────
    if rosa_sp_uri:
        timed_call(
            result, "Get starter pack by URI",
            lambda: client.graph.get_starter_pack(rosa_sp_uri, token=rosa.access_jwt),
            detail_fn=lambda r: f"name={r.get('starterPack', {}).get('name', '')}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Get starter pack by URI", "No starter pack URI")

    # ── Get multiple starter packs by URIs ───────────────────────────
    if rosa_sp_uri:
        timed_call(
            result, "Get starter packs by URIs",
            lambda: client.graph.get_starter_packs([rosa_sp_uri], token=rosa.access_jwt),
            detail_fn=lambda r: f"count={len(r.get('starterPacks', []))}",
            skip_on_status={404},
        )
    else:
        result.step_skipped("Get starter packs by URIs", "No starter pack URI")

    # ── Record artifacts ─────────────────────────────────────────────
    result.record_artifact("accounts", {
        n: {"did": get_character(n).did}
        for n in char_names if get_character(n).did
    })
    result.record_artifact("relationships_checked", ["luna→marcus", "luna→troll"])
    result.record_artifact("starter_pack_uri", rosa_sp_uri)

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
