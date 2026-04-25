"""Scenario 6: "Private Conversations" — Chat & DMs

Luna starts a DM conversation with Marcus. They exchange messages.
Rosa tries to start a group chat with Luna and DJ Volt.
Marcus mutes the conversation.

Services: PDS, AppView (chat.bsky)

NOTE: Chat endpoints may not be fully implemented yet. This scenario
detects missing endpoints and reports SKIP instead of FAIL.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, PDS1
from lib.assertions import assert_success, assert_contains
from lib.report import ScenarioResult, StepStatus


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _chat_step(result: ScenarioResult, step_name: str, func, *args, **kwargs):
    """Execute a chat step, failing strictly on error."""
    try:
        response = func(*args, **kwargs)
        result.step_passed(step_name, detail=str(response)[:100])
        return response
    except Exception as exc:
        result.step_failed(step_name, str(exc))
        return None


def run() -> ScenarioResult:
    result = ScenarioResult("Chat & DMs")
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

    # ── Create accounts ──────────────────────────────────────────────
    char_names = ["luna", "marcus", "rosa", "volt"]
    for name in char_names:
        char = get_character(name)
        try:
            session = client.create_account(char.handle, char.email, char.password)
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            result.step_passed(f"Create account: {char.name}", f"did={char.did}")
        except XrpcError as exc:
            result.step_failed(f"Create account: {char.name}", str(exc))

    luna = get_character("luna")
    marcus = get_character("marcus")
    rosa = get_character("rosa")
    volt = get_character("volt")

    if not all([luna.did, marcus.did, rosa.did, volt.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    # ── Luna starts a DM with Marcus ─────────────────────────────────
    convo_id = None
    convo = _chat_step(
        result,
        "Luna gets/creates DM convo with Marcus",
        client.xrpc_get,
        "chat.bsky.convo.getConvoForMembers",
        {"members": [luna.did, marcus.did]},
        luna.access_jwt,
    )
    if convo and "convo" in convo:
        convo_id = convo["convo"].get("id")

    # ── Luna sends a DM to Marcus ────────────────────────────────────
    luna_msg_id = None
    luna_msg = _chat_step(
        result,
        "Luna sends DM to Marcus",
        client.xrpc_post,
        "chat.bsky.convo.sendMessage",
        {
            "convoId": convo_id or "default",
            "message": {
                "$type": "chat.bsky.convo.message",
                "text": "Hey Marcus! Want to collaborate on a space-tech project?",
                "createdAt": _now(),
            },
        },
        luna.access_jwt,
    )
    if luna_msg and "id" in luna_msg:
        luna_msg_id = luna_msg["id"]

    # ── Marcus replies to Luna's DM ───────────────────────────────────
    _chat_step(
        result,
        "Marcus replies to Luna's DM",
        client.xrpc_post,
        "chat.bsky.convo.sendMessage",
        {
            "convoId": convo_id or "default",
            "message": {
                "$type": "chat.bsky.convo.message",
                "text": "Absolutely! I've been thinking about ATProto + space data. Let's do it!",
                "createdAt": _now(),
            },
        },
        marcus.access_jwt,
    )

    # ── Marcus lists his conversations ───────────────────────────────
    _chat_step(
        result,
        "Marcus lists conversations",
        client.xrpc_get,
        "chat.bsky.convo.listConvos",
        {"limit": 10},
        marcus.access_jwt,
    )

    # ── Marcus gets conversation messages ────────────────────────────
    if convo_id:
        _chat_step(
            result,
            "Marcus gets conversation messages",
            client.xrpc_get,
            "chat.bsky.convo.getMessages",
            {"convoId": convo_id, "limit": 20},
            marcus.access_jwt,
        )

    # ── Marcus mutes the conversation ────────────────────────────────
    if convo_id:
        _chat_step(
            result,
            "Marcus mutes conversation",
            client.xrpc_post,
            "chat.bsky.convo.muteConvo",
            {"convoId": convo_id},
            marcus.access_jwt,
        )

    # ── Rosa creates a group chat ────────────────────────────────────
    group_id = None
    group = _chat_step(
        result,
        "Rosa creates group chat",
        client.xrpc_post,
        "chat.bsky.group.createGroup",
        {
            "name": "Food & Space Enthusiasts",
            "members": [luna.did, volt.did],
        },
        rosa.access_jwt,
    )
    if group and "group" in group:
        group_id = group["group"].get("id")

    # ── Rosa adds a member to the group ──────────────────────────────
    if group_id:
        _chat_step(
            result,
            "Rosa adds member to group",
            client.xrpc_post,
            "chat.bsky.group.addMember",
            {"groupId": group_id, "did": marcus.did},
            rosa.access_jwt,
        )

    # ── Rosa gets group info ─────────────────────────────────────────
    if group_id:
        _chat_step(
            result,
            "Rosa gets group info",
            client.xrpc_get,
            "chat.bsky.group.getGroup",
            {"groupId": group_id},
            rosa.access_jwt,
        )

    # ── Luna updates read status ─────────────────────────────────────
    if convo_id and luna_msg_id:
        _chat_step(
            result,
            "Luna marks conversation as read",
            client.xrpc_post,
            "chat.bsky.convo.updateRead",
            {"convoId": convo_id, "messageId": luna_msg_id},
            luna.access_jwt,
        )

    # ── Marcus unmutes the conversation ──────────────────────────────
    if convo_id:
        _chat_step(
            result,
            "Marcus unmutes conversation",
            client.xrpc_post,
            "chat.bsky.convo.unmuteConvo",
            {"convoId": convo_id},
            marcus.access_jwt,
        )

    # ── Marcus leaves the conversation ──────────────────────────────
    if convo_id:
        _chat_step(
            result,
            "Marcus leaves conversation",
            client.xrpc_post,
            "chat.bsky.convo.leaveConvo",
            {"convoId": convo_id},
            marcus.access_jwt,
        )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
