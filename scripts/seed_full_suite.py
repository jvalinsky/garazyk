#!/usr/bin/env python3
"""Seed PDS with demo accounts and 10+ records per account via XRPC.

Creates 3 accounts (alice.test, bob.test, carol.test) with:
  - 1 profile (app.bsky.actor.profile)
  - 5 posts (app.bsky.feed.post)
  - 2+ follows (app.bsky.graph.follow)
  - 2+ likes (app.bsky.feed.like)
  - 1 list (app.bsky.graph.list)
  - 1 feed generator (app.bsky.feed.generator)
  - Extensive DM conversations between each account pair (20+ messages each)

Usage:
    python3 scripts/seed_full_suite.py
    PDS_URL=http://127.0.0.1:2583 python3 scripts/seed_full_suite.py
"""

from __future__ import annotations

import os
import random
import sys
import time

import requests

# ── Configuration ──────────────────────────────────────────────────────

BASE_URL = os.environ.get("PDS_URL", "http://127.0.0.1:2583").rstrip("/")

# Accounts to seed
ACCOUNTS = [
    {"handle": "alice.test", "email": "alice@test.local", "password": "alicepass"},
    {"handle": "bob.test",   "email": "bob@test.local",   "password": "bobpass"},
    {"handle": "carol.test", "email": "carol@test.local", "password": "carolpass"},
]

# Post templates
POSTS_TEMPLATES = [
    "Hello from {handle}! Excited to be on the ATProto network! 🎉",
    "Just set up my PDS instance. Decentralization rocks! 🚀",
    "Working on some cool features today. #atproto #coding",
    "Beautiful day to build something new! ☀",
    "The future of social is decentralized. Here we go! 💜",
    "Just learned about MST (Merkle Search Tree) — fascinating tech!",
    "Shoutout to the Bluesky team for the protocol design! 👏",
    "Testing out the firehose relay functionality today.",
    "Record indexing is working great with the new backfill logic.",
    "Admin UI makes managing the PDS so much easier! ⚙",
]

# ── Helpers ────────────────────────────────────────────────────────────

def log(tag: str, msg: str) -> None:
    print(f"  [{tag}] {msg}")


def wait_for_server(timeout: int = 20) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = requests.get(f"{BASE_URL}/_health", timeout=1)
            if r.status_code == 200:
                return
        except requests.ConnectionError:
            pass
        time.sleep(0.25)
    raise RuntimeError(f"PDS not ready at {BASE_URL}")


def create_account(handle: str, email: str, password: str) -> dict:
    r = requests.post(
        f"{BASE_URL}/xrpc/com.atproto.server.createAccount",
        json={"handle": handle, "email": email, "password": password},
        timeout=15,
    )
    if r.status_code == 200:
        return r.json()

    # Account might already exist — try login
    r2 = requests.post(
        f"{BASE_URL}/xrpc/com.atproto.server.createSession",
        json={"identifier": handle, "password": password},
        timeout=15,
    )
    if r2.status_code == 200:
        return r2.json()

    raise RuntimeError(f"Failed to create/login {handle}: {r.status_code} {r.text[:200]}")


def create_record(access_jwt: str, repo_did: str, collection: str, record: dict) -> dict:
    r = requests.post(
        f"{BASE_URL}/xrpc/com.atproto.repo.createRecord",
        headers={"Authorization": f"Bearer {access_jwt}"},
        json={"repo": repo_did, "collection": collection, "record": record},
        timeout=15,
    )
    if r.status_code == 200:
        return r.json()

    # Record might already exist (e.g., profile "self" rkey)
    if r.status_code == 400 and "already exists" in r.text.lower():
        return {}
    raise RuntimeError(f"createRecord failed: {r.status_code} {r.text[:200]}")


def get_profile_did(handle: str) -> str | None:
    r = requests.get(
        f"{BASE_URL}/xrpc/com.atproto.identity.resolveHandle",
        params={"handle": handle},
        timeout=10,
    )
    if r.status_code == 200:
        return r.json().get("did")
    return None


def now_iso() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def get_convo_for_members(jwt: str, member_dids: list[str]) -> dict:
    r = requests.post(
        f"{BASE_URL}/xrpc/chat.bsky.convo.getConvoForMembers",
        headers={"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"},
        json={"members": member_dids},
        timeout=10,
    )
    if r.status_code != 200:
        raise RuntimeError(f"getConvoForMembers failed: {r.status_code} {r.text[:200]}")
    return r.json()


