#!/usr/bin/env python3
"""Seed chat conversations and messages between accounts via XRPC.

Creates DM conversations and group chats, sends messages between accounts,
and verifies message retrieval. Designed to work with a running PDS that
has the chat.bsky.convo XRPC endpoints registered.

Usage:
    # First create accounts (e.g. via seed_demo_via_xrpc.py), then:
    python3 scripts/seed_chat.py

    # Custom PDS URL:
    PDS_URL=http://localhost:2583 python3 scripts/seed_chat.py

    # Custom accounts (comma-separated handles):
    CHAT_ACCOUNTS=alice.garazyk.xyz,bob.garazyk.xyz,carol.garazyk.xyz python3 scripts/seed_chat.py

Environment variables:
    PDS_URL          - PDS base URL (default: http://localhost:2583)
    CHAT_ACCOUNTS    - Comma-separated list of handles (default: alice.garazyk.xyz,bob.garazyk.xyz,carol.garazyk.xyz)
    CHAT_PASSWORDS   - Comma-separated passwords per account (default: alicepass123,bobpass123,carolpass123)
    CHAT_PASSWORD    - Single password for all accounts (overrides CHAT_PASSWORDS)
"""

import json
import os
import sys
import time
from datetime import datetime, timezone

import requests

BASE_URL = os.environ.get("PDS_URL", "http://localhost:2583").rstrip("/")
ACCOUNTS_RAW = os.environ.get(
    "CHAT_ACCOUNTS", "alice.garazyk.xyz,bob.garazyk.xyz,carol.garazyk.xyz"
)
HANDLES = [h.strip() for h in ACCOUNTS_RAW.split(",") if h.strip()]
DEFAULT_PASSWORDS = "alicepass123,bobpass123,carolpass123"
SINGLE_PASSWORD = os.environ.get("CHAT_PASSWORD", "")
PASSWORDS_RAW = os.environ.get("CHAT_PASSWORDS", DEFAULT_PASSWORDS)
# If CHAT_PASSWORD is set, use it for all accounts; otherwise parse per-account
if SINGLE_PASSWORD:
    PASSWORDS = [SINGLE_PASSWORD] * len(HANDLES)
else:
    PASSWORDS = [p.strip() for p in PASSWORDS_RAW.split(",")]
    # Pad with last password if not enough provided
    while len(PASSWORDS) < len(HANDLES):
        PASSWORDS.append(PASSWORDS[-1] if PASSWORDS else "changeme")
NOW = lambda: datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def wait_for_server(timeout: int = 30) -> None:
    """Wait for PDS to be healthy."""
    deadline = time.time() + timeout
    last_err = None
    while time.time() < deadline:
        try:
            r = requests.get(f"{BASE_URL}/_health", timeout=2)
            if r.status_code == 200:
                return
            last_err = f"HTTP {r.status_code}"
        except Exception as e:
            last_err = str(e)
        time.sleep(0.5)
    print(f"ERROR: PDS not ready at {BASE_URL} (last: {last_err})", file=sys.stderr)
    sys.exit(1)


def create_session(handle: str, password: str) -> dict:
    """Create a session and return {did, accessJwt, handle}."""
    r = requests.post(
        f"{BASE_URL}/xrpc/com.atproto.server.createSession",
        json={"identifier": handle, "password": password},
        timeout=10,
    )
    if r.status_code != 200:
        raise RuntimeError(f"createSession failed for {handle}: {r.status_code} {r.text}")
    return r.json()


def get_convo_for_members(jwt: str, member_dids: list[str]) -> dict:
    """Get or create a conversation for the given members."""
    r = requests.post(
        f"{BASE_URL}/xrpc/chat.bsky.convo.getConvoForMembers",
        headers={"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"},
        json={"members": member_dids},
        timeout=10,
    )
    if r.status_code != 200:
        raise RuntimeError(f"getConvoForMembers failed: {r.status_code} {r.text}")
    return r.json()


def send_message(jwt: str, convo_id: str, text: str) -> dict:
    """Send a message in a conversation."""
    r = requests.post(
        f"{BASE_URL}/xrpc/chat.bsky.convo.sendMessage",
        headers={"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"},
        json={
            "convoId": convo_id,
            "message": {
                "$type": "chat.bsky.convo.def#messageRef",
                "text": text,
                "createdAt": NOW(),
            },
        },
        timeout=10,
    )
    if r.status_code != 200:
        raise RuntimeError(f"sendMessage failed: {r.status_code} {r.text}")
    return r.json()


def list_convos(jwt: str, limit: int = 20) -> dict:
    """List conversations for the authenticated user."""
    r = requests.get(
        f"{BASE_URL}/xrpc/chat.bsky.convo.listConvos?limit={limit}",
        headers={"Authorization": f"Bearer {jwt}"},
        timeout=10,
    )
    if r.status_code != 200:
        raise RuntimeError(f"listConvos failed: {r.status_code} {r.text}")
    return r.json()


def get_messages(jwt: str, convo_id: str, limit: int = 50) -> dict:
    """Get messages for a conversation."""
    r = requests.get(
        f"{BASE_URL}/xrpc/chat.bsky.convo.getMessages?convoId={convo_id}&limit={limit}",
        headers={"Authorization": f"Bearer {jwt}"},
        timeout=10,
    )
    if r.status_code != 200:
        raise RuntimeError(f"getMessages failed: {r.status_code} {r.text}")
    return r.json()


