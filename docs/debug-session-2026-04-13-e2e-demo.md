# E2E Demo Debug Session - April 13, 2026

## Background

Goal was to build a full E2E demo of the ATProto suite:
- PLC (campagnola) on port 2582
- PDS (kaszlak) on port 2583  
- Relay (zuk) on port 2584
- AppView (syrena) on port 3200

Create 3 accounts (alice, bob, carol) with various records (posts, follows, likes, reposts, blocks).

---

## What Worked

### 1. Docker Compose Setup
```
cd docker/local-network && docker compose up -d
```

**Services Started:**
- local-plc:2582 ✅
- local-pds:2583 ✅
- local-relay:2584 ✅
- local-appview:3200 ✅

### 2. Key Path Workaround
PDS rotation key needed a mounted volume to write:
```yaml
volumes:
  - /tmp/pds_keys:/var/lib/atprotopds/keys
```

Also added to compose environment:
```yaml
- PDS_DATA_DIR=/var/lib/atprotopds
- PDS_PLC_KEYS_DIR=/var/lib/atprotopds/keys
- HOME=/var/lib/atprotopds
```

### 3. Account Creation
```bash
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{
    "handle": "alice.test",
    "email": "alice@test.com", 
    "password": "password123"
  }'
```

**Created accounts:**
- alice.test -> did:plc:3d3ebd3lqebz4hb26txmyl2t
- bob.test -> did:plc:zid2p3aus2rv453yfnrgl4od
- carol.test -> did:plc:c7qqm26lqxfgz5ncwcimipzy

### 4. Profile Creation (WORKS)
```bash
curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "repo": "did:plc:3d3ebd3lqebz4hb26txmyl2t",
    "collection": "app.bsky.actor.profile",
    "rkey": "self",
    "record": {
      "$type": "app.bsky.actor.profile",
      "displayName": "Alice 🐱",
      "description": "Hello from my PDS!"
    }
  }'
# Result: at://did:plc:.../app.bsky.actor.profile/self ✓
```

### 5. requestCrawl (WORKS)
```bash
curl -X POST http://localhost:2583/xrpc/com.atproto.sync.requestCrawl \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"hostname":"local-pds"}'
# Result: {}
```

---

## Issues Encountered

### Issue 1: Local PLC Rejects Operations (400)

**Error:**
```
PLC registration failed with status 400
```

**Logs:**
```
POST /did:plc:enfkfvcvgs3rwpscctmf7rin, status 400
[DEBUG] [Core] [PLCMetrics.m:78] PLC error recorded
```

**Root Cause:** Unknown - PLCAuditor validation failing but no specific error message.

**Temporary Workaround:** Use `skip_plc_operations: true` in config (defeats the purpose for full E2E).

---

### Issue 2: Post Creation Fails (500 InternalServerError)

**Error:**
```json
{
  "error": "InternalServerError",
  "message": "Unhandled exception"
}
```

**Request:**
```bash
curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "repo": "did:plc:3d3ebd3lqebz4hb26txmyl2t",
    "collection": "app.bsky.feed.post",
    "record": {
      "$type": "app.bsky.feed.post",
      "text": "Hello world! First post from my new PDS! 🚀",
      "createdAt": "2026-04-14T00:20:00.000Z"
    }
  }'
```

**Note:** First got "Missing required field 'createdAt'" error - fixed by adding it, but then hit unhandled exception.

**Profile works but posts fail** - what's different?

---

### Issue 3: requestCrawl "Missing hostname"

**Initial wrong call:**
```bash
curl -X POST http://localhost:2583/xrpc/com.atproto.sync.requestCrawl \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"host":"localhost"}'
# Error: Missing hostname
```

**Fix:** from lexicon (`requestCrawl.json`):
```json
{
  "required": ["hostname"],
  "hostname": {
    "type": "string",
    "description": "Hostname of the current service (eg, PDS) that is requesting to be crawled."
  }
}
```

**Correct call:**
```bash
curl -X POST http://localhost:2583/xrpc/com.atproto.sync.requestCrawl \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"hostname":"local-pds"}'
# Result: {} ✓
```

**Lesson:** Error messages ARE telling you exactly what's wrong - read them!

---

## API Lessons Learned

### 1. Lexicons are the Source of Truth
Always check `/Resources/lexicons/com/atproto/sync/requestCrawl.json` for:
- Required fields
- Input schema
- Description

### 2. Error Messages are Specific
- "Missing hostname" → pass `hostname`, not `host`
- "Missing required field 'createdAt'" → add it to record
- "Content-Length required" → pass `{}` not empty body

### 3. Profile vs Post Difference
- `app.bsky.actor.profile` works with createRecord
- `app.bsky.feed.post` fails with 500

---

## Relay Status After requestCrawl
```json
{
  "status": "healthy", 
  "downstreamConnections": 0,
  "currentSequence": 0,
  "upstreamConnections": 0
}
```

No upstream connections yet because no records were successfully created as posts.

---

## Next Steps to Debug

### 1. Post Creation (500 error)
**Debug approach:**
- Enable debug logging in PDS repo handler
- Try minimal post: just `{"text": "test"}` without createdAt
- Check createRecord handler code path
- Verify app.bsky.feed.post lexicon requirements

### 2. Local PLC (400 error)
**Debug approach:**
- Add logging in PLCAuditor to see which specific validation fails
- Compare working vs non-working operation structure
- Check signature/timestamp requirements

### 3. Once Fixed - Create Full E2E Data

**Alice:**
- Profile ✓
- Posts (3)
- Follow bob.test
- Like bob's post
- Repost bob's post

**Bob:**
- Profile
- Posts (3)
- Like alice's first post

**Carol:**
- Profile  
- Post
- Follow bob.test
- Like bob's post
- Block bob.test

Then verify in AppView:
- /xrpc/app.bsky.feed.getTimeline
- /admin/backfill/status

---

## Files Modified During Session

1. `docker/local-network/docker-compose.yml` - Added keys volume mount
2. `docker/local-network/pds-config.json` - debug skip_plc_operations (temporary)
3. `Garazyk/Sources/PLC/PLCRotationKeyManager.m` - Added HOME env fallback

---

**Session ended:** April 13, 2026 ~22:30 UTC