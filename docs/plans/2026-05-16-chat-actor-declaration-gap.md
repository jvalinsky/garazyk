# Plan: Address chat.bsky.actor.declaration and Chat Service Gaps

## Problem Statement

When a bsky client tries to use chat on Garazyk, it needs to:
1. Read/write `chat.bsky.actor.declaration` records (the `allowIncoming` preference: "all", "none", or "following")
2. Call `chat.bsky.convo.*` and `chat.bsky.group.*` methods for messaging

Currently, `chat.bsky.actor.declaration` returns `MethodNotFound` on `chat.garazyk.xyz`. This is because:

- `chat.bsky.actor.declaration` is a **record** type (not a query/procedure), so it has no dedicated XRPC endpoint
- It's accessed via `com.atproto.repo.getRecord` / `com.atproto.repo.createRecord` with `collection=chat.bsky.actor.declaration&rkey=self`
- The PDS (`garazyk.xyz`) has repo handlers and correctly returns `RecordNotFound` (no declaration created yet)
- The chat service (`chat.garazyk.xyz`) does NOT have repo handlers — it only has `chat.bsky.*` handlers

## Architecture Analysis

### How the Bluesky Reference Handles This

In the Bluesky reference architecture:
- The **PDS** handles all `com.atproto.repo.*` operations (including `chat.bsky.actor.declaration` records)
- The **Chat service** handles `chat.bsky.convo.*` and `chat.bsky.group.*` methods
- The PDS proxies `chat.bsky.*` methods to the Chat service
- The client talks to the PDS for everything; the PDS routes internally

The `chat.bsky.authFullChatClient` permission-set confirms this split:
```json
{
  "permissions": [
    { "type": "permission", "resource": "rpc", "lxm": ["chat.bsky.convo.*", ...] },
    { "type": "permission", "resource": "repo", "action": ["create","update","delete"], "collection": ["chat.bsky.actor.declaration"] }
  ]
}
```

The declaration is a **repo** permission, not an **rpc** permission.

### Current Garazyk Architecture

```
bsky client
    │
    ├── com.atproto.repo.getRecord(collection=chat.bsky.actor.declaration)
    │   → PDS (garazyk.xyz) → repo handlers → RecordNotFound ✓
    │
    ├── chat.bsky.convo.listConvos
    │   → PDS (garazyk.xyz) → PDS_CHAT_URL → chat.garazyk.xyz → AuthRequired ✓
    │
    └── chat.bsky.actor.declaration (directly on chat.garazyk.xyz)
        → MethodNotFound ✗ (no repo handlers on chat service)
```

The problem only manifests if a bsky client sends the declaration request directly to `chat.garazyk.xyz` instead of to the PDS. This shouldn't happen in normal operation, but some clients might if they discover the chat service URL independently.

### Real Issue: What's Actually Missing

The `MethodNotFound` for `chat.bsky.actor.declaration` on the chat service is a **symptom**, not the root cause. The real gaps are:

1. **No declaration record exists** — `com.atproto.repo.getRecord` returns `RecordNotFound` on the PDS because no user has created a declaration yet
2. **No convenience endpoint** — The Bluesky reference chat service provides a convenience `chat.bsky.actor.declaration` query endpoint that reads the record from the user's repo and returns it, so clients don't need to call `com.atproto.repo.getRecord` separately
3. **Chat service has no repo access** — The chat service can't read the user's repo to check `allowIncoming` before allowing a conversation to be created

## Plan

### Step 1: Add `chat.bsky.actor.declaration` convenience query endpoint

**What:** Register a `chat.bsky.actor.declaration` query handler on the chat service that reads the declaration record from the PDS's repo and returns it.

**Why:** The Bluesky reference chat service provides this endpoint. Some bsky clients call it directly on the chat service rather than using `com.atproto.repo.getRecord` on the PDS.

**How:**

In `XrpcChatBskyActorPack.m`, add:

```objc
[dispatcher registerMethod:@"chat.bsky.actor.declaration"
                   handler:^(HttpRequest *request, HttpResponse *response) {
    XrpcHandlerContext *context =
        [[XrpcHandlerContext alloc] initWithRequest:request
                                          response:response
                                          services:resolvedServices];
    if (![context requireAuthentication]) {
        return;
    }

    // Read the declaration record from the PDS repo
    // at://<did>/chat.bsky.actor.declaration/self
    NSString *actorDid = context.authenticatedDid;
    NSString *pdsUrl = resolvedServices.configuration.pdsUrl
        ?: @"http://127.0.0.1:2583";

    // Fetch the record via com.atproto.repo.getRecord
    NSString *getUrl = [NSString stringWithFormat:
        @"%@/xrpc/com.atproto.repo.getRecord?collection=chat.bsky.actor.declaration&rkey=self&repo=%@",
        pdsUrl, [actorDid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];

    // Use ATProtoSafeHTTPClient to fetch
    // ... (HTTP GET to PDS, return the record or default)

    // Default if no record exists: allowIncoming = "all"
    response.statusCode = 200;
    [response setJsonBody:@{
        @"uri": [NSString stringWithFormat:@"at://%@/chat.bsky.actor.declaration/self", actorDid],
        @"cid": @"",
        @"value": @{@"allowIncoming": @"all", @"$type": @"chat.bsky.actor.declaration"}
    }];
}];
```

**Effort:** Small (1-2 hours). The handler is a simple PDS repo read + default fallback.

**Dependencies:** ChatConfiguration needs `pdsUrl` to be set (already done via `PDS_URL` env var).

### Step 2: Enforce `allowIncoming` in conversation creation

