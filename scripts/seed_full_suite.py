#!/usr/bin/env python3
"""Seed full-suite demo data through public XRPC endpoints.

Creates 3 accounts (alice.test, bob.test, carol.test) with:
  - 1 profile (app.bsky.actor.profile)
  - 5 posts (app.bsky.feed.post)
  - 2+ follows (app.bsky.graph.follow)
  - 2+ likes (app.bsky.feed.like)
  - 1 list (app.bsky.graph.list)
  - 1 feed generator (app.bsky.feed.generator)
  - Extensive DM conversations between each account pair (20+ messages each)

The seeder intentionally uses the same XRPC surface that clients use instead
of direct database writes. That keeps the demo data representative and catches
endpoint, auth, and validation regressions during full-stack smoke tests.

Usage:
    python3 scripts/seed_full_suite.py
    PDS_URL=http://127.0.0.1:2583 python3 scripts/seed_full_suite.py
    PDS_URL=http://127.0.0.1:2583 CHAT_URL=http://127.0.0.1:2585 python3 scripts/seed_full_suite.py
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

# Add scripts/ to sys.path so the shared atproto helper package is available
# when the script is invoked from the repository checkout.
_scripts_dir = str(Path(__file__).resolve().parent)
if _scripts_dir not in sys.path:
    sys.path.insert(0, _scripts_dir)

from lib.atproto import (
    XrpcClient,
    XrpcError,
    create_account_or_login,
    create_record_idempotent,
    get_convo_for_members,
    send_message,
    now_iso,
    wait_for_server,
    DEFAULT_ACCOUNTS,
    DEFAULT_POSTS_TEMPLATES,
)

# ── Configuration ──────────────────────────────────────────────────────

BASE_URL = os.environ.get("PDS_URL", "http://127.0.0.1:2583").rstrip("/")
CHAT_URL = os.environ.get("CHAT_URL", BASE_URL).rstrip("/")

# ── Main ──────────────────────────────────────────────────────────────

def main() -> None:
    """Create demo accounts, repo records, and chat conversations."""
    print()
    print("  ╔════════════════════════════════════════════════════╗")
    print("  ║     Seeding Full Suite Demo Data               ║")
    print("  ╚════════════════════════════════════════════════════╝")
    print()

    print(f"  [SETUP] Target PDS: {BASE_URL}")
    wait_for_server(BASE_URL)
    print("  [SETUP] PDS is healthy")
    print(f"  [SETUP] Target Chat: {CHAT_URL}")
    if CHAT_URL != BASE_URL:
        wait_for_server(CHAT_URL)
        print("  [SETUP] Chat is healthy")

    pds_client = XrpcClient(BASE_URL)
    chat_client = XrpcClient(CHAT_URL)

    now = now_iso()
    sessions: list[dict] = []
    dids: dict[str, str] = {}  # handle -> did, used to build follows and chat memberships
    seed_errors: list[str] = []

    # ── Create Accounts ──────────────────────────────────────────────

    print("  [ACCT] Creating accounts...")
    for acct in DEFAULT_ACCOUNTS:
        try:
            session = create_account_or_login(
                pds_client, acct["handle"], acct["email"], acct["password"]
            )
            sessions.append(session)
            dids[acct["handle"]] = session["did"]
            print(f"  [ACCT]   {acct['handle']}: {session['did']}")
        except XrpcError as e:
            print(f"  [ACCT]   FAILED {acct['handle']}: {e}")
            sys.exit(1)

    # ── Create Records Per Account ──────────────────────────────────

    for acct in DEFAULT_ACCOUNTS:
        handle = acct["handle"]
        if handle not in dids:
            continue

        did = dids[handle]
        jwt = next((s["accessJwt"] for s in sessions if s["did"] == did), None)
        if not jwt:
            print(f"  [SEED]   No JWT for {handle}, skipping records")
            continue

        print(f"  [SEED] Seeding records for {handle} ({did})...")

        # Profiles give AppView/UI smoke tests stable display-name data to
        # verify after relay backfill.
        try:
            create_record_idempotent(pds_client, did, "app.bsky.actor.profile", {
                "$type": "app.bsky.actor.profile",
                "displayName": handle.split(".")[0].capitalize(),
                "description": f"Demo account for {handle}. Seeded for full suite demo.",
                "createdAt": now,
            }, jwt)
            print(f"  [SEED]   ✓ Profile created")
        except XrpcError as e:
            print(f"  [SEED]   ✗ Profile failed: {e}")
            seed_errors.append(f"profile {handle}: {e}")

        # Posts provide feed, author-feed, and notification source material.
        # We keep their URIs for future like/reply expansion.
        post_uris = []
        for i in range(5):
            try:
                result = create_record_idempotent(pds_client, did, "app.bsky.feed.post", {
                    "$type": "app.bsky.feed.post",
                    "text": DEFAULT_POSTS_TEMPLATES[i].format(handle=handle.split(".")[0]),
                    "createdAt": now,
                }, jwt)
                if result and "uri" in result:
                    post_uris.append(result["uri"])
                print(f"  [SEED]   ✓ Post #{i+1}")
            except XrpcError as e:
                print(f"  [SEED]   ✗ Post #{i+1} failed: {e}")
                seed_errors.append(f"post {handle} #{i+1}: {e}")

        # Follow records create a non-trivial social graph for timeline and
        # graph endpoint checks.
        other_handles = [h for h in dids if h != handle]
        for target_handle in other_handles[:2]:  # Follow up to 2 others
            target_did = dids[target_handle]
            try:
                create_record_idempotent(pds_client, did, "app.bsky.graph.follow", {
                    "$type": "app.bsky.graph.follow",
                    "subject": target_did,
                    "createdAt": now,
                }, jwt)
                print(f"  [SEED]   ✓ Followed {target_handle.split('.')[0]}")
            except XrpcError as e:
                print(f"  [SEED]   ✗ Follow failed: {e}")
                seed_errors.append(f"follow {handle}->{target_handle}: {e}")

        # Placeholder for likes. The surrounding control flow is left intact so
        # post URI collection can be expanded without restructuring the seeder.
        for target_handle in other_handles:
            target_did = dids[target_handle]
            pass

        # Lists cover graph collection records beyond simple follows.
        try:
            create_record_idempotent(pds_client, did, "app.bsky.graph.list", {
                "$type": "app.bsky.graph.list",
                "name": f"{handle.split('.')[0]}'s Follows",
                "purpose": "app.bsky.graph.defs#curatelist",
                "description": "A list of interesting accounts",
                "createdAt": now,
            }, jwt)
            print(f"  [SEED]   ✓ List created")
        except XrpcError as e:
            print(f"  [SEED]   ✗ List failed: {e}")
            seed_errors.append(f"list {handle}: {e}")

        # Feed generators exercise a record type that requires the actor DID in
        # the payload, not just in the repo parameter.
        try:
            create_record_idempotent(pds_client, did, "app.bsky.feed.generator", {
                "$type": "app.bsky.feed.generator",
                "did": did,
                "displayName": f"{handle.split('.')[0]}'s Feed",
                "description": "A demo feed generator",
                "createdAt": now,
            }, jwt)
            print(f"  [SEED]   ✓ Feed generator created")
        except XrpcError as e:
            print(f"  [SEED]   ✗ Feed generator failed: {e}")
            seed_errors.append(f"feed generator {handle}: {e}")

        print(f"  [SEED]   Done with {handle}")

    # ── Chat Conversations ──────────────────────────────────────────

    # Each account pair gets a long back-and-forth conversation so the Admin UI
    # and chat APIs have realistic scrollable content. Keys are sorted tuples
    # for deterministic output across runs.
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

    print("  [CHAT] Seeding DM conversations...")
    handles = list(dids.keys())
    chat_count = 0
    expected_chat_count = 0

    for (h1, h2), messages in CONVERSATIONS.items():
        if h1 not in dids or h2 not in dids:
            continue
        expected_chat_count += len(messages)
        name1 = h1.split(".")[0].capitalize()
        name2 = h2.split(".")[0].capitalize()
        print(f"  [CHAT]   {name1} <-> {name2} ({len(messages)} messages)")

        jwt1 = next((s["accessJwt"] for s in sessions if s["did"] == dids[h1]), None)
        if not jwt1:
            print(f"  [CHAT]     No JWT for {h1}, skipping")
            seed_errors.append(f"chat {h1}<->{h2}: missing JWT for {h1}")
            continue

        try:
            convo = get_convo_for_members(chat_client, jwt1, [dids[h1], dids[h2]])
            convo_data = convo.get("convo", convo)
            convo_id = convo_data.get("id", "")
            if not convo_id:
                print(f"  [CHAT]     No convo ID returned, skipping")
                seed_errors.append(f"chat {h1}<->{h2}: no convo id returned")
                continue
        except XrpcError as e:
            print(f"  [CHAT]     Failed to create convo: {e}")
            seed_errors.append(f"chat {h1}<->{h2}: failed to create convo: {e}")
            continue

        sent_for_convo = 0
        for sender_handle, text in messages:
            jwt = next((s["accessJwt"] for s in sessions if s["did"] == dids[sender_handle]), None)
            if not jwt:
                seed_errors.append(f"chat {h1}<->{h2}: missing JWT for sender {sender_handle}")
                continue
            try:
                send_message(chat_client, jwt, convo_id, text)
                chat_count += 1
                sent_for_convo += 1
            except XrpcError as e:
                print(f"  [CHAT]     Send failed: {e}")
                seed_errors.append(f"chat {h1}<->{h2}: send failed for {sender_handle}: {e}")
                break
            time.sleep(0.05)

        if sent_for_convo == len(messages):
            print(f"  [CHAT]     ✓ {sent_for_convo}/{len(messages)} messages sent")
        else:
            print(f"  [CHAT]     ✗ {sent_for_convo}/{len(messages)} messages sent")
            seed_errors.append(f"chat {h1}<->{h2}: sent {sent_for_convo}/{len(messages)} messages")

    # Group chat with all 3 accounts
    if len(handles) >= 3:
        print(f"  [CHAT]   Group: {', '.join(h.split('.')[0].capitalize() for h in handles[:3])}")
        jwt0 = next((s["accessJwt"] for s in sessions if s["did"] == dids[handles[0]]), None)
        if jwt0:
            try:
                group_dids = [dids[h] for h in handles[:3]]
                convo = get_convo_for_members(chat_client, jwt0, group_dids)
                convo_data = convo.get("convo", convo)
                group_convo_id = convo_data.get("id", "")
                if not group_convo_id:
                    raise XrpcError("chat.bsky.convo.getConvoForMembers", 200, "missing group convo id")

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
                    (handles[1], "See you all then."),
                ]

                expected_chat_count += len(group_messages)
                sent_for_group = 0
                for sender_handle, text in group_messages:
                    jwt = next((s["accessJwt"] for s in sessions if s["did"] == dids[sender_handle]), None)
                    if not jwt:
                        seed_errors.append(f"group chat: missing JWT for sender {sender_handle}")
                        continue
                    try:
                        send_message(chat_client, jwt, group_convo_id, text)
                        chat_count += 1
                        sent_for_group += 1
                    except XrpcError as e:
                        print(f"  [CHAT]     Send failed: {e}")
                        seed_errors.append(f"group chat: send failed for {sender_handle}: {e}")
                        break
                    time.sleep(0.05)

                if sent_for_group == len(group_messages):
                    print(f"  [CHAT]     ✓ {sent_for_group}/{len(group_messages)} group messages sent")
                else:
                    print(f"  [CHAT]     ✗ {sent_for_group}/{len(group_messages)} group messages sent")
                    seed_errors.append(f"group chat: sent {sent_for_group}/{len(group_messages)} messages")
            except XrpcError as e:
                print(f"  [CHAT]     Group chat failed: {e}")
                seed_errors.append(f"group chat: {e}")

    print(f"  [CHAT]   Total chat messages sent: {chat_count}/{expected_chat_count}")

    # ── Summary ──────────────────────────────────────────────────

    print()
    print("  [DONE] Seeding complete!")
    print()
    print("  Demo Accounts:")
    for acct in DEFAULT_ACCOUNTS:
        handle = acct["handle"]
        did = dids.get(handle, "?")
        print(f"  - {handle}  password={acct['password']}  did={did}")
    print()
    print(f"  DM conversations: {len(CONVERSATIONS)}")
    total_dm_msgs = sum(len(msgs) for msgs in CONVERSATIONS.values())
    print(f"  DM messages expected: {total_dm_msgs}")
    print(f"  Chat messages sent: {chat_count}/{expected_chat_count}")
    print(f"  Group chat: 1 (15 messages)")
    print()
    print(f"  PDS: {BASE_URL}")
    print(f"  Chat: {CHAT_URL}")
    print(f"  Admin UI: http://127.0.0.1:2590/admin")
    print()

    if seed_errors:
        print("  [FAILED] Seed completed with errors:", file=sys.stderr)
        for err in seed_errors:
            print(f"  - {err}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
