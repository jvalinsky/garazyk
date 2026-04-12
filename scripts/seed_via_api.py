import requests
import subprocess
import time
import sys
import os

BASE_URL = "http://localhost:2583"
ADMIN_KEY = "admin" # Update if auth is required for account creation, but we use CLI

def run_cli_command(args):
    """Runs the kaszlak CLI command."""
    cmd = ["./build/bin/kaszlak", "-v"] + args
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.stdout:
        print(f"CLI Stdout ({' '.join(args)}):")
        print(result.stdout)
    if result.stderr:
        print(f"CLI Stderr ({' '.join(args)}):")
        print(result.stderr)
    if result.returncode != 0:
        print(f"Command failed: {' '.join(cmd)}")
        return False
    return True

def create_account(handle, email, password):
    print(f"Creating account {handle}...")
    # Check if account exists via CLI list (optional, but good for idempotency)
    # For now, just try to create and ignore failure
    run_cli_command(["account", "create", "--email", email, "--handle", handle, "--password", password])

def login(handle, password):
    print(f"Logging in as {handle}...")
    resp = requests.post(f"{BASE_URL}/xrpc/com.atproto.server.createSession", json={
        "identifier": handle,
        "password": password
    })
    if resp.status_code != 200:
        print(f"Login failed: {resp.text}")
        return None
    return resp.json()

def create_record(session, collection, record):
    print(f"Creating record in {collection} for {session['handle']}...")
    resp = requests.post(
        f"{BASE_URL}/xrpc/com.atproto.repo.createRecord",
        headers={"Authorization": f"Bearer {session['accessJwt']}"},
        json={
            "repo": session["did"],
            "collection": collection,
            "record": record
        }
    )
    if resp.status_code != 200:
        print(f"Create record failed: {resp.text}")
        return None
    return resp.json()

def main():
    # waiting for server to be ready
    print("Waiting for server to be ready...")
    for i in range(10):
        try:
            requests.get(f"{BASE_URL}/explore")
            break
        except requests.exceptions.ConnectionError:
            time.sleep(1)
            print(".", end="", flush=True)
    print(" Server is up!")

    # 1. Alice
    create_account("alice.test", "alice@test.com", "hunter2")
    alice_session = login("alice.test", "hunter2")
    
    if alice_session:
        # Profile
        create_record(alice_session, "app.bsky.actor.profile", {
            "$type": "app.bsky.actor.profile",
            "displayName": "Alice",
            "description": "I am looking for the white rabbit."
        })
        # Posts
        for i in range(3):
            create_record(alice_session, "app.bsky.feed.post", {
                "$type": "app.bsky.feed.post",
                "text": f"Alice's post number {i+1}",
                "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            })

    # 2. Bob
    create_account("bob.test", "bob@test.com", "hunter2")
    bob_session = login("bob.test", "hunter2")
    
    if bob_session:
        # Profile
        create_record(bob_session, "app.bsky.actor.profile", {
            "$type": "app.bsky.actor.profile",
            "displayName": "Bob",
            "description": "I build things."
        })
        # Posts
        create_record(bob_session, "app.bsky.feed.post", {
            "$type": "app.bsky.feed.post",
            "text": "Hello world from Bob!",
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        })
        
        # Bob likes Alice's post (finding uri is hard without listing, skipping for now or listing first)

if __name__ == "__main__":
    main()
