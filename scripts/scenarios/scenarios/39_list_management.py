"""Scenario 39: "The Organizer" — List Management

Luna creates and manages lists: curatelist and modlist, adds and
removes members, and verifies list operations.

Services: PDS, AppView
"""

# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0

from __future__ import annotations

import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import (
    XrpcClient, get_character, PDS1, ScenarioResult, timed_call,
    SERVICE_URLS, create_account_or_login, now_iso,
)


def run() -> ScenarioResult:
    result = ScenarioResult("List Management")
    result.start()

    pds = XrpcClient(PDS1)
    appview = XrpcClient(SERVICE_URLS["appview"])
    luna = get_character("luna")
    bob = get_character("bob")

    timed_call(result, "PDS health check",
               lambda: pds.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # Create accounts
    luna_session = timed_call(
        result, "Create account for Luna",
        lambda: create_account_or_login(pds, luna),
        detail_fn=lambda s: f"did={s.get('did', '?')}",
    )
    bob_session = timed_call(
        result, "Create account for Bob",
        lambda: create_account_or_login(pds, bob),
        detail_fn=lambda s: f"did={s.get('did', '?')}",
    )

    if not luna_session or not bob_session:
        result.finish()
        return result

    luna.did = luna_session["did"]
    luna.access_jwt = luna_session["accessJwt"]
    bob.did = bob_session["did"]

    # Create a curate list
    list_rkey = "curate-list-" + str(int(time.time()))
    list_record = {
        "$type": "app.bsky.graph.list",
        "purpose": "app.bsky.graph.defs#curatelist",
        "name": "Luna's Favorites",
        "description": "Accounts Luna finds interesting",
        "createdAt": now_iso(),
    }

    list_ref = timed_call(
        result, "Create curate list",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.graph.list", list_rkey,
            list_record, luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r.get('uri', '?')}" if r else "failed",
    )

    if not list_ref:
        result.finish()
        return result

    list_uri = list_ref.get("uri", "")

    # Add Bob to the list
    item_rkey = "listitem-" + str(int(time.time()))
    listitem_record = {
        "$type": "app.bsky.graph.listitem",
        "list": list_uri,
        "subject": bob.did,
        "createdAt": now_iso(),
    }

    timed_call(
        result, "Add Bob to curate list",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.graph.listitem", item_rkey,
            listitem_record, luna.access_jwt,
        ),
    )

    time.sleep(1)

    # Verify list appears in getLists
    timed_call(
        result, "Get lists for Luna",
        lambda: appview.graph.get_lists(
            {"actor": luna.did, "limit": 10}, luna.access_jwt,
        ),
        detail_fn=lambda r: f"count={len(r.get('lists', []))}" if r else "failed",
    )

    # Verify Bob appears in getList
    timed_call(
        result, "Get list items",
        lambda: appview.graph.get_list(
            {"list": list_uri, "limit": 10}, luna.access_jwt,
        ),
        detail_fn=lambda r: f"count={len(r.get('items', []))}" if r else "failed",
    )

    # Remove Bob from the list
    item_uri = list_uri.replace("app.bsky.graph.list", "app.bsky.graph.listitem") + "/" + item_rkey
    timed_call(
        result, "Remove Bob from list",
        lambda: pds.repositories.delete_record(
            luna.did, "app.bsky.graph.listitem", item_rkey,
            luna.access_jwt,
        ),
    )

    # Create a moderation list
    mod_list_rkey = "mod-list-" + str(int(time.time()))
    mod_list_record = {
        "$type": "app.bsky.graph.list",
        "purpose": "app.bsky.graph.defs#modlist",
        "name": "Luna's Block List",
        "description": "Accounts to moderate",
        "createdAt": now_iso(),
    }

    timed_call(
        result, "Create mod list",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.graph.list", mod_list_rkey,
            mod_list_record, luna.access_jwt,
        ),
    )

    # Verify both lists accessible
    timed_call(
        result, "Verify both lists accessible",
        lambda: appview.graph.get_lists(
            {"actor": luna.did, "limit": 10}, luna.access_jwt,
        ),
        detail_fn=lambda r: f"count={len(r.get('lists', []))}" if r else "failed",
    )

    result.finish()
    return result
