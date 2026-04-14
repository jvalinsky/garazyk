import sqlite3
import json
import random
from datetime import datetime, timezone
import os

DB_PATH = 'data/pds.db'

if not os.path.exists(DB_PATH):
    print(f"Error: Database not found at {DB_PATH}")
    exit(1)

conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# Get Accounts
cursor.execute("SELECT did, handle FROM accounts")
accounts = cursor.fetchall()

if not accounts:
    print("No accounts found.")
    exit(0)

print(f"Found {len(accounts)} accounts. Seeding data...")

# Helper to generate TID (Timestamp Identifier - simplified)
def generate_tid():
    # Simple microsecond timestamp
    import time
    return str(int(time.time() * 1000000))

# Helper to generate CID (fake)
def generate_cid():
    # Need something that looks like a CID
    chars = 'abcdefghijklmnopqrstuvwxyz234567'
    return 'b' + ''.join(random.choice(chars) for _ in range(58))

def insert_record(did, collection, rkey, value):
    uri = f"at://{did}/{collection}/{rkey}"
    cid = generate_cid()
    created_at = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    
    value_json = json.dumps(value)
    
    try:
        cursor.execute(
            "INSERT INTO records (uri, did, collection, rkey, cid, created_at, value) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (uri, did, collection, rkey, cid, created_at, value_json)
        )
        return True
    except sqlite3.IntegrityError:
        print(f"Record exists: {uri}")
        return False

# Data Generators
def create_profile(did, handle):
    return {
        "$type": "app.bsky.actor.profile",
        "displayName": handle.split('.')[0].capitalize(),
        "description": f"Hello, I am {handle}! This is a seeded profile.",
        "avatar": None, # Complex to seed blob
        "banner": None
    }

def create_post(did, text):
    return {
        "$type": "app.bsky.feed.post",
        "text": text,
        "createdAt": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    }

def create_like(did, subject_uri, subject_cid):
    return {
        "$type": "app.bsky.feed.like",
        "subject": {
            "uri": subject_uri,
            "cid": subject_cid
        },
        "createdAt": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    }

def create_follow(did, subject_did):
    return {
        "$type": "app.bsky.graph.follow",
        "subject": subject_did,
        "createdAt": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    }

# Seeding Logic
for did, handle in accounts:
    print(f"Seeding {handle} ({did})...")
    
    # 1. Profile
    if insert_record(did, "app.bsky.actor.profile", "self", create_profile(did, handle)):
        print(f"  - Created Profile")
    
    # 2. Posts
    for i in range(5):
        tid = generate_tid()
        text = f"This is post #{i+1} from {handle}. #atproto #seeded"
        if insert_record(did, "app.bsky.feed.post", tid, create_post(did, text)):
            print(f"  - Created Post {tid}")

conn.commit()
print("Seeding complete.")

# Phase 2: Inter-actions (Likes/Follows)
# Need to fetch created posts to like them
print("Generating interactions...")

for did, handle in accounts:
    # Like random posts from others
    other_accounts = [a for a in accounts if a[0] != did]
    if not other_accounts: continue
    
    for _ in range(3):
        target_did, _ = random.choice(other_accounts)
        # Get random post
        cursor.execute("SELECT uri, cid FROM records WHERE did = ? AND collection = 'app.bsky.feed.post' ORDER BY RANDOM() LIMIT 1", (target_did,))
        post = cursor.fetchone()
        if post:
            uri, cid = post
            tid = generate_tid()
            if insert_record(did, "app.bsky.feed.like", tid, create_like(did, uri, cid)):
                print(f"  - {handle} liked post by {target_did}")

    # Follow others
    for target_did, target_handle in other_accounts[:3]:
        tid = generate_tid()
        if insert_record(did, "app.bsky.graph.follow", tid, create_follow(did, target_did)):
            print(f"  - {handle} followed {target_handle}")

conn.commit()
conn.close()
print("Done!")