**What:** When `chat.bsky.convo.getConvoForMembers` or `chat.bsky.convo.sendMessage` is called, check the target user's `allowIncoming` declaration before allowing the conversation.

**Why:** This is the core access control for Bluesky chat. Without it, anyone can message anyone regardless of their preference.

**How:**

In `ChatService`, add a method:

```objc
- (NSString *)allowIncomingForDid:(NSString *)did error:(NSError **)error;
```

This method reads the declaration record from the PDS repo (via `com.atproto.repo.getRecord`) and returns the `allowIncoming` value ("all", "none", "following"). If no record exists, default to "all".

Then in `XrpcChatBskyConvoPack.m`, before creating a conversation:

```objc
// Check if target allows incoming messages
NSString *allowIncoming = [chatService allowIncomingForDid:targetDid error:nil];
if ([allowIncoming isEqualToString:@"none"]) {
    response.statusCode = 403;
    [response setJsonBody:@{@"error": @"Blocked", @"message": @"Recipient does not allow incoming messages"}];
    return;
}
if ([allowIncoming isEqualToString:@"following"]) {
    // Check if sender follows target (requires PDS graph query)
    // ...
}
```

**Effort:** Medium (4-8 hours). Requires PDS repo read integration + graph query for "following" check.

**Dependencies:** Step 1 (the convenience endpoint establishes the pattern for reading declarations from the PDS).

### Step 3: Add `chat.bsky.convo.getConvoForMembers` declaration check

**What:** The `getConvoForMembers` endpoint (used to initiate a conversation) should check `allowIncoming` before returning the conversation.

**Why:** This is the primary entry point for starting a new conversation in the bsky chat client.

**How:** Same pattern as Step 2, but applied specifically to `getConvoForMembers`.

**Effort:** Small (1-2 hours, included in Step 2).

### Step 4: Wire ChatService to PDS for declaration reads

**What:** Add a PDS HTTP client to ChatService so it can read repo records.

**Why:** Currently ChatService only has database access. It needs to call the PDS's `com.atproto.repo.getRecord` endpoint to read declaration records.

**How:**

Add to `ChatConfiguration`:
```objc
@property (nonatomic, copy) NSString *pdsUrl;  // Already exists
```

Add to `ChatService`:
```objc
@property (nonatomic, weak) NSString *pdsUrl;

- (nullable NSDictionary *)getDeclarationForDid:(NSString *)did error:(NSError **)error {
    // HTTP GET to PDS: /xrpc/com.atproto.repo.getRecord?collection=chat.bsky.actor.declaration&rkey=self&repo=<did>
    // Return the record value, or nil with default "all"
}
```

**Effort:** Small (2-3 hours). Uses existing `ATProtoSafeHTTPClient`.

### Step 5: Handle `chat.bsky.actor.declaration` writes on the PDS

**What:** Ensure the PDS's `com.atproto.repo.createRecord` handler accepts `chat.bsky.actor.declaration` as a valid collection.

**Why:** When a user changes their chat preferences (e.g., from "all" to "following"), the client calls `com.atproto.repo.createRecord` or `com.atproto.repo.putRecord` on the PDS with `collection=chat.bsky.actor.declaration`.

**How:**

Check if the PDS's repo handler validates collection names. If it does, add `chat.bsky.actor.declaration` to the allowed collections list. If it doesn't (accepts any collection), no changes needed.

**Current status:** The PDS already returns `RecordNotFound` (not `InvalidCollection`), which suggests it accepts the collection name but no record exists yet. Need to verify by creating a test record.

**Effort:** Small (1-2 hours for verification + any needed changes).

## Dependency Graph

```
Step 4 (ChatService → PDS HTTP client)
  │
  ├── Step 1 (convenience declaration query endpoint)
  │
  └── Step 2 (enforce allowIncoming in conversation creation)
        │
        └── Step 3 (getConvoForMembers declaration check)

Step 5 (PDS repo write support) — independent, can be done in parallel
```

## Priority

- **Step 1** is P0 — without it, bsky clients that call `chat.bsky.actor.declaration` directly on the chat service get `MethodNotFound`
- **Step 5** is P0 — without it, users can't set their chat preferences at all
- **Step 4** is P1 — needed for Step 1 and Step 2
- **Step 2/3** is P1 — access control, but not blocking for basic chat functionality

## Testing

After implementation:

```bash
# Step 1: Convenience endpoint
curl -s https://chat.garazyk.xyz/xrpc/chat.bsky.actor.declaration -H "Authorization: Bearer <jwt>"
# Expected: {"uri":"at://<did>/chat.bsky.actor.declaration/self","value":{"allowIncoming":"all"}}

# Step 5: Repo write
curl -s -X POST https://garazyk.xyz/xrpc/com.atproto.repo.createRecord \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"collection":"chat.bsky.actor.declaration","rkey":"self","record":{"$type":"chat.bsky.actor.declaration","allowIncoming":"following"}}'
# Expected: {"uri":"at://<did>/chat.bsky.actor.declaration/self","cid":"..."}

# Step 2: Access control
# After setting allowIncoming to "none" for a user, attempting to message them should return 403
```

## Open Questions

- **Caching:** Should the chat service cache declaration reads? The PDS repo is local (same machine), so latency is low. But for high-traffic scenarios, a short TTL cache (e.g., 60s) would reduce PDS load.
- **"Following" check:** How does the chat service determine if the sender follows the target? It needs to query the PDS's graph (app.bsky.graph.getFollows or similar). This requires additional PDS integration.
- **WebSocket events:** When a user updates their declaration, should the chat service be notified? Currently there's no event bus between the PDS and chat service. This could be addressed via the firehose or a direct notification.
