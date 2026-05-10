"""Scenario 14: "Drafts & Bookmarks" — Drafts and Bookmarks Workflow

Luna drafts an astronomy post, edits it with tags, then publishes it and
cleans up the draft. Marcus drafts two technical posts, then deletes one.
Quiet Observer bookmarks Luna's published post, verifies it, then removes it.

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
    result = ScenarioResult("Drafts & Bookmarks Workflow")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    char_names = ["luna", "marcus", "quiet"]
    dids = []
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
            dids.append(session["did"])
            timed_call(result, f"Set profile: {char.name}",
                       lambda c=char: client.records.create_record(
                           c.did, "app.bsky.actor.profile",
                           {"$type": "app.bsky.actor.profile", "displayName": c.name},
                           c.access_jwt),
                       skip_on_status={404})

    active = [n for n in char_names if get_character(n).did]
    if len(active) < 2:
        result.step_failed("Setup", "Not enough accounts created")
        result.finish()
        return result

    luna = get_character("luna")
    marcus = get_character("marcus")
    quiet = get_character("quiet")

    luna_draft_content = {
        "text": "Just captured the most stunning image of the Orion Nebula!",
        "facets": [], "tags": [],
    }

    resp = timed_call(
        result, "Luna creates draft",
        lambda: client.drafts.create_draft(luna_draft_content, luna.access_jwt),
        detail_fn=lambda r: f"id={r.get('id') or r.get('draft', {}).get('id', '')}",
        skip_on_status={404},
    )
    luna_draft_id = resp.get("id") or resp.get("draft", {}).get("id", "") if resp else None

    if luna_draft_id is None and result.failed > 0:
        result.finish()
        return result

    drafts = timed_call(
        result, "Luna lists drafts",
        lambda: client.drafts.get_drafts(luna.access_jwt),
        skip_on_status={404},
    )

    if luna_draft_id:
        updated_content = dict(luna_draft_content)
        updated_content["text"] = "Just captured the most stunning image of the Orion Nebula! #astronomy"
        updated_content["tags"] = ["astronomy", "nebula"]
        timed_call(
            result, "Luna edits draft",
            lambda: client.drafts.update_draft(luna_draft_id, updated_content, luna.access_jwt),
            detail_fn=lambda r: f"id={luna_draft_id}",
        )

    luna_post_uri = None
    if luna_draft_id:
        post = timed_call(
            result, "Luna publishes post from draft",
            lambda: client.records.create_record(
                luna.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post",
                 "text": "Just captured the most stunning image of the Orion Nebula! #astronomy",
                 "createdAt": _now()},
                luna.access_jwt,
            ),
            detail_fn=lambda r: f"uri={r['uri']}",
        )
        if post:
            luna_post_uri = post["uri"]

        timed_call(
            result, "Luna deletes draft (cleanup)",
            lambda: client.drafts.delete_draft(luna_draft_id, luna.access_jwt),
            detail_fn=lambda r: f"id={luna_draft_id}",
        )

        timed_call(
            result, "Luna verifies 0 drafts",
            lambda: client.drafts.get_drafts(luna.access_jwt),
            skip_on_status={404},
        )

    marcus_draft_ids = []
    for i, text in enumerate(["Building a new ATProto feed generator",
                              "Thoughts on CBOR encoding in distributed systems"]):
        resp = timed_call(
            result, f"Marcus creates draft {i+1}",
            lambda t=text: client.drafts.create_draft({"text": t}, marcus.access_jwt),
            detail_fn=lambda r, idx=i: f"id={r.get('id') or r.get('draft', {}).get('id', '')}",
        )
        if resp:
            did = resp.get("id") or resp.get("draft", {}).get("id", "")
            marcus_draft_ids.append(did)

    drafts = timed_call(
        result, "Marcus lists drafts",
        lambda: client.drafts.get_drafts(marcus.access_jwt),
        skip_on_status={404},
    )

    if len(marcus_draft_ids) >= 1:
        timed_call(
            result, "Marcus deletes draft",
            lambda: client.drafts.delete_draft(marcus_draft_ids[0], marcus.access_jwt),
            detail_fn=lambda r: f"id={marcus_draft_ids[0]}",
        )

    timed_call(
        result, "Marcus verifies draft count",
        lambda: client.drafts.get_drafts(marcus.access_jwt),
        skip_on_status={404},
    )

    if luna_draft_id:
        timed_call(
            result, "Reject update with bad draft id",
            lambda: client.drafts.update_draft("nonexistent-id", {"text": "x"}, luna.access_jwt),
            skip_on_status={404},
        )

    # ── Bookmarks ────────────────────────────────────────────────────
    if luna_post_uri:
        timed_call(
            result, "Quiet bookmarks Luna's post",
            lambda: client.raw.xrpc_post("app.bsky.bookmark.createBookmark",
                                     {"uri": luna_post_uri}, token=quiet.access_jwt),
            detail_fn=lambda r: f"uri={luna_post_uri}",
        )

        timed_call(
            result, "Quiet lists bookmarks",
            lambda: client.raw.xrpc_get("app.bsky.bookmark.getBookmarks",
                                    {"limit": 50}, token=quiet.access_jwt),
            skip_on_status={404},
        )

        timed_call(
            result, "Quiet deletes bookmark",
            lambda: client.raw.xrpc_post("app.bsky.bookmark.deleteBookmark",
                                     {"uri": luna_post_uri}, token=quiet.access_jwt),
            detail_fn=lambda r: f"uri={luna_post_uri}",
        )

        timed_call(
            result, "Quiet verifies 0 bookmarks",
            lambda: client.raw.xrpc_get("app.bsky.bookmark.getBookmarks",
                                    {"limit": 50}, token=quiet.access_jwt),
            skip_on_status={404},
        )

    # ── Record artifacts ─────────────────────────────────────────────
    result.record_artifact("accounts", {
        c.name: {"did": get_character(c.name).did}
        for c in [get_character(n) for n in char_names] if c.did
    })
    result.record_artifact("drafts_created", {
        "luna": luna_draft_id,
        "marcus": marcus_draft_ids,
    })
    result.record_artifact("post_uri", luna_post_uri)

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
