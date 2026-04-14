import requests
import subprocess
import time
import os
import random
import json

BASE_URL = os.environ.get("PDS_URL", "http://localhost:2583")
BIN_PATH = os.environ.get("PDS_BIN", "./build/bin/kaszlak")
DATA_DIR = os.environ.get("PDS_DATA_DIR", "./simulation_data")

def run_cli(args, is_admin=False):
    cmd_group = "admin" if is_admin else "account"
    cmd = [BIN_PATH, "--data-dir", DATA_DIR, cmd_group] + args
    print(f"Running CLI: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"CLI error: {result.stderr}")
        return False
    return True

def run_oauth_cli(args):
    cmd = [BIN_PATH, "--data-dir", DATA_DIR, "oauth"] + args
    print(f"Running OAuth CLI: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"OAuth CLI error: {result.stderr}")
        return False
    return True

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

def create_report(session, subject_uri, subject_cid, reason):
    try:
        resp = requests.post(
            f"{BASE_URL}/xrpc/com.atproto.moderation.createReport",
            headers={"Authorization": f"Bearer {session['accessJwt']}"},
            json={
                "reasonType": "com.atproto.moderation.defs#reasonSpam", # Generic reason for demo
                "subject": {
                    "$type": "com.atproto.repo.strongRef",
                    "uri": subject_uri,
                    "cid": subject_cid
                },
                "reason": reason
            }
        )
        if resp.status_code != 200:
            print(f"Report failed: {resp.text}")
            return None
        return resp.json()
    except Exception as e:
        print(f"Report exception: {e}")
        return None

def main():
    suffix = str(random.randint(100, 999))
    
    # 0. Register OAuth test client (required for OAuth flows)
    print("\n=== Registering OAuth test client ===")
    redirect_uris = [
        f"{BASE_URL}/?oauth_callback=1",
        f"{BASE_URL}/oauth-demo/callback",
    ]
    run_oauth_cli(["client", "register", 
                   "--client-id", "test-client", 
                   "--redirect-uri", redirect_uris[0],
                   "--redirect-uri", redirect_uris[1]])
    
    users = {
        "admin": {"handle": f"admin{suffix}.test", "email": f"admin{suffix}@test.com", "pass": "adminpass123", "is_admin": True, "persona": "Server Admin"},
        "nature": {"handle": f"nature{suffix}.test", "email": f"nature{suffix}@test.com", "pass": "naturepass123", "is_admin": False, "persona": "Nature Lover"},
        "tech": {"handle": f"tech{suffix}.test", "email": f"tech{suffix}@test.com", "pass": "techpass123", "is_admin": False, "persona": "Tech Nerd"},
        "foodie": {"handle": f"foodie{suffix}.test", "email": f"foodie{suffix}@test.com", "pass": "foodiepass123", "is_admin": False, "persona": "Food Critic"},
        "troll": {"handle": f"troll{suffix}.test", "email": f"troll{suffix}@test.com", "pass": "trollpass123", "is_admin": False, "persona": "Internet Troll"}
    }

    # 1. Create accounts
    for key, u in users.items():
        if u["is_admin"]:
            run_cli(["create", "--email", u["email"], "--handle", u["handle"], "--password", u["pass"]], is_admin=True)
        else:
            run_cli(["create", "--email", u["email"], "--handle", u["handle"], "--password", u["pass"]], is_admin=False)
    
    # 2. Login and store sessions
    for key, u in users.items():
        session = login(u["handle"], u["pass"])
        if session:
            u["session"] = session
            # Set Profile
            create_record(session, "app.bsky.actor.profile", {
                "$type": "app.bsky.actor.profile",
                "displayName": f"{u['persona']} {suffix}",
                "description": f"Official account for {u['persona']}"
            })
        else:
            print(f"FAILED to start session for {u['handle']}")

    sessions = [u["session"] for u in users.values() if "session" in u]
    if len(sessions) < 5:
        print("Not all sessions were established. Aborting social simulation.")
        return

    # 3. Perform 10 actions each
    actions = {
        "nature": [
            "Just saw a beautiful sunrise! #nature",
            "Hiking the Pacific Crest Trail this weekend.",
            "Native plants are so important for biodiversity.",
            "Follow nature lovers!",
            "Look at this mushroom I found 🍄",
            "Peace and quiet is underrated.",
            "Waterfalls are nature's music.",
            "Save the bees!",
            "Morning dew on spider webs is magic.",
            "Check out my new hiking boots!"
        ],
        "tech": [
            "AI is moving so fast, it's hard to keep up.",
            "Just pushed a new PR to open-atproto!",
            "Objective-C is still the king of dynamic runtimes.",
            "Secp256k1 curves are math at its best.",
            "Rust or Zig? Discuss.",
            "PDS self-hosting is the future of the web.",
            "DPoP nonces are great for security.",
            "Is it weird that I like compiler warnings?",
            "Building a new ATProto client in my spare time.",
            "Hello world! My first post on this new PDS."
        ],
        "foodie": [
            "Baking sourdough is a science and an art.",
            "Pizza night! What are your favorite toppings?",
            "Farm-to-table is the only way to eat.",
            "Found this amazing hidden ramen spot.",
            "Is it still a sandwich if it's open-faced?",
            "Cooking for friends is my love language.",
            "Fresh herbs make everything better.",
            "Espresso shot at 2 PM is essential.",
            "Trying out a new vegan lasagna recipe tonight.",
            "Chocolate cake solves most problems."
        ],
        "troll": [
            "This place is empty. Boring!",
            "Why is everyone posting about plants and pizza?",
            "Tech nerds are the worst.",
            "Server lag is real. Fix it!",
            "Nobody cares about your hike, Alice.",
            "I'm only here to see the fire.",
            "Is this thing even on?",
            "Deleting my account in 3... 2... 1...",
            "Trolling is a lost art form.",
            "The admin stinks!!! this server is slow and the mods are losers." # THE RUDE POST
        ],
        "admin": [
            "Welcome to the new PDS instance!",
            "Server maintenance scheduled for Sunday at 2 AM.",
            "Please follow the community guidelines.",
            "New feature: Persistent Admin DIDs now active.",
            "Supporting the growth of the ATProto ecosystem.",
            "Security update: PBKDF2 hashing now default.",
            "If you experience issues, please report them.",
            "Great to see so much activity already!",
            "Respect each other in the comments.",
            "Proud to be running this piece of infrastructure."
        ]
    }

    # Execute posts
    posts_data = {}
    for key, posts in actions.items():
        u = users[key]
        posts_data[key] = []
        for p in posts:
            res = create_record(u["session"], "app.bsky.feed.post", {
                "$type": "app.bsky.feed.post",
                "text": p,
                "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            })
            if res:
                posts_data[key].append({"uri": res["uri"], "cid": res["cid"]})
            time.sleep(0.1) # Small delay

    # Misc actions: Likes and Follows
    # Alice (nature) follows Bob (tech)
    create_record(users["nature"]["session"], "app.bsky.graph.follow", {
        "$type": "app.bsky.graph.follow",
        "subject": users["tech"]["session"]["did"],
        "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    })
    
    # Bob (tech) likes Alice's first post
    if posts_data["nature"]:
        create_record(users["tech"]["session"], "app.bsky.feed.like", {
            "$type": "app.bsky.feed.like",
            "subject": {"uri": posts_data["nature"][0]["uri"], "cid": posts_data["nature"][0]["cid"]},
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        })

    # Admin likes the Nature and Foodie posts
    if posts_data["nature"]:
        create_record(users["admin"]["session"], "app.bsky.feed.like", {
            "$type": "app.bsky.feed.like",
            "subject": {"uri": posts_data["nature"][1]["uri"], "cid": posts_data["nature"][1]["cid"]},
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        })

    # 4. Moderation Event
    # Flag the troll's rude post
    rude_post = posts_data["troll"][-1]
    print(f"Admin flagging rude post: {rude_post['uri']}")
    report_res = create_report(users["admin"]["session"], rude_post["uri"], rude_post["cid"], "Targeted harassment of the administrator.")
    
    if report_res:
        print("Report created successfully!")
        print(json.dumps(report_res, indent=2))
    
    print("\n--- Simulation Complete ---")
    print(f"Created 5 accounts: {', '.join([u['handle'] for u in users.values()])}")
    print("Performed 50 posts and multiple social interactions.")
    print("Admin successfully flagged the troll.")

if __name__ == "__main__":
    main()
