# AT Protocol PDS Architecture and Specifications

## 1. What is atproto and How PDS Fits Into the Ecosystem

### AT Protocol Overview

The **Authenticated Transfer Protocol** (atproto) is a decentralized protocol for large-scale social web applications, developed by Bluesky Social. It enables federated social networking with self-authenticating data structures.

**Key Design Principles:**

- **Self-authenticating data**: All user data is signed by the authoring users
- **Account portability**: Users can migrate between PDS providers without server involvement
- **Federated architecture**: Data stored on host servers, not peer-to-peer
- **Schema-driven interoperability**: Lexicon schemas unify API names and behaviors across servers

### Network Architecture

The AT Protocol has a federated network with three core services:

1. **Personal Data Servers (PDS)**: Host user data, manage identity, orchestrate requests
2. **Relays**: Collect data updates from many servers into a single firehose
3. **App Views**: Provide aggregated application data for the entire network

**Account Identity Components:**
- **DID (Decentralized Identifier)**: Permanent, globally unique identifier
- **Handle**: Configurable human-readable domain name
- **Signing key**: Validates the user's data repository
- **Rotation keys**: Assert changes to the DID Document

## 2. PDS API Endpoints and Protocols

### XRPC (HTTP API)

The HTTP API uses **XRPC** (Cross-server Remote Procedure Call) with common conventions:

**Endpoint Structure:**
```
/xrpc/{NSID}
```

**Request Types:**
- **Query** (HTTP GET): Cacheable, no state mutation
- **Procedure** (HTTP POST): Not cacheable, may mutate state

**Common Endpoints:**

```json
// com.atproto namespace (core protocols)
com.atproto.server.createSession
com.atproto.server.refreshSession
com.atproto.repo.createRecord
com.atproto.repo.getRecord
com.atproto.repo.deleteRecord
com.atproto.repo.listRecords
com.atproto.repo.uploadBlob
com.atproto.sync.subscribeRepos
com.atproto.identity.resolveHandle

// app.bsky namespace (social app features)
app.bsky.feed.post
app.bsky.feed.like
app.bsky.feed.repost
app.bsky.graph.follow
app.bsky.actor.profile
```

### Blob Handling

Blobs are handled separately from records:
1. **Upload**: `com.atproto.repo.uploadBlob` returns CID and metadata
2. **Constraints**: MIME type and file size validated during record creation
3. **Retrieval**: `com.atproto.sync.getBlob` for account-specific blobs

### HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 400 | Bad Request |
| 401 | Unauthorized |
| 403 | Forbidden |
| 404 | Not Found |
| 429 | Rate Limited |
| 500 | Internal Server Error |
| 501 | Not Implemented |

## 3. Authentication and Authorization Mechanisms

### OAuth 2.1 Profile

atproto uses a specific OAuth profile with mandatory security features:

**Core Requirements:**
- Authorization Code grant type only
- PKCE (Proof Key for Code Exchange - RFC 7636)
- DPoP (Demonstration of Proof-of-Possession - RFC 9449)
- Pushed Authorization Requests (PAR)

**Token Types:**
- **Access tokens**: Short-lived (< 30 minutes), authorize PDS requests
- **Refresh tokens**: Longer-lived, request new access tokens

### Legacy Authentication (Deprecated)

```bash
# Session creation
POST /xrpc/com.atproto.server.createSession
{
  "identifier": "handle or email",
  "password": "password"
}
```

### Inter-Service Authentication

JWT tokens signed by account's atproto signing key:

```javascript
// JWT Header
{
  "alg": "ES256K",  // or ES256 for p256 keys
  "typ": "JWT"
}
```

## 4. Data Storage Requirements

### Self-Hosting Requirements

**Minimum Server Specifications:**
- **OS**: Ubuntu 22.04 (recommended)
- **Memory**: 1 GB RAM
- **CPU**: 1 core
- **Storage**: 20 GB SSD
- **Network**: Public IPv4, DNS name

### Database Considerations

The official PDS uses SQLite for development but can use PostgreSQL for production:

