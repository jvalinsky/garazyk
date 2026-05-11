"""Scenario 47: "The Group Chat" — Chat Group Lifecycle

Luna creates a group conversation with Bob and Carol, manages
members, and verifies group state changes.

Services: PDS, AppView (chat)
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
    get_convo_for_members, send_message, get_messages, list_convos,
)


def run() -> ScenarioResult:
    result = ScenarioResult("Chat Group Lifecycle")
    result.start()

    pds = XrpcClient(PDS1)
    chat = XrpcClient(SERVICE_URLS["chat"])
    luna = get_character("luna")
    bob = get_character("bob")
    carol = get_character("carol")

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
    carol_session = timed_call(
        result, "Create account for Carol",
        lambda: create_account_or_login(pds, carol),
        detail_fn=lambda s: f"did={s.get('did', '?')}",
    )

    if not all([luna_session, bob_session, carol_session]):
        result.finish()
        return result

    luna.did = luna_session["did"]
    luna.access_jwt = luna_session["accessJwt"]
    bob.did = bob_session["did"]
    bob.access_jwt = bob_session["accessJwt"]
    carol.did = carol_session["did"]
    carol.access_jwt = carol_session["accessJwt"]

    # Check chat service health
    timed_call(
        result, "Chat service health check",
        lambda: chat._get("/_health"),
    )

    # Create a group conversation
    convo = timed_call(
        result, "Create group conversation",
        lambda: get_convo_for_members(
            chat, [bob.did, carol.did], luna.access_jwt,
        ),
        detail_fn=lambda r: f"convoId={r.get('id', '?')}" if r else "failed",
    )

    if not convo:
        result.finish()
        return result

    convo_id = convo.get("id", "")

    # Send a message to the group
    timed_call(
        result, "Luna sends message to group",
        lambda: send_message(
            chat, convo_id, "Hello group!", luna.access_jwt,
        ),
    )

    # Bob retrieves the conversation
    time.sleep(1)
    bob_convos = timed_call(
        result, "Bob retrieves conversations",
        lambda: list_convos(chat, bob.access_jwt),
        detail_fn=lambda r: f"count={len(r.get('convos', []))}" if r else "failed",
    )

    # Bob reads messages
    timed_call(
        result, "Bob reads group messages",
        lambda: get_messages(chat, convo_id, bob.access_jwt),
        detail_fn=lambda r: f"count={len(r.get('messages', []))}" if r else "failed",
    )

    # Mute the conversation (Bob)
    timed_call(
        result, "Bob mutes the group",
        lambda: chat.convo.mute_convo(
            {"convoId": convo_id}, bob.access_jwt,
        ),
    )

    # Carol leaves the group
    timed_call(
        result, "Carol leaves the group",
        lambda: chat.convo.leave_convo(
            {"convoId": convo_id}, carol.access_jwt,
        ),
    )

    # Verify group state after changes
    time.sleep(1)
    timed_call(
        result, "Verify group state after changes",
        lambda: get_messages(chat, convo_id, luna.access_jwt),
    )

    # Luna retrieves her conversation list
    timed_call(
        result, "Luna retrieves conversation list",
        lambda: list_convos(chat, luna.access_jwt),
    )

    result.finish()
    return result
