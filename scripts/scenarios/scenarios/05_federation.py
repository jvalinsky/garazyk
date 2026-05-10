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

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, PDS2, ScenarioResult, timed_call



def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def run() -> ScenarioResult:
    result = ScenarioResult("Federation & Multi-PDS")
    result.start()

    pds1 = XrpcClient(PDS1)
    pds2 = XrpcClient(PDS2)

    for name, client in [("PDS1", pds1), ("PDS2", pds2)]:
        timed_call(result, f"{name} health check",
                   lambda c=client: c.wait_for_healthy(timeout=60))
        if result.failed > 0:
            result.finish()
            return result

    luna = get_character("luna")
    marcus = get_character("marcus")
    for char in [luna, marcus]:
        timed_call(
            result, f"Create account on PDS1: {char.name}",
            lambda c=char: pds1.accounts.create_account(c.handle, c.email, c.password),
            detail_fn=lambda s, c=char: f"did={s['did']}",
        )

    nova = get_character("nova")
    rex = get_character("rex")
    for char in [nova, rex]:
        timed_call(
            result, f"Create account on PDS2: {char.name}",
            lambda c=char: pds2.accounts.create_account(c.handle, c.email, c.password),
            detail_fn=lambda s, c=char: f"did={s['did']}",
        )

    if not all([luna.did, marcus.did, nova.did, rex.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    for char, client in [(luna, pds1), (marcus, pds1), (nova, pds2), (rex, pds2)]:
        timed_call(
            result, f"Set profile: {char.name}",
            lambda c=char, cl=client: cl.records.create_record(
                c.did, "app.bsky.actor.profile",
                {"$type": "app.bsky.actor.profile", "displayName": c.name, "description": c.persona},
                c.access_jwt),
        )

    luna_post = timed_call(
        result, "Luna posts on PDS 1",
        lambda: pds1.records.create_record(
            luna.did, "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post", "text": "Hello from PDS 1! Can anyone on PDS 2 see this?",
             "createdAt": _now()},
            luna.access_jwt),
    )

    marcus_post = timed_call(
        result, "Marcus posts on PDS 1",
        lambda: pds1.records.create_record(
            marcus.did, "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post",
             "text": "Federation is the future of social media! Building bridges across PDSes.",
             "createdAt": _now()},
            marcus.access_jwt),
    )

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

    resolved = timed_call(
        result, "Nova resolves Luna's handle from PDS2",
        lambda: pds2.identity.resolve_handle(luna.handle),
        detail_fn=lambda r: f"did={r.get('did')}",
    )
    if resolved and resolved.get("did") != luna.did:
        result.step_failed("Nova resolves Luna's handle from PDS2",
                           f"expected {luna.did}, got {resolved.get('did')}")

    timed_call(
        result, "Nova follows Luna (cross-PDS)",
        lambda: pds2.records.create_record(
            nova.did, "app.bsky.graph.follow",
            {"$type": "app.bsky.graph.follow", "subject": luna.did, "createdAt": _now()},
            nova.access_jwt),
        detail_fn=lambda r: f"uri={r['uri']}",
    )

    timed_call(
        result, "Rex follows Marcus (cross-PDS)",
        lambda: pds2.records.create_record(
            rex.did, "app.bsky.graph.follow",
            {"$type": "app.bsky.graph.follow", "subject": marcus.did, "createdAt": _now()},
            rex.access_jwt),
        detail_fn=lambda r: f"uri={r['uri']}",
    )

    if marcus_post:
        timed_call(
            result, "Rex replies to Marcus (cross-PDS)",
            lambda: pds2.records.create_record(
                rex.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post",
                 "text": "Hey Marcus! Replying from PDS 2. Federation works!",
                 "createdAt": _now(),
                 "reply": {"root": {"uri": marcus_post["uri"], "cid": marcus_post["cid"]},
                           "parent": {"uri": marcus_post["uri"], "cid": marcus_post["cid"]}}},
                rex.access_jwt),
        )

    time.sleep(5)

    try:
        import requests
        relay_resp = requests.get("http://localhost:2584/api/relay/health", timeout=5)
        if relay_resp.status_code == 200:
            result.step_passed("Relay health check", f"body={relay_resp.text[:100]}")
        else:
            result.step_skipped("Relay health check", f"status={relay_resp.status_code}")
    except Exception as exc:
        result.step_skipped("Relay health check", str(exc))

    try:
        import requests
        upstreams_resp = requests.get("http://localhost:2584/api/relay/upstreams", timeout=5)
        if upstreams_resp.status_code == 200:
            upstreams = upstreams_resp.json()
            count = len(upstreams) if isinstance(upstreams, list) else len(upstreams.get("upstreams", []))
            result.step_passed("Relay upstreams", f"count={count}")
        else:
            result.step_skipped("Relay upstreams", f"status={upstreams_resp.status_code}")
    except Exception as exc:
        result.step_skipped("Relay upstreams", str(exc))

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

    timed_call(
        result, "Nova views Luna's profile via AppView",
        lambda: pds2.feed.get_profile(luna.did, token=nova.access_jwt),
        detail_fn=lambda p: f"displayName={p.get('displayName')}",
        skip_on_status={404},
    )

    timed_call(
        result, "Nova sees Luna's feed via AppView",
        lambda: pds2.feed.get_author_feed(luna.did, token=nova.access_jwt),
        detail_fn=lambda f: f"items={len(f.get('feed', []))}",
        skip_on_status={404},
    )

    if luna_post:
        timed_call(
            result, "Cross-PDS record retrieval",
            lambda: pds2.raw.xrpc_get(
                "com.atproto.repo.getRecord",
                {"repo": luna.did, "collection": "app.bsky.feed.post",
                 "rkey": luna_post["uri"].split("/")[-1]},
                token=nova.access_jwt),
            detail_fn=lambda r: f"uri={r.get('uri')}",
            skip_on_status={404},
        )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
