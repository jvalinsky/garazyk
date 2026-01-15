import requests
import time
import sys

BASE_URL = "http://localhost:2583"

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
        print(f"Login error: {e}")
        return None

def create_record(session, collection, record):
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
        print(f"Create record error: {e}")
        return None

def main():
    print("Generating activity...")
    
    # Login Alice
    alice = login("alice.test", "hunter2")
    if alice:
        print("Generating 50 posts for Alice...")
        for i in range(50):
            create_record(alice, "app.bsky.feed.post", {
                "$type": "app.bsky.feed.post",
                "text": f"Mushroom hunting log #{i+1}: Found some fascinating fungi today!",
                "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            })
            time.sleep(0.2) # Avoid rate limits
            if i % 10 == 0:
                print(f"  Created {i+1} posts...")
    
    # Login Bob
    print("Waiting before logging in Bob...")
    time.sleep(2)
    bob = login("bob.test", "hunter2")
    if bob:
        print("Generating 50 posts for Bob...")
        for i in range(50):
            create_record(bob, "app.bsky.feed.post", {
                "$type": "app.bsky.feed.post",
                "text": f"Builder's log entry #{i+1}: Progress is steady.",
                "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            })
            time.sleep(0.2) # Avoid rate limits
            if i % 10 == 0:
                print(f"  Created {i+1} posts...")

if __name__ == "__main__":
    main()