**Key Storage Areas:**
1. **Repository data**: Content-addressed blocks (CAR files)
2. **Account metadata**: User accounts, handles, blobs
3. **Event stream**: Sequence numbers for backfill
4. **Blobs**: Large binary files (images, media)

## 5. Repository Structure and Operations

### Repository Data Structure (v3)

Repositories are **Merkle Search Trees (MST)** - content-addressed data structures:

```
┌────────────────┐
│     Commit     │  (Signed Root - contains signature)
└───────┬────────┘
        ↓
┌────────────────┐
│   Tree Nodes   │  (MST internal nodes)
└───────┬────────┘
        ↓
┌────────────────┐
│     Record     │  (Leaf nodes - actual data)
└────────────────┘
```

### Commit Object Structure

```json
{
  "did": "did:plc:44ybard66vv44zksje25o7dz",
  "version": 3,
  "data": {"/": "bafyre..."},  // CID link to MST root
  "rev": "3jwdwj2ctlk26",      // TID revision string
  "prev": null,                 // Previous commit CID
  "sig": {"/": {"/": 136}}     // Signature bytes
}
```

### Record Operations

**Create Record:**
```json
PUT /xrpc/com.atproto.repo.createRecord
{
  "repo": "did:plc:...",
  "collection": "app.bsky.feed.post",
  "rkey": "3jwdwj2ctlk26",
  "record": {
    "text": "Hello, atproto!",
    "createdAt": "2024-01-01T00:00:00Z"
  }
}
```

## 6. Event Stream and Firehose

### WebSocket Connection

```javascript
// Connect to repo subscription
const ws = new WebSocket(
  'wss://pds.example.com/xrpc/com.atproto.sync.subscribeRepos?cursor=0'
);
```

### Frame Format (v0)

Each WebSocket frame contains two concatenated DAG-CBOR objects:

**Header:**
```json
{
  "op": 1,           // 1 = message, -1 = error
  "t": "#commit"    // Message type (fragment)
}
```

## 7. Existing Implementations

### Go Implementations

#### **Indigo** (Bluesky Official)
GitHub: `bluesky-social/indigo` (1.3k stars)

**Key Packages:**
```go
// Repository handling
github.com/bluesky-social/indigo/atproto/repo
github.com/bluesky-social/indigo/atproto/repo/mst

// Identity
github.com/bluesky-social/indigo/atproto/identity

// OAuth
github.com/bluesky-social/indigo/atproto/auth/oauth

// Lexicon validation
github.com/bluesky-social/indigo/atproto/lexicon
```

### Python Implementations

#### **millipds** (Most Complete)
GitHub: `DavidBuchanan314/millipds` (149 stars)

**Features:**
- From-scratch PDS implementation
- Supports federation with network
- Uses `atmst` for MST operations
- Uses `dag-cbrrr` for DAG-CBOR

## Key Security Considerations

1. **SSRF Protection**: Validate all URLs fetched from external parties
2. **Token Binding**: DPoP binds tokens to specific client instances
3. **Key Rotation**: Support for rotating signing keys without account migration
4. **Input Validation**: Strict validation of DAG-CBOR and CBOR data
5. **Rate Limiting**: Protect against abuse with connection and message limits

## Related Documentation

### Architecture Documents
- [README.md](README) - Architecture documentation index
- [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS) - Deep code analysis and component details
- [atproto_data_models.md](atproto_data_models) - DID, MST, and repository structure
- [XRPC_PROTOCOL_REFERENCE.md](XRPC_PROTOCOL_REFERENCE) - XRPC method quick reference

### Diagram Documents
- [DIAGRAMS_MERMAID.md](DIAGRAMS_MERMAID) - OAuth2 and record lifecycle diagrams
- [ARCHITECTURE_DIAGRAMS.md](ARCHITECTURE_DIAGRAMS) - System architecture diagrams

### Related Tests
- [../tests/00-identity-auth/oauth.md](../tests/00-identity-auth/oauth) - OAuth and DPoP test documentation
- [../tests/01-repository/mst.md](../tests/01-repository/mst) - MST test documentation
- [../tests/02-network/xrpc.md](../tests/02-network/xrpc) - XRPC test documentation

### Security Documentation
- [../security/](../security/) - Security audit and hardening guides
