# Reference Comparison: Garazyk vs Bluesky PDS

Compare Garazyk's federation behavior against the Bluesky PDS reference (`bsky.social`) and the AT Protocol specification.

## Table of Contents

- [Account Creation](#account-creation)
- [Handle Resolution](#handle-resolution)
- [DID Document Shape](#did-document-shape)
- [Cross-PDS Record Retrieval](#cross-pds-record-retrieval)
- [Relay Firehose](#relay-firehose)
- [AppView Endpoints](#appview-endpoints)
- [Spec Links](#spec-links)

## Account Creation

### Garazyk

```bash
curl -s -X POST http://127.0.0.1:2583/xrpc/com.atproto.account.create \
  -H "Content-Type: application/json" \
  -d '{"handle":"alice.test","email":"alice@test.com","password":"test1234"}'
```

Expected response:
```json
{
  "did": "did:plc:...",
  "handle": "alice.test",
  "accessJwt": "...",
  "refreshJwt": "..."
}
```

### Bluesky PDS Reference

```bash
curl -s -X POST https://bsky.social/xrpc/com.atproto.account.create \
  -H "Content-Type: application/json" \
  -d '{"handle":"example.bsky.social","email":"test@example.com","password":"..."}'
```

Same response shape. Note: `bsky.social` requires invite codes.

### Spec

- [com.atproto.account.create](https://atproto.com/specs/account#create-account)

## Handle Resolution

### Garazyk

```bash
curl -s "http://127.0.0.1:2587/xrpc/com.atproto.identity.resolveHandle?handle=alice.test"
```

Expected:
```json
{"did": "did:plc:..."}
```

### Bluesky PDS Reference

```bash
curl -s "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=atproto.com"
```

Same shape. Production handles use DNS-based verification (`_atproto` TXT record) or HTTP well-known (`/.well-known/atproto-did`).

### Spec

- [com.atproto.identity.resolveHandle](https://atproto.com/specs/identity#handle-resolution)

## DID Document Shape

### Garazyk (PLC)

```bash
curl -s http://127.0.0.1:2582/{DID}
```

Expected PLC DID document:
```json
{
  "@context": ["https://www.w3.org/ns/did/v1"],
  "id": "did:plc:...",
  "alsoKnownAs": ["at://alice.test"],
  "verificationMethod": [...],
  "rotationKeys": [...],
  "service": [
    {
      "id": "#atproto_pds",
      "type": "AtprotoPersonalDataServer",
      "serviceEndpoint": "http://127.0.0.1:2583"
    }
  ]
}
```

### Bluesky PLC

```bash
curl -s https://plc.directory/{DID}
```

Same shape. Production endpoints use `https://` URLs.

### Key Differences

| Field | Garazyk (local) | Bluesky (production) |
|-------|-----------------|---------------------|
| `serviceEndpoint` | `http://127.0.0.1:2583` | `https://bsky.social` |
| `alsoKnownAs` | `at://alice.test` | `at://alice.bsky.social` |
| Signing keys | Test keys | Production rotation keys |

### Spec

- [DID PLC Method](https://web.plc.directory/spec/v0.1/did-plc)
- [AT Protocol Identity](https://atproto.com/specs/identity)

## Cross-PDS Record Retrieval

### Garazyk

```bash
# From PDS2, fetch a record hosted on PDS1
curl -s "http://127.0.0.1:2587/xrpc/com.atproto.repo.getRecord?repo={ALICE_DID}&collection=app.bsky.feed.post&rkey={RKEY}"
```

Expected:
```json
{
  "uri": "at://{ALICE_DID}/app.bsky.feed.post/{RKEY}",
  "cid": "...",
  "value": {
    "$type": "app.bsky.feed.post",
    "text": "Hello from PDS 1!",
    "createdAt": "..."
  }
}
```

### Bluesky PDS Reference

```bash
# Any PDS can fetch records from any other PDS
curl -s "https://bsky.social/xrpc/com.atproto.repo.getRecord?repo={DID}&collection=app.bsky.feed.post&rkey={RKEY}"
```

Same response shape. The reference PDS fetches the repo from the origin PDS using `com.atproto.sync.getRepo`.

### Spec

- [com.atproto.repo.getRecord](https://atproto.com/specs/repository#get-record)
- [com.atproto.sync.getRepo](https://atproto.com/specs/sync#get-repo)

## Relay Firehose

### Garazyk

```bash
# Subscribe to firehose (WebSocket)
curl -s -N "http://127.0.0.1:2584/xrpc/com.atproto.sync.subscribeRepos"
```

Binary frame format: length-prefixed CBOR messages. Each message has:
- `type`: `#commit`, `#handle`, `#identity`, `#account`, etc.
- `repo`: DID of the originating account
- `ops`: array of repo operations (create, update, delete)
- `seq`: monotonically increasing sequence number

### Bluesky Relay Reference

```bash
wscat -c "wss://bsky.network/xrpc/com.atproto.sync.subscribeRepos"
```

Same frame format. Production relay handles thousands of events per second.

### Key Verification Points

1. Events from both PDS1 and PDS2 appear in the relay firehose
2. Sequence numbers are monotonically increasing
3. `#commit` events contain correct repo operations
4. No duplicate events for the same repo/seq

### Spec

- [com.atproto.sync.subscribeRepos](https://atproto.com/specs/sync#subscribe-repos)
- [Event Stream](https://atproto.com/specs/event-stream)

## AppView Endpoints

### Garazyk

```bash
# Profile
curl -s "http://127.0.0.1:3200/xrpc/app.bsky.actor.getProfile?actor={DID}" \
  -H "Authorization: Bearer {JWT}"

# Author feed
curl -s "http://127.0.0.1:3200/xrpc/app.bsky.feed.getAuthorFeed?actor={DID}" \
  -H "Authorization: Bearer {JWT}"
```

### Bluesky AppView Reference

```bash
curl -s "https://api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=atproto.com" \
  -H "Authorization: Bearer {JWT}"

curl -s "https://api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor=atproto.com" \
  -H "Authorization: Bearer {JWT}"
```

### Key Verification Points

1. Cross-PDS profiles are indexed (not just local PDS accounts)
2. Follow counts reflect cross-PDS follows
3. Feed items include posts from both PDS instances
4. Profile `did` matches the PLC DID document

### Spec

- [app.bsky.actor.getProfile](https://atproto.com/specs/bsky#get-profile)
- [app.bsky.feed.getAuthorFeed](https://atproto.com/specs/bsky#get-author-feed)

## Spec Links

| Topic | URL |
|-------|-----|
| AT Protocol Spec | https://atproto.com/specs/atp |
| Identity | https://atproto.com/specs/identity |
| Repository | https://atproto.com/specs/repository |
| Sync | https://atproto.com/specs/sync |
| Event Stream | https://atproto.com/specs/event-stream |
| DID PLC Method | https://web.plc.directory/spec/v0.1/did-plc |
| Handle Resolution | https://atproto.com/specs/handle |
| XRPC | https://atproto.com/specs/xrpc |
| Lexicon | https://atproto.com/specs/lexicon |
| Bluesky PDS Reference | https://github.com/bluesky-social/atproto |
