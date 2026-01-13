# PDSls.dev Compatibility Analysis

Analysis of API compatibility with [pdsls.dev](https://pdsls.dev) PDS viewer application.

## Summary

| Status | Count |
|--------|-------|
| ✅ Implemented | 16 |
| ⚠️ Partial | 1 |

## Required APIs

### PDS View (`/pds.tsx`)

| Endpoint | Status | Notes |
|----------|--------|-------|
| `_health` | ✅ | Returns version info |
| `com.atproto.server.describeServer` | ✅ | Returns server metadata |
| `com.atproto.sync.listRepos` | ✅ | Lists all repos on PDS |

### Record View (`/record.tsx`)

| Endpoint | Status | Notes |
|----------|--------|-------|
| `com.atproto.repo.getRecord` | ✅ | Get record by AT URI |
| `com.atproto.sync.getRecord` | ✅ | Returns record as CAR bytes for integrity verification |

### Blob View (`/blob.tsx`)

| Endpoint | Status | Notes |
|----------|--------|-------|
| `com.atproto.sync.listBlobs` | ✅ | Lists blob CIDs for a DID |
| `com.atproto.sync.getBlob` | ✅ | Returns blob data by CID |

### Firehose View (`/stream/index.tsx`)

| Endpoint | Status | Notes |
|----------|--------|-------|
| `com.atproto.sync.subscribeRepos` | ⚠️ | WebSocket implemented on port 8081, may need path routing |

### Authentication (`/auth/*`)

| Endpoint | Status | Notes |
|----------|--------|-------|
| `com.atproto.server.getSession` | ✅ | Returns current authenticated session |
| OAuth metadata | ✅ | `/.well-known/oauth-authorization-server` |

### Record Operations (Create/Edit/Delete)

| Endpoint | Status | Notes |
|----------|--------|-------|
| `com.atproto.repo.createRecord` | ✅ | Create new record |
| `com.atproto.repo.deleteRecord` | ✅ | Delete record |
| `com.atproto.repo.applyWrites` | ✅ | Batch operations |
| `com.atproto.repo.uploadBlob` | ✅ | Upload blob |
| `com.atproto.repo.describeRepo` | ✅ | Repo metadata |
| `com.atproto.repo.listRecords` | ✅ | List records in collection |

### Profile/Actor

| Endpoint | Status | Notes |
|----------|--------|-------|
| `app.bsky.actor.getProfile` | ✅ | Get actor profile |
| `app.bsky.actor.searchActorsTypeahead` | ❌ | Not used by pdsls directly |

### Labels

| Endpoint | Status | Notes |
|----------|--------|-------|
| `com.atproto.label.queryLabels` | ⚠️ | Implemented as `getLabels` |

## Implementation Notes

### `com.atproto.server.getSession`

Implemented. Returns current session info for authenticated user.

**Response:**
```json
{
  "handle": "user.bsky.social",
  "did": "did:plc:xxx",
  "email": "user@example.com",
  "emailConfirmed": true,
  "active": true
}
```

### `com.atproto.sync.getRecord`

Implemented. Returns a single record as a CAR file (bytes).

**Parameters:**
- `did` - Repository DID
- `collection` - Record collection NSID  
- `rkey` - Record key

**Response:** `application/vnd.ipld.car` (binary CAR data)

**Note:** Current implementation returns a minimal CAR structure. Full MST proof path
is not yet included, which means `@atcute/repo.verifyRecord()` may fail verification.
The record data is still accessible via `com.atproto.repo.getRecord`.

## Firehose Notes

pdsls connects to firehose via:
```
wss://<pds>/xrpc/com.atproto.sync.subscribeRepos
```

Our implementation runs on port 8081 separately. May need:
1. WebSocket path routing on main HTTP server, OR
2. Proxy configuration to route WebSocket traffic

## Remaining Work

1. **Priority 1**: Full MST proof in `com.atproto.sync.getRecord` for verification
2. **Priority 2**: Route WebSocket on `/xrpc/com.atproto.sync.subscribeRepos`
3. **Priority 3**: Implement `app.bsky.actor.searchActorsTypeahead` (optional)
