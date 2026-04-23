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
BIN_PATH = os.environ.get("PDS_BIN", "./build/bin/kaszlak")


def run_cli_command(args):
    """Runs the kaszlak CLI command."""
    # Correct order: kaszlak <command> [global-options] [subcommand-options]
    # args[0] is the top-level command (e.g., "account")
    # rest of args is subcommands and options
    top_command = args[0]
    sub_args = args[1:]

    cmd = (
        [BIN_PATH, top_command]
        + sub_args
        + [
            "--data-dir",
            DATA_DIR,
            "--verbose",
            "--config",
            "/tmp/missing_config_to_force_args.json",
        ]
    )
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
    print(f"Creating account {handle} via XRPC...")
    try:
        resp = requests.post(
            f"{BASE_URL}/xrpc/com.atproto.server.createAccount",
            json={"email": email, "handle": handle, "password": password},
        )
        if resp.status_code == 200:
            print(f"Account {handle} created successfully via XRPC.")
            return True
        else:
            print(
                f"Create account via XRPC failed (status {resp.status_code}): {resp.text}"
            )
    except Exception as e:
        print(f"Create account via XRPC exception: {e}")

    print(f"Falling back to CLI for account {handle}...")
    return run_cli_command(
        [
            "account",
            "create",
            "--email",
            email,
            "--handle",
            handle,
            "--password",
            password,
        ]
    )


def login(handle, password):
    print(f"Logging in as {handle}...")
    try:
        resp = requests.post(
            f"{BASE_URL}/xrpc/com.atproto.server.createSession",
            json={"identifier": handle, "password": password},
        )
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
            json={"repo": session["did"], "collection": collection, "record": record},
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

    # Use fixed handles for demo predictability
    alice_handle = "alice.test"
    alice_email = "alice@test.com"
    alice_pass = "hunter2"

    create_account(alice_handle, alice_email, alice_pass)
    alice_session = login(alice_handle, alice_pass)

    if alice_session:
        # Profile
        create_record(
            alice_session,
            "app.bsky.actor.profile",
            {
                "$type": "app.bsky.actor.profile",
                "displayName": "Alice",
                "description": "I am looking for the white rabbit.",
            },
        )
        # Posts
        for i in range(3):
            create_record(
                alice_session,
                "app.bsky.feed.post",
                {
                    "$type": "app.bsky.feed.post",
                    "text": f"Alice's post number {i + 1}",
                    "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                },
            )

    # 2. Bob
    bob_handle = "bob.test"
    bob_email = "bob@test.com"
    bob_pass = "hunter2"

    create_account(bob_handle, bob_email, bob_pass)
    bob_session = login(bob_handle, bob_pass)

    if bob_session:
        # Profile
        create_record(
            bob_session,
            "app.bsky.actor.profile",
            {
                "$type": "app.bsky.actor.profile",
                "displayName": "Bob",
                "description": "I build things.",
            },
        )
        # Posts
        create_record(
            bob_session,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "Hello world from Bob!",
                "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            },
        )


if __name__ == "__main__":
    main()