def main() -> None:
    if len(HANDLES) < 2:
        print("ERROR: Need at least 2 accounts for chat", file=sys.stderr)
        sys.exit(1)

    print(f"Waiting for PDS at {BASE_URL} ...")
    wait_for_server()
    print("PDS is up!")

    # Create sessions
    sessions: dict[str, dict] = {}
    for i, handle in enumerate(HANDLES):
        pwd = PASSWORDS[i] if i < len(PASSWORDS) else PASSWORDS[-1]
        try:
            session = create_session(handle, pwd)
            sessions[handle] = session
            print(f"  Logged in: {handle} ({session['did']})")
        except RuntimeError as e:
            print(f"  FAILED: {e}")
            sys.exit(1)

    dids = {h: s["did"] for h, s in sessions.items()}
    jwts = {h: s["accessJwt"] for h, s in sessions.items()}

    # ── DM Conversations ──────────────────────────────────────────────
    # Create pairwise DMs between first 3 accounts
    dm_pairs = []
    for i in range(min(len(HANDLES), 3)):
        for j in range(i + 1, min(len(HANDLES), 3)):
            dm_pairs.append((HANDLES[i], HANDLES[j]))

    dm_convo_ids: dict[tuple, str] = {}
    dm_messages: dict[tuple, list[tuple]] = {}  # (handle, text) pairs

    for h1, h2 in dm_pairs:
        pair = (h1, h2)
        print(f"\n=== DM: {h1} <-> {h2} ===")

        # Create convo (include both DIDs)
        convo = get_convo_for_members(jwts[h1], [dids[h1], dids[h2]])
        convo_data = convo.get("convo", convo)
        convo_id = convo_data.get("id", "")
        dm_convo_ids[pair] = convo_id
        print(f"  Convo ID: {convo_id}")

        # Exchange messages
        messages = [
            (h1, f"Hey {h2.split('.')[0]}! How's it going?"),
            (h2, f"Hey {h1.split('.')[0]}! Doing great, thanks!"),
            (h1, f"Have you seen the latest ATProto spec updates?"),
            (h2, f"Yes! The new XRPC methods are awesome 🚀"),
        ]
        dm_messages[pair] = []

        for sender, text in messages:
            msg = send_message(jwts[sender], convo_id, text)
            msg_id = msg.get("id", "?")
            dm_messages[pair].append((sender, text))
            short_id = msg_id[:30] + "..." if len(msg_id) > 30 else msg_id
            print(f"  [{sender}]: {text}")
            print(f"    msg_id: {short_id}")
            time.sleep(0.1)

    # ── Group Chat ────────────────────────────────────────────────────
    if len(HANDLES) >= 3:
        print(f"\n=== Group Chat: {', '.join(HANDLES[:3])} ===")
        group_dids = [dids[h] for h in HANDLES[:3]]
        group_convo = get_convo_for_members(jwts[HANDLES[0]], group_dids)
        group_data = group_convo.get("convo", group_convo)
        group_convo_id = group_data.get("id", "")
        print(f"  Convo ID: {group_convo_id}")

        group_messages = [
            (HANDLES[0], "Hey team! Group chat is live! 🎉"),
            (HANDLES[1], "Awesome! Love this decentralized chat 💬"),
            (HANDLES[2], "Count me in! This is the future 🔮"),
            (HANDLES[0], "Let's coordinate the relay deployment here"),
            (HANDLES[1], "Relay-to-chat pipeline is next! 🔄"),
            (HANDLES[2], "I'll handle the PLC integration side"),
        ]

        for sender, text in group_messages:
            msg = send_message(jwts[sender], group_convo_id, text)
            print(f"  [{sender}]: {text}")
            time.sleep(0.1)

    # ── Verification ──────────────────────────────────────────────────
    print("\n=== Verification ===")

    # List convos for first account
    convos = list_convos(jwts[HANDLES[0]])
    convo_list = convos.get("convos", [])
    print(f"  {HANDLES[0]} has {len(convo_list)} conversation(s)")
    for c in convo_list:
        members = [m.get("did", "?")[:25] for m in c.get("members", [])]
        print(f"    Convo {c.get('id', '?')[:30]}... members: {members}")

    # Verify messages in first DM
    if dm_convo_ids:
        first_pair = list(dm_convo_ids.keys())[0]
        convo_id = dm_convo_ids[first_pair]
        msgs = get_messages(jwts[first_pair[0]], convo_id)
        msg_list = msgs.get("messages", [])
        print(f"\n  Messages in {first_pair[0]} <-> {first_pair[1]}: {len(msg_list)}")
        for m in msg_list:
            sender = m.get("senderDid", "?")[-25:]
            text = m.get("text", "")[:50]
            print(f"    [{sender}]: {text}")

    # Verify group messages
    if len(HANDLES) >= 3 and group_convo_id:
        msgs = get_messages(jwts[HANDLES[0]], group_convo_id)
        msg_list = msgs.get("messages", [])
        print(f"\n  Messages in group chat: {len(msg_list)}")
        for m in msg_list:
            sender = m.get("senderDid", "?")[-25:]
            text = m.get("text", "")[:50]
            print(f"    [{sender}]: {text}")

    # ── Summary ───────────────────────────────────────────────────────
    print("\n=== Summary ===")
    print(f"  Accounts: {len(sessions)}")
    print(f"  DM conversations: {len(dm_convo_ids)}")
    total_dm_msgs = sum(len(v) for v in dm_messages.values())
    print(f"  DM messages sent: {total_dm_msgs}")
    if len(HANDLES) >= 3:
        print(f"  Group conversation: 1")
        print(f"  Group messages sent: {len(group_messages)}")
    print("  Done! ✅")


if __name__ == "__main__":
    main()
