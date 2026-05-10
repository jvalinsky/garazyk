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

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call



def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _chat_call(result: ScenarioResult, step_name: str, fn, *args, **kwargs):
    """Execute a chat step, reporting strictly."""
    response = timed_call(result, step_name, lambda: fn(*args, **kwargs))
    return response


def run() -> ScenarioResult:
    result = ScenarioResult("Chat & DMs")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    char_names = ["luna", "marcus", "rosa", "volt"]
    for name in char_names:
        char = get_character(name)
        timed_call(
            result, f"Create account: {char.name}",
            lambda c=char: client.accounts.create_account(c.handle, c.email, c.password),
            detail_fn=lambda s, n=name: f"did={s['did']}",
        )

    luna = get_character("luna")
    marcus = get_character("marcus")
    rosa = get_character("rosa")
    volt = get_character("volt")

    if not all([luna.did, marcus.did, rosa.did, volt.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    convo = timed_call(
        result, "Luna gets/creates DM convo with Marcus",
        lambda: client.raw.xrpc_get(
            "chat.bsky.convo.getConvoForMembers",
            {"members": [luna.did, marcus.did]},
            luna.access_jwt),
    )
    convo_id = convo["convo"].get("id") if convo and "convo" in convo else None

    luna_msg = timed_call(
        result, "Luna sends DM to Marcus",
        lambda: client.raw.xrpc_post(
            "chat.bsky.convo.sendMessage",
            {"convoId": convo_id or "default",
             "message": {"$type": "chat.bsky.convo.message",
                         "text": "Hey Marcus! Want to collaborate on a space-tech project?",
                         "createdAt": _now()}},
            luna.access_jwt),
    )
    luna_msg_id = luna_msg.get("id") if luna_msg else None

    timed_call(
        result, "Marcus replies to Luna's DM",
        lambda: client.raw.xrpc_post(
            "chat.bsky.convo.sendMessage",
            {"convoId": convo_id or "default",
             "message": {"$type": "chat.bsky.convo.message",
                         "text": "Absolutely! I've been thinking about ATProto + space data. Let's do it!",
                         "createdAt": _now()}},
            marcus.access_jwt),
    )

    timed_call(
        result, "Marcus lists conversations",
        lambda: client.raw.xrpc_get("chat.bsky.convo.listConvos", {"limit": 10}, marcus.access_jwt),
    )

    if convo_id:
        timed_call(
            result, "Marcus gets conversation messages",
            lambda: client.raw.xrpc_get("chat.bsky.convo.getMessages",
                                         {"convoId": convo_id, "limit": 20}, marcus.access_jwt),
        )

    if convo_id:
        timed_call(
            result, "Marcus mutes conversation",
            lambda: client.raw.xrpc_post("chat.bsky.convo.muteConvo",
                                          {"convoId": convo_id}, marcus.access_jwt),
        )

    group = timed_call(
        result, "Rosa creates group chat",
        lambda: client.raw.xrpc_post("chat.bsky.group.createGroup",
                                      {"name": "Food & Space Enthusiasts",
                                       "members": [luna.did, volt.did]},
                                      rosa.access_jwt),
    )
    group_id = group["group"].get("id") if group and "group" in group else None

    if group_id:
        timed_call(
            result, "Rosa adds member to group",
            lambda: client.raw.xrpc_post("chat.bsky.group.addMember",
                                          {"groupId": group_id, "did": marcus.did},
                                          rosa.access_jwt),
        )

    if group_id:
        timed_call(
            result, "Rosa gets group info",
            lambda: client.raw.xrpc_get("chat.bsky.group.getGroup",
                                         {"groupId": group_id}, rosa.access_jwt),
        )

    if convo_id and luna_msg_id:
        timed_call(
            result, "Luna marks conversation as read",
            lambda: client.raw.xrpc_post("chat.bsky.convo.updateRead",
                                          {"convoId": convo_id, "messageId": luna_msg_id},
                                          luna.access_jwt),
        )

    if convo_id:
        timed_call(
            result, "Marcus unmutes conversation",
            lambda: client.raw.xrpc_post("chat.bsky.convo.unmuteConvo",
                                          {"convoId": convo_id}, marcus.access_jwt),
        )

    if convo_id:
        timed_call(
            result, "Marcus leaves conversation",
            lambda: client.raw.xrpc_post("chat.bsky.convo.leaveConvo",
                                          {"convoId": convo_id}, marcus.access_jwt),
        )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
