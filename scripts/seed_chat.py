#!/usr/bin/env python3
"""Seed chat conversations and messages between existing accounts.

The script logs in as each configured account, creates pairwise direct
messages for the first three accounts, optionally creates a group chat, sends
sample messages, and reads conversations back to verify that chat.bsky.convo
endpoints are wired correctly.

Accounts must already exist. Use seed_demo_via_xrpc.py, seed_full_suite.py, or
seed_network.py first when starting from an empty local PDS.

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

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

# Add scripts/ to sys.path so direct execution can import the shared atproto
# helper package without packaging or virtualenv setup.
_scripts_dir = str(Path(__file__).resolve().parent)
if _scripts_dir not in sys.path:
    sys.path.insert(0, _scripts_dir)

from lib.atproto import (
    XrpcClient,
    XrpcError,
    wait_for_server,
    get_convo_for_members,
    send_message,
    list_convos,
    get_messages,
)

# ── Configuration ──────────────────────────────────────────────────────────

BASE_URL = os.environ.get("PDS_URL", "http://localhost:2583").rstrip("/")
ACCOUNTS_RAW = os.environ.get(
    "CHAT_ACCOUNTS", "alice.garazyk.xyz,bob.garazyk.xyz,carol.garazyk.xyz"
)
HANDLES = [h.strip() for h in ACCOUNTS_RAW.split(",") if h.strip()]
DEFAULT_PASSWORDS = "alicepass123,bobpass123,carolpass123"
SINGLE_PASSWORD = os.environ.get("CHAT_PASSWORD", "")
PASSWORDS_RAW = os.environ.get("CHAT_PASSWORDS", DEFAULT_PASSWORDS)
# CHAT_PASSWORD is a convenience for homogeneous demo accounts. Otherwise,
# CHAT_PASSWORDS maps positionally to CHAT_ACCOUNTS and pads with the last
# supplied password so callers can override only the unusual tail entries.
if SINGLE_PASSWORD:
    PASSWORDS = [SINGLE_PASSWORD] * len(HANDLES)
else:
    PASSWORDS = [p.strip() for p in PASSWORDS_RAW.split(",")]
    # Pad with last password if not enough provided
    while len(PASSWORDS) < len(HANDLES):
        PASSWORDS.append(PASSWORDS[-1] if PASSWORDS else "changeme")


# ── Main ──────────────────────────────────────────────────────────────────

def main() -> None:
    """Log in, create conversations, send messages, and verify reads."""
    if len(HANDLES) < 2:
        print("ERROR: Need at least 2 accounts for chat", file=sys.stderr)
        sys.exit(1)

    print(f"Waiting for PDS at {BASE_URL} ...")
    wait_for_server(BASE_URL)
    print("PDS is up!")

    client = XrpcClient(BASE_URL)

    # Create sessions first so every later step can use DID and accessJwt maps
    # without retrying login inside nested conversation loops.
    sessions: dict[str, dict] = {}
    for i, handle in enumerate(HANDLES):
        pwd = PASSWORDS[i] if i < len(PASSWORDS) else PASSWORDS[-1]
        try:
            session = client.create_session(handle, pwd)
            sessions[handle] = session
            print(f"  Logged in: {handle} ({session['did']})")
        except XrpcError as e:
            print(f"  FAILED: {e}")
            sys.exit(1)

    dids = {h: s["did"] for h, s in sessions.items()}
    jwts = {h: s["accessJwt"] for h, s in sessions.items()}

    # ── DM Conversations ──────────────────────────────────────────────
    # Create pairwise DMs between the first three accounts. Limiting the set
    # keeps the output readable while still covering multiple memberships.
    dm_pairs = []
    for i in range(min(len(HANDLES), 3)):
        for j in range(i + 1, min(len(HANDLES), 3)):
            dm_pairs.append((HANDLES[i], HANDLES[j]))

    dm_convo_ids: dict[tuple, str] = {}
    dm_messages: dict[tuple, list[tuple]] = {}  # (handle, text) pairs

    for h1, h2 in dm_pairs:
        pair = (h1, h2)
        print(f"\n=== DM: {h1} <-> {h2} ===")

        # Include both member DIDs. The chat endpoint returns an existing
        # conversation if membership already matches, making reruns harmless.
        convo = get_convo_for_members(client, jwts[h1], [dids[h1], dids[h2]])
        convo_data = convo.get("convo", convo)
        convo_id = convo_data.get("id", "")
        dm_convo_ids[pair] = convo_id
        print(f"  Convo ID: {convo_id}")

        # Exchange a short deterministic message sequence so verification can
        # compare message counts and visible text in local demo output.
        messages = [
            (h1, f"Hey {h2.split('.')[0]}! How's it going?"),
            (h2, f"Hey {h1.split('.')[0]}! Doing great, thanks!"),
            (h1, f"Have you seen the latest ATProto spec updates?"),
            (h2, f"Yes! The new XRPC methods are awesome!"),
        ]
        dm_messages[pair] = []

        for sender, text in messages:
            msg = send_message(client, jwts[sender], convo_id, text)
            msg_id = msg.get("id", "?")
            dm_messages[pair].append((sender, text))
            short_id = msg_id[:30] + "..." if len(msg_id) > 30 else msg_id
            print(f"  [{sender}]: {text}")
            print(f"    msg_id: {short_id}")
            time.sleep(0.1)

    # ── Group Chat ────────────────────────────────────────────────────
    group_convo_id = ""
    if len(HANDLES) >= 3:
        print(f"\n=== Group Chat: {', '.join(HANDLES[:3])} ===")
        group_dids = [dids[h] for h in HANDLES[:3]]
        group_convo = get_convo_for_members(client, jwts[HANDLES[0]], group_dids)
        group_data = group_convo.get("convo", group_convo)
        group_convo_id = group_data.get("id", "")
        print(f"  Convo ID: {group_convo_id}")

        group_messages = [
            (HANDLES[0], "Hey team! Group chat is live!"),
            (HANDLES[1], "Awesome! Love this decentralized chat"),
            (HANDLES[2], "Count me in! This is the future"),
            (HANDLES[0], "Let's coordinate the relay deployment here"),
            (HANDLES[1], "Relay-to-chat pipeline is next!"),
            (HANDLES[2], "I'll handle the PLC integration side"),
        ]

        for sender, text in group_messages:
            msg = send_message(client, jwts[sender], group_convo_id, text)
            print(f"  [{sender}]: {text}")
            time.sleep(0.1)

    # ── Verification ──────────────────────────────────────────────────
    print("\n=== Verification ===")

    # List conversations for the first account because it participates in every
    # seeded DM and, when present, the group chat.
    convos = list_convos(client, jwts[HANDLES[0]])
    convo_list = convos.get("convos", [])
    print(f"  {HANDLES[0]} has {len(convo_list)} conversation(s)")
    for c in convo_list:
        members = [m.get("did", "?")[:25] for m in c.get("members", [])]
        print(f"    Convo {c.get('id', '?')[:30]}... members: {members}")

    # Read one DM in detail to validate message retrieval and sender metadata.
    if dm_convo_ids:
        first_pair = list(dm_convo_ids.keys())[0]
        convo_id = dm_convo_ids[first_pair]
        msgs = get_messages(client, jwts[first_pair[0]], convo_id)
        msg_list = msgs.get("messages", [])
        print(f"\n  Messages in {first_pair[0]} <-> {first_pair[1]}: {len(msg_list)}")
        for m in msg_list:
            sender = m.get("senderDid", "?")[-25:]
            text = m.get("text", "")[:50]
            print(f"    [{sender}]: {text}")

    # Read group messages separately because group membership exercises a
    # different server-side conversation lookup path.
    if len(HANDLES) >= 3 and group_convo_id:
        msgs = get_messages(client, jwts[HANDLES[0]], group_convo_id)
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
    print("  Done!")


if __name__ == "__main__":
    main()
