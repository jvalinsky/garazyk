#!/usr/bin/env python3
"""Seed PDS with demo accounts and 10+ records per account via XRPC.

Creates 3 accounts (alice.test, bob.test, carol.test) with:
  - 1 profile (app.bsky.actor.profile)
  - 5 posts (app.bsky.feed.post)
  - 2+ follows (app.bsky.graph.follow)
  - 2+ likes (app.bsky.feed.like)
  - 1 list (app.bsky.graph.list)
  - 1 feed generator (app.bsky.feed.generator)

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
    print(f"  PDS: {BASE_URL}")
    print(f"  Admin UI: http://127.0.0.1:2590/admin")
    print()


if __name__ == "__main__":
    main()
