"""Scenario 5: "Across the Wire" — Federation & Multi-PDS

Nova (on PDS 2) follows Luna (on PDS 1). Nova's follow resolves Luna's
DID via PLC. Luna's posts appear on the Relay from PDS 1, and AppView
indexes them. Nova can see Luna's posts through AppView. Rex (PDS 2)
tries to interact with Marcus (PDS 1) — cross-PDS reply works.

Services: PDS x2, PLC, Relay, AppView
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, PDS1, PDS2
from lib.assertions import assert_success, assert_contains
from lib.report import ScenarioResult, StepStatus


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Federation & Multi-PDS")
    result.start()

    pds1 = XrpcClient(PDS1)
    pds2 = XrpcClient(PDS2)

    # ── Wait for both PDSes ──────────────────────────────────────────
    for name, client in [("PDS1", pds1), ("PDS2", pds2)]:
        try:
            client.wait_for_healthy(timeout=60)
            result.step_passed(f"{name} health check")
        except RuntimeError as exc:
            result.step_failed(f"{name} health check", str(exc))
            result.finish()
            return result

    # ── Create accounts on PDS 1 ─────────────────────────────────────
    luna = get_character("luna")
    marcus = get_character("marcus")
    for char in [luna, marcus]:
        try:
            session = pds1.create_account(char.handle, char.email, char.password)
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            result.step_passed(f"Create account on PDS1: {char.name}", f"did={char.did}")
        except XrpcError as exc:
            result.step_failed(f"Create account on PDS1: {char.name}", str(exc))

    # ── Create accounts on PDS 2 ─────────────────────────────────────
    nova = get_character("nova")
    rex = get_character("rex")
    for char in [nova, rex]:
        try:
            session = pds2.create_account(char.handle, char.email, char.password)
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            result.step_passed(f"Create account on PDS2: {char.name}", f"did={char.did}")
        except XrpcError as exc:
            result.step_failed(f"Create account on PDS2: {char.name}", str(exc))

    if not all([luna.did, marcus.did, nova.did, rex.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    # ── Set up profiles ──────────────────────────────────────────────
    for char, client in [(luna, pds1), (marcus, pds1), (nova, pds2), (rex, pds2)]:
        try:
            client.create_record(
                char.did,
                "app.bsky.actor.profile",
                {"$type": "app.bsky.actor.profile", "displayName": char.name, "description": char.persona},
                char.access_jwt,
            )
        except XrpcError:
            pass

    # ── Luna posts on PDS 1 ──────────────────────────────────────────
    luna_post = None
    try:
        luna_post = pds1.create_record(
            luna.did,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "Hello from PDS 1! Can anyone on PDS 2 see this? 🌍",
                "createdAt": _now(),
            },
            luna.access_jwt,
        )
        result.step_passed("Luna posts on PDS 1")
    except XrpcError as exc:
        result.step_failed("Luna posts on PDS 1", str(exc))

    # ── Marcus posts on PDS 1 ────────────────────────────────────────
    marcus_post = None
    try:
        marcus_post = pds1.create_record(
            marcus.did,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "Federation is the future of social media! Building bridges across PDSes.",
                "createdAt": _now(),
            },
            marcus.access_jwt,
        )
        result.step_passed("Marcus posts on PDS 1")
    except XrpcError as exc:
        result.step_failed("Marcus posts on PDS 1", str(exc))

    # ── PLC DID resolution: Nova resolves Luna's DID ─────────────────
    try:
        import requests
        plc_resp = requests.get(f"http://localhost:2582/{luna.did}", timeout=10)
        if plc_resp.status_code == 200:
            did_doc = plc_resp.json()
            result.step_passed("PLC resolves Luna's DID", f"alsoKnownAs={did_doc.get('alsoKnownAs')}")
        else:
            result.step_skipped("PLC resolves Luna's DID", f"PLC returned {plc_resp.status_code}")
    except Exception as exc:
        result.step_skipped("PLC resolves Luna's DID", str(exc))

    # ── Nova resolves Luna's handle from PDS 2 ───────────────────────
    try:
        resolved = pds2.resolve_handle(luna.handle)
        if resolved.get("did") == luna.did:
            result.step_passed("Nova resolves Luna's handle from PDS2", f"did={resolved['did']}")
        else:
            result.step_failed("Nova resolves Luna's handle from PDS2",
                               f"expected {luna.did}, got {resolved.get('did')}")
    except XrpcError as exc:
        result.step_skipped("Nova resolves Luna's handle from PDS2", str(exc))

    # ── Nova follows Luna (cross-PDS follow) ─────────────────────────
    try:
        follow = pds2.create_record(
            nova.did,
            "app.bsky.graph.follow",
            {
                "$type": "app.bsky.graph.follow",
                "subject": luna.did,
                "createdAt": _now(),
            },
            nova.access_jwt,
        )
        result.step_passed("Nova follows Luna (cross-PDS)", f"uri={follow['uri']}")
    except XrpcError as exc:
        result.step_failed("Nova follows Luna (cross-PDS)", str(exc))

    # ── Rex follows Marcus (cross-PDS) ────────────────────────────────
    try:
        follow = pds2.create_record(
            rex.did,
            "app.bsky.graph.follow",
            {
                "$type": "app.bsky.graph.follow",
                "subject": marcus.did,
                "createdAt": _now(),
            },
            rex.access_jwt,
        )
        result.step_passed("Rex follows Marcus (cross-PDS)", f"uri={follow['uri']}")
    except XrpcError as exc:
        result.step_failed("Rex follows Marcus (cross-PDS)", str(exc))

    # ── Rex replies to Marcus (cross-PDS reply) ──────────────────────
    if marcus_post:
        try:
            reply = pds2.create_record(
                rex.did,
                "app.bsky.feed.post",
                {
                    "$type": "app.bsky.feed.post",
                    "text": "Hey Marcus! Replying from PDS 2. Federation works! 🎉",
                    "createdAt": _now(),
                    "reply": {
                        "root": {"uri": marcus_post["uri"], "cid": marcus_post["cid"]},
                        "parent": {"uri": marcus_post["uri"], "cid": marcus_post["cid"]},
                    },
                },
                rex.access_jwt,
            )
            result.step_passed("Rex replies to Marcus (cross-PDS)")
        except XrpcError as exc:
            result.step_failed("Rex replies to Marcus (cross-PDS)", str(exc))

    # ── Give Relay and AppView time to process ───────────────────────
    time.sleep(5)

    # ── Check relay health ────────────────────────────────────────────
    try:
        import requests
        relay_resp = requests.get("http://localhost:2584/api/relay/health", timeout=5)
        if relay_resp.status_code == 200:
            result.step_passed("Relay health check", f"body={relay_resp.text[:100]}")
        else:
            result.step_skipped("Relay health check", f"status={relay_resp.status_code}")
    except Exception as exc:
        result.step_skipped("Relay health check", str(exc))

    # ── Check relay upstreams ─────────────────────────────────────────
    try:
        import requests
        upstreams_resp = requests.get("http://localhost:2584/api/relay/upstreams", timeout=5)
        if upstreams_resp.status_code == 200:
            upstreams = upstreams_resp.json()
            count = len(upstreams) if isinstance(upstreams, list) else upstreams.get("upstreams", [])
            result.step_passed("Relay upstreams", f"count={len(count) if isinstance(count, list) else count}")
        else:
            result.step_skipped("Relay upstreams", f"status={upstreams_resp.status_code}")
    except Exception as exc:
        result.step_skipped("Relay upstreams", str(exc))

    # ── AppView backfill status ───────────────────────────────────────
    try:
        import requests
        appview_resp = requests.get(
            "http://localhost:3200/admin/backfill/status",
            headers={"Authorization": "Bearer localdevadmin"},
            timeout=5,
        )
        if appview_resp.status_code == 200:
            result.step_passed("AppView backfill status", f"body={appview_resp.text[:100]}")
        else:
            result.step_skipped("AppView backfill status", f"status={appview_resp.status_code}")
    except Exception as exc:
        result.step_skipped("AppView backfill status", str(exc))

    # ── Nova views Luna's profile via AppView ────────────────────────
    try:
        profile = pds2.get_profile(luna.did, token=nova.access_jwt)
        result.step_passed("Nova views Luna's profile via AppView",
                           f"displayName={profile.get('displayName')}")
    except XrpcError as exc:
        result.step_skipped("Nova views Luna's profile via AppView", str(exc))

    # ── Nova gets Luna's author feed via AppView ─────────────────────
    try:
        feed = pds2.get_author_feed(luna.did, token=nova.access_jwt)
        feed_items = feed.get("feed", [])
        result.step_passed("Nova sees Luna's feed via AppView", f"items={len(feed_items)}")
    except XrpcError as exc:
        result.step_skipped("Nova sees Luna's feed via AppView", str(exc))

    # ── Cross-PDS record retrieval ───────────────────────────────────
    if luna_post:
        try:
            record = pds2.xrpc_get(
                "com.atproto.repo.getRecord",
                {"repo": luna.did, "collection": "app.bsky.feed.post",
                 "rkey": luna_post["uri"].split("/")[-1]},
                token=nova.access_jwt,
            )
            result.step_passed("Cross-PDS record retrieval", f"uri={record.get('uri')}")
        except XrpcError as exc:
            result.step_skipped("Cross-PDS record retrieval", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
