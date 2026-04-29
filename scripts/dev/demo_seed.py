#!/usr/bin/env python3
"""Seed a minimal PDS demo dataset through XRPC.

This is the smallest developer-facing seeder: it creates two deterministic
accounts, writes profile records, and adds a few posts. It is useful for quick
manual testing because the credentials and handles stay stable across runs.

Usage:
    python3 scripts/dev/demo_seed.py
    PDS_URL=http://localhost:2583 python3 scripts/dev/demo_seed.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# Add scripts/ to sys.path so this developer script can import the shared
# helpers when executed directly from the checkout.
_scripts_dir = str(Path(__file__).resolve().parent.parent)
if _scripts_dir not in sys.path:
    sys.path.insert(0, _scripts_dir)

from lib.atproto import (
    XrpcClient,
    XrpcError,
    create_account_or_login,
    now_iso,
    wait_for_server,
)

# ── Configuration ──────────────────────────────────────────────────────────

BASE_URL = os.environ.get("PDS_URL", "http://localhost:2583").rstrip("/")
DATA_DIR = os.environ.get("PDS_DATA_DIR", "./data")
BIN_PATH = os.environ.get("PDS_BIN", "./build/bin/kaszlak")

DEMO_ACCOUNTS = [
    {
        "handle": "alice.test",
        "email": "alice@test.com",
        "password": "hunter2",
        "display_name": "Alice",
        "description": "I am looking for the white rabbit.",
        "posts": ["Alice's post number 1", "Alice's post number 2", "Alice's post number 3"],
    },
    {
        "handle": "bob.test",
        "email": "bob@test.com",
        "password": "hunter2",
        "display_name": "Bob",
        "description": "I build things.",
        "posts": ["Hello world from Bob!"],
    },
]


# ── Main ──────────────────────────────────────────────────────────────────

def main() -> None:
    """Create or reuse demo accounts and write their profile/post records."""
    print(f"Waiting for server at {BASE_URL} to be ready...")
    wait_for_server(BASE_URL, timeout=30)
    print("Server is up!")

    client = XrpcClient(BASE_URL)
    now = now_iso()

    for acct in DEMO_ACCOUNTS:
        handle = acct["handle"]
        email = acct["email"]
        password = acct["password"]

        # Use create-or-login so repeated demo runs can reuse an existing local
        # account instead of failing before record seeding begins.
        try:
            session = create_account_or_login(client, handle, email, password)
        except XrpcError as e:
            print(f"Account {handle} failed: {e}")
            continue

        did = session["did"]
        jwt = session["accessJwt"]
        print(f"Account {handle} ready ({did})")

        # Profiles make the demo accounts visible in actor/profile endpoints.
        try:
            client.create_record(did, "app.bsky.actor.profile", {
                "$type": "app.bsky.actor.profile",
                "displayName": acct["display_name"],
                "description": acct["description"],
            }, jwt)
            print(f"  Profile created for {acct['display_name']}")
        except XrpcError as e:
            print(f"  Profile failed: {e}")

        # Posts provide visible feed data for smoke tests and manual UI checks.
        for i, text in enumerate(acct["posts"]):
            try:
                client.create_record(did, "app.bsky.feed.post", {
                    "$type": "app.bsky.feed.post",
                    "text": text,
                    "createdAt": now,
                }, jwt)
                print(f"  Post #{i+1}: {text[:50]}")
            except XrpcError as e:
                print(f"  Post #{i+1} failed: {e}")

    print("\nDone!")


if __name__ == "__main__":
    main()
