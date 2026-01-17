import requests
import subprocess
import time
import sys
import os
import uuid
import random

# Configuration from env
BASE_URL = os.environ.get("PDS_URL", "http://localhost:2583")
DATA_DIR = os.environ.get("PDS_DATA_DIR", "./data")
BIN_PATH = os.environ.get("PDS_BIN", "./build/bin/september")

def run_cli_command(args):
    """Runs the september CLI command."""
    # Global options must come BEFORE the command (args[0])
    # Pass --config /tmp/missing.json to avoid loading ./config.json which overrides data-dir
    cmd = [BIN_PATH, "--verbose", "--data-dir", DATA_DIR, "--config", "/tmp/missing_config_to_force_args.json"] + args
    print(f"Running CLI: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.stdout:
        print(f"CLI Stdout:")
        print(result.stdout)
    if result.stderr:
        print(f"CLI Stderr:")
        print(result.stderr)
    if result.returncode != 0:
        print(f"Command failed: {' '.join(cmd)}")
        return False
    return True

def create_account(handle, email, password):
    print(f"Creating account {handle}...")
    run_cli_command(["account", "create", "--email", email, "--handle", handle, "--password", password])

def login(handle, password):
    print(f"Logging in as {handle}...")
    try:
        resp = requests.post(f"{BASE_URL}/xrpc/com.atproto.server.createSession", json={
            "identifier": handle,
            "password": password
        })
        if resp.status_code != 200:
            print(f"Login failed: {resp.text}")
            return None
        return resp.json()
    except Exception as e:
        print(f"Login exception: {e}")
        return None

def create_record(session, collection, record):
    print(f"Creating record in {collection} for {session['handle']}...")
    try:
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
    except Exception as e:
        print(f"Create record exception: {e}")
        return None

def main():
    # waiting for server to be ready
    print(f"Waiting for server at {BASE_URL} to be ready...")
    for i in range(30):
        try:
            requests.get(f"{BASE_URL}/_health")
            break
        except requests.exceptions.ConnectionError:
            time.sleep(1)
            print(".", end="", flush=True)
    print(" Server is up!")
    
    # Generate random suffix
    suffix = str(random.randint(1000, 9999))

    # 1. Alice
    alice_handle = f"alice{suffix}.test"
    alice_email = f"alice{suffix}@test.com"
    alice_pass = f"hunter{suffix}"
    
    create_account(alice_handle, alice_email, alice_pass)
    alice_session = login(alice_handle, alice_pass)
    
    if alice_session:
        # Profile
        create_record(alice_session, "app.bsky.actor.profile", {
            "$type": "app.bsky.actor.profile",
            "displayName": f"Alice {suffix}",
            "description": "I am looking for the white rabbit."
        })
        # Posts
        for i in range(3):
            create_record(alice_session, "app.bsky.feed.post", {
                "$type": "app.bsky.feed.post",
                "text": f"Alice's post number {i+1} (Run {suffix})",
                "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            })

    # 2. Bob
    bob_handle = f"bob{suffix}.test"
    bob_email = f"bob{suffix}@test.com"
    bob_pass = f"hunter{suffix}"

    create_account(bob_handle, bob_email, bob_pass)
    bob_session = login(bob_handle, bob_pass)
    
    if bob_session:
        # Profile
        create_record(bob_session, "app.bsky.actor.profile", {
            "$type": "app.bsky.actor.profile",
            "displayName": f"Bob {suffix}",
            "description": "I build things."
        })
        # Posts
        create_record(bob_session, "app.bsky.feed.post", {
            "$type": "app.bsky.feed.post",
            "text": f"Hello world from Bob! (Run {suffix})",
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        })

if __name__ == "__main__":
    main()