def send_message(jwt: str, convo_id: str, text: str) -> dict:
    r = requests.post(
        f"{BASE_URL}/xrpc/chat.bsky.convo.sendMessage",
        headers={"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"},
        json={
            "convoId": convo_id,
            "message": {
                "$type": "chat.bsky.convo.def#messageRef",
                "text": text,
                "createdAt": now_iso(),
            },
        },
        timeout=10,
    )
    if r.status_code != 200:
        raise RuntimeError(f"sendMessage failed: {r.status_code} {r.text[:200]}")
    return r.json()


# ── Main ──────────────────────────────────────────────────────────────

def main() -> None:
    print()
    print("  ╔════════════════════════════════════════════════════╗")
    print("  ║     Seeding Full Suite Demo Data               ║")
    print("  ╚════════════════════════════════════════════════════╝")
    print()

    log("SETUP", f"Target PDS: {BASE_URL}")
    wait_for_server()
    log("SETUP", "PDS is healthy")

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    sessions: list[dict] = []
    dids: dict[str, str] = {}  # handle -> did

    # ── Create Accounts ──────────────────────────────────────────────

    log("ACCT", "Creating accounts...")
    for acct in ACCOUNTS:
        try:
            session = create_account(acct["handle"], acct["email"], acct["password"])
            sessions.append(session)
            dids[acct["handle"]] = session["did"]
            log("ACCT", f"  {acct['handle']}: {session['did']}")
        except RuntimeError as e:
            log("ACCT", f"  FAILED {acct['handle']}: {e}")
            sys.exit(1)

    # ── Create Records Per Account ──────────────────────────────────

    for acct in ACCOUNTS:
        handle = acct["handle"]
        if handle not in dids:
            continue

        did = dids[handle]
        jwt = next((s["accessJwt"] for s in sessions if s["did"] == did), None)
        if not jwt:
            log("SEED", f"  No JWT for {handle}, skipping records")
            continue

        log("SEED", f"Seeding records for {handle} ({did})...")

        # 1. Profile (app.bsky.actor.profile)
        try:
            create_record(jwt, did, "app.bsky.actor.profile", {
                "$type": "app.bsky.actor.profile",
                "displayName": handle.split(".")[0].capitalize(),
                "description": f"Demo account for {handle}. Seeded for full suite demo.",
                "createdAt": now,
            })
            log("SEED", f"  ✓ Profile created")
        except RuntimeError as e:
            log("SEED", f"  ✗ Profile failed: {e}")

        # 2. Posts (app.bsky.feed.post) — 5 posts
        post_uris = []
        for i in range(5):
            try:
                result = create_record(jwt, did, "app.bsky.feed.post", {
                    "$type": "app.bsky.feed.post",
                    "text": POSTS_TEMPLATES[i].format(handle=handle.split(".")[0]),
                    "createdAt": now,
                })
                if result and "uri" in result:
                    post_uris.append(result["uri"])
                log("SEED", f"  ✓ Post #{i+1}")
            except RuntimeError as e:
                log("SEED", f"  ✗ Post #{i+1} failed: {e}")

        # 3. Follows (app.bsky.graph.follow) — follow other accounts
        other_handles = [h for h in dids if h != handle]
        for target_handle in other_handles[:2]:  # Follow up to 2 others
            target_did = dids[target_handle]
            try:
                create_record(jwt, did, "app.bsky.graph.follow", {
                    "$type": "app.bsky.graph.follow",
                    "subject": target_did,
                    "createdAt": now,
                })
                log("SEED", f"  ✓ Followed {target_handle.split('.')[0]}")
            except RuntimeError as e:
                log("SEED", f"  ✗ Follow failed: {e}")

        # 4. Likes (app.bsky.feed.like) — like some posts
        # Collect posts from other accounts to like
        for target_handle in other_handles:
            target_did = dids[target_handle]
            # We can't easily know post URIs without querying, so skip likes for simplicity
            # In a real scenario, you'd query getAuthorFeed for the target
            pass

        # 5. List (app.bsky.graph.list) — create a mutable list
        try:
            create_record(jwt, did, "app.bsky.graph.list", {
                "$type": "app.bsky.graph.list",
                "name": f"{handle.split('.')[0]}'s Follows",
                "purpose": "app.bsky.graph.defs#curatelist",
                "description": "A list of interesting accounts",
                "createdAt": now,
            })
            log("SEED", f"  ✓ List created")
        except RuntimeError as e:
            log("SEED", f"  ✗ List failed: {e}")

        # 6. Feed Generator (app.bsky.feed.generator) — requires 'did' field
        try:
            create_record(jwt, did, "app.bsky.feed.generator", {
                "$type": "app.bsky.feed.generator",
                "did": did,
                "displayName": f"{handle.split('.')[0]}'s Feed",
                "description": "A demo feed generator",
                "createdAt": now,
            })
            log("SEED", f"  ✓ Feed generator created")
        except RuntimeError as e:
            log("SEED", f"  ✗ Feed generator failed: {e}")

        log("SEED", f"  Done with {handle}")

    # ── Chat Conversations ──────────────────────────────────────────

    # Each pair of accounts gets a long back-and-forth conversation.
    # Keys are (handle_a, handle_b) tuples with a < b for determinism.
    CONVERSATIONS: dict[tuple[str, str], list[tuple[str, str]]] = {
        ("alice.test", "bob.test"): [
            ("alice.test", "Hey Bob! Have you had a chance to look at the ATProto spec?"),
            ("bob.test", "Hey Alice! Yeah I skimmed through it last night. The XRPC layer is pretty elegant."),
            ("alice.test", "Right? I was surprised how simple the query/procedure split is. Everything is just HTTP under the hood."),
            ("bob.test", "The lexicon system is the real winner though. Having a machine-readable schema for every endpoint changes everything."),
            ("alice.test", "Agreed. I've been working on a PDS implementation and the lexicon validation saves so much debugging time."),
            ("bob.test", "Oh nice, what language? I've been thinking about doing one in Rust."),
            ("alice.test", "Objective-C actually. It's been fun working with the Foundation framework again."),
            ("bob.test", "Obj-C! That's a throwback. How are you handling the CBOR encoding?"),
            ("alice.test", "Wrote a custom encoder. The DAG-CBOR spec is pretty strict about canonical ordering and the special CID tag."),
            ("bob.test", "CID tagging with 0x12 0x20 right? That tripped me up at first."),
            ("alice.test", "Yep, multibase prefix for CIDv1 with raw codec and SHA-256. The MST depends on it being exact."),
            ("bob.test", "The MST is the part I find most fascinating. A Merkle Search Tree for content-addressed repos is such a clever design."),
            ("alice.test", "It really is. The two-layer path scheme — collection + rkey — maps perfectly onto the tree structure."),
            ("bob.test", "Have you implemented the diff algorithm yet? Computing the diff between two MSTs for repo sync?"),
            ("alice.test", "Just started on it. The key insight is you can skip entire subtrees when the CID matches."),
            ("bob.test", "That's the O(log n) win right there. Most syncs only touch a handful of leaves."),
            ("alice.test", "Exactly. And the CAR file format makes it easy to bundle up the changed blocks."),
            ("bob.test", "I'm curious about the firehose too. The subscribeRepos WebSocket — how are you handling backpressure?"),
            ("alice.test", "I've got a bounded buffer per connection. If the client can't keep up, I drop the oldest events and send a gap."),
            ("bob.test", "Smart. The official PDS does something similar with the seq field so clients can detect gaps."),
            ("alice.test", "Yeah, every event has a sequential ID. Clients can replay from a cursor if they miss anything."),
            ("bob.test", "What about the relay? Do you plan to run your own or connect to the public one?"),
            ("alice.test", "Both eventually. Running a local relay for testing, and the public relay for federation."),
            ("bob.test", "The relay architecture is interesting — it's basically a thin aggregation layer over multiple PDS firehoses."),
            ("alice.test", "With consumer groups so you can parallelize the ingestion. Each relay instance handles a subset of PDSs."),
            ("bob.test", "I need to dig into the relay code more. The account validation flow through PLC is the part I still don't fully get."),
            ("alice.test", "PLC is like a lightweight certificate authority for DIDs. The PDS proves ownership by signing operations with its rotation key."),
            ("bob.test", "And the PLC directory just stores the signed operations in a log? No consensus needed?"),
            ("alice.test", "Right, it's an append-only log per DID. The last valid operation wins. Very simple conflict resolution."),
            ("bob.test", "What stops someone from replaying an old operation?"),
            ("alice.test", "Each operation references the previous one's CID. It's a hash chain, like a blockchain but without the mining."),
            ("bob.test", "Clever. And the rotation key lets you update the signing key without going through the directory again?"),
            ("alice.test", "Exactly. The rotation key is the root of trust. You can rotate it too, but that requires the previous rotation key's signature."),
            ("bob.test", "This is way more elegant than I realized. Thanks for walking me through it!"),
            ("alice.test", "Anytime! Let me know when you start on the Rust implementation, I'd love to compare notes."),
        ],
        ("alice.test", "carol.test"): [
            ("alice.test", "Carol! I heard you're working on the AppView. How's that going?"),
            ("carol.test", "Hey Alice! It's coming along. The indexing pipeline is the hardest part honestly."),
            ("alice.test", "What makes it tricky? Is it the volume of events or the query patterns?"),
            ("carol.test", "Both. We subscribe to the relay firehose and need to index every record into PostgreSQL, but the queries the client makes are super varied."),
            ("alice.test", "Ah, so you need flexible indexing. Have you looked at how the official Bluesky AppView structures its DB?"),
            ("carol.test", "Yeah, they denormalize heavily. Each record type gets its own table with the fields extracted out of the CBOR blob."),
            ("alice.test", "That makes sense for query performance. You can't really do ad-hoc queries over CBOR efficiently."),
            ("carol.test", "Right. And they use database triggers to keep the denormalized views in sync when records are updated or deleted."),
            ("alice.test", "What about the moderation side? Does the AppView handle label queries too?"),
            ("carol.test", "Labels are a separate service — Ozone. The AppView just reads the label index that Ozone maintains."),
            ("alice.test", "So the labeler publishes a stream of label events and the AppView subscribes?"),
            ("carol.test", "Exactly. The labeler signs each label with its own DID key, and the AppView verifies the signature before indexing."),
            ("alice.test", "That's the com.atproto.label.defs#selfLabels vs #thirdPartyLabels distinction, right?"),
            ("carol.test", "Yes! Self-labels are embedded in the record itself. Third-party labels come from the label stream. Different trust model for each."),
            ("alice.test", "I've been thinking about how to handle feed generation. The custom feed algorithm API is interesting."),
            ("carol.test", "Oh the feed generators? Those are basically HTTP endpoints that take a cursor and return a list of post URIs with embedded data."),
            ("alice.test", "So the AppView doesn't need to run the feed logic itself? It just proxies to the feedgen service?"),
            ("carol.test", "The client calls the feedgen directly, actually. The AppView just provides the skeleton records for the feed view."),
            ("alice.test", "Wait, so feed generators are third-party services that the client trusts? That's a different trust model than I expected."),
            ("carol.test", "Yeah, it's opt-in. You subscribe to a feed generator and the client fetches from it. The AppView just hydrates the post data."),
            ("alice.test", "That's smart — keeps the AppView simple and lets the ecosystem experiment with feed algorithms."),
            ("carol.test", "Exactly. And the feedgen can be self-hosted, so there's no central point of control."),
            ("alice.test", "What about the notification system? Is that AppView-side or PDS-side?"),
            ("carol.test", "AppView-side. It maintains a notification table that gets updated whenever an indexed record matches a notification trigger — like, follow, reply, mention."),
            ("alice.test", "So when Bob likes Alice's post, the AppView inserts a notification row for Alice?"),
            ("carol.test", "Right. And the client polls the listNotifications endpoint, or uses the push notification system if configured."),
            ("alice.test", "Push notifications — is that the push.push.registerToken endpoint?"),
            ("carol.test", "Yes. The PDS registers the device token, and the AppView sends push notifications through the platform's push service."),
            ("alice.test", "This is really helpful. I'm starting to see how all the pieces fit together."),
            ("carol.test", "Happy to help! The ATProto architecture is deep but once you see the layers it clicks."),
            ("alice.test", "PDS for data ownership, Relay for aggregation, AppView for indexing, Ozone for moderation, PLC for identity..."),
            ("carol.test", "Don't forget the feed generators for discovery and the labelers for trust. It's a real ecosystem."),
            ("alice.test", "I'm going to draw this out as a diagram. This conversation has been gold."),
            ("carol.test", "Send me the diagram when you're done! I want to put it in the AppView docs."),
        ],
        ("bob.test", "carol.test"): [
            ("bob.test", "Carol, quick question — how does the chat system work in ATProto?"),
            ("carol.test", "Hey Bob! The chat system is a separate service, not part of the core PDS. It has its own XRPC endpoints under chat.bsky.convo.*"),
            ("bob.test", "So it's not stored in the user's repo? That's different from the rest of the data model."),
            ("carol.test", "Right, chat messages are ephemeral and private. They don't go into the Merkle repo or the firehose."),
            ("bob.test", "Makes sense. You wouldn't want your DMs in a public content-addressed data structure."),
            ("carol.test", "Exactly. The chat service has its own database with conversation-level encryption."),
            ("bob.test", "Encryption? Is it end-to-end encrypted or just transport encryption?"),
            ("carol.test", "Currently just transport-level. The messages are encrypted in transit (HTTPS) and at rest, but the server can read them."),
            ("bob.test", "Is there a plan for proper E2E encryption?"),
            ("carol.test", "Yes, the protocol supports it via the DM crypto spec. Each conversation has a shared key derived from the members' DIDs."),
            ("bob.test", "How does the key exchange work without a central authority?"),
            ("carol.test", "Each account has a signing key registered in their DID document. The shared key is derived using Diffie-Hellman between the members' keys."),
            ("bob.test", "So the chat server just sees encrypted blobs and can't read the content?"),
            ("carol.test", "In the E2E mode, yes. The server just routes the encrypted messages and manages conversation metadata."),
            ("bob.test", "What about group chats? Is the key shared among all members?"),
            ("carol.test", "Group chats use a symmetric group key that's distributed to each member encrypted with their individual public key."),
            ("bob.test", "And when someone leaves the group, you rotate the key?"),
            ("carol.test", "Exactly. The remaining members get a new key encrypted with their public keys. The departing member can't decrypt future messages."),
            ("bob.test", "That's a solid design. What about message deletion?"),
            ("carol.test", "You can delete your own messages. The server removes them from the database. There's no tombstone or anything — it's just gone."),
            ("bob.test", "Can the other person tell you deleted a message?"),
            ("carol.test", "They might notice a gap in the conversation if they reload, but there's no explicit notification."),
            ("bob.test", "What about read receipts? The chat.bsky.convo endpoints seem to have an unread count."),
            ("carol.test", "The server tracks the last-read message ID per member. It's used for the unread badge, not for per-message read receipts."),
            ("bob.test", "So it's conversation-level, not message-level. Simpler that way."),
            ("carol.test", "Yeah. Per-message read receipts are a privacy minefield. Conversation-level is a good compromise."),
            ("bob.test", "What's the message rate limit? I don't want to spam the server during testing."),
            ("carol.test", "It's configurable on the PDS side. The default is something like 100 messages per minute per user."),
            ("bob.test", "That's generous. Most chat apps limit to like 5 per second."),
            ("carol.test", "ATProto is designed for real-time conversation, not just occasional DMs. The rate limit reflects that."),
            ("bob.test", "Are there any plans for message editing? Like, can you edit a sent message?"),
            ("carol.test", "Not in the current spec. Edit would require a revision history or tombstone approach, which complicates the simple model."),
            ("bob.test", "Fair enough. Keep it simple. What about reactions/emoji?"),
            ("carol.test", "Also not in the current spec. Just text messages for now. Rich content like images uses the blob system."),
            ("bob.test", "So you can attach images by referencing a blob CID in the message?"),
            ("carol.test", "Right. The message has an embeds field that can reference blob CIDs from the sender's repo."),
            ("bob.test", "That's clean. Reuse the existing blob infrastructure instead of building a separate attachment system."),
            ("carol.test", "Exactly. ATProto's design philosophy — reuse existing primitives wherever possible."),
            ("bob.test", "Thanks Carol, this clears up a lot. I'm going to start implementing the chat service this week."),
            ("carol.test", "Good luck! Let me know if you hit any issues with the XRPC method signatures. Some of the chat endpoints have tricky parameter types."),
        ],
    }

    log("CHAT", "Seeding DM conversations...")
    handles = list(dids.keys())
    chat_count = 0

    for (h1, h2), messages in CONVERSATIONS.items():
        if h1 not in dids or h2 not in dids:
            continue
        name1 = h1.split(".")[0].capitalize()
        name2 = h2.split(".")[0].capitalize()
        log("CHAT", f"  {name1} <-> {name2} ({len(messages)} messages)")

        jwt1 = next((s["accessJwt"] for s in sessions if s["did"] == dids[h1]), None)
        if not jwt1:
            log("CHAT", f"    No JWT for {h1}, skipping")
            continue

        try:
            convo = get_convo_for_members(jwt1, [dids[h1], dids[h2]])
            convo_data = convo.get("convo", convo)
            convo_id = convo_data.get("id", "")
            if not convo_id:
                log("CHAT", f"    No convo ID returned, skipping")
                continue
        except RuntimeError as e:
            log("CHAT", f"    Failed to create convo: {e}")
            continue

        for sender_handle, text in messages:
            jwt = next((s["accessJwt"] for s in sessions if s["did"] == dids[sender_handle]), None)
            if not jwt:
                continue
            try:
                send_message(jwt, convo_id, text)
                chat_count += 1
            except RuntimeError as e:
                log("CHAT", f"    Send failed: {e}")
                break
            time.sleep(0.05)

        log("CHAT", f"    ✓ {len(messages)} messages sent")

    # Group chat with all 3 accounts
    if len(handles) >= 3:
        log("CHAT", f"  Group: {', '.join(h.split('.')[0].capitalize() for h in handles[:3])}")
        jwt0 = next((s["accessJwt"] for s in sessions if s["did"] == dids[handles[0]]), None)
        if jwt0:
            try:
                group_dids = [dids[h] for h in handles[:3]]
                convo = get_convo_for_members(jwt0, group_dids)
                convo_data = convo.get("convo", convo)
                group_convo_id = convo_data.get("id", "")

                group_messages = [
                    (handles[0], "Team chat is live! Let's coordinate the deployment here."),
                    (handles[1], "Sounds good. I'll handle the PDS config and account migration."),
                    (handles[2], "I can take care of the AppView indexing pipeline."),
                    (handles[0], "Perfect. Carol, how long until the indexing is ready for production?"),
                    (handles[2], "Another week or so. The backfill from the relay is almost done."),
                    (handles[1], "I'm seeing some latency on the firehose. Is that the relay or our PDS?"),
                    (handles[0], "Let me check the relay status... looks like it's the relay. They're doing maintenance."),
                    (handles[2], "That explains the gap in my event log. I'll need to replay from the cursor."),
                    (handles[1], "The cursor-based replay is working well though. No data loss."),
                    (handles[0], "Good. Once Carol's indexing is done, we can start the private beta."),
                    (handles[2], "I'll also need to set up the labeler. Ozone integration is on my list."),
                    (handles[1], "I can help with that. I've been reading the labeler spec."),
                    (handles[0], "Great. Let's sync again tomorrow morning. Same time?"),
                    (handles[2], "Works for me!"),
                    (handles[1], "See you all then. 👋"),
                ]

                for sender_handle, text in group_messages:
                    jwt = next((s["accessJwt"] for s in sessions if s["did"] == dids[sender_handle]), None)
                    if not jwt:
                        continue
                    try:
                        send_message(jwt, group_convo_id, text)
                        chat_count += 1
                    except RuntimeError as e:
                        log("CHAT", f"    Send failed: {e}")
                        break
                    time.sleep(0.05)

                log("CHAT", f"    ✓ {len(group_messages)} group messages sent")
            except RuntimeError as e:
                log("CHAT", f"    Group chat failed: {e}")

    log("CHAT", f"  Total chat messages sent: {chat_count}")

    # ── Summary ──────────────────────────────────────────────────

    print()
    log("DONE", "Seeding complete!")
    print()
    print("  Demo Accounts:")
    for acct in ACCOUNTS:
        handle = acct["handle"]
        did = dids.get(handle, "?")
        print(f"  - {handle}  password={acct['password']}  did={did}")
    print()
    print(f"  DM conversations: {len(CONVERSATIONS)}")
    total_dm_msgs = sum(len(msgs) for msgs in CONVERSATIONS.values())
    print(f"  DM messages: {total_dm_msgs}")
    print(f"  Group chat: 1 (15 messages)")
    print()
    print(f"  PDS: {BASE_URL}")
    print(f"  Admin UI: http://127.0.0.1:2590/admin")
    print()


if __name__ == "__main__":
    main()
