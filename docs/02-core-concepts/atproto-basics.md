# AT Protocol Basics

## Overview

The AT Protocol (Authenticated Transfer Protocol) is a decentralized social protocol that enables users to own their data and choose their service providers. This document covers the fundamental concepts you need to understand to implement a PDS.

## Decentralized Identifiers (DIDs)

### What is a DID?

A DID (Decentralized Identifier) is a globally unique identifier that doesn't depend on any central authority. DIDs are used to identify users, services, and other entities in the AT Protocol.

**Format:** `did:method:identifier`

**Examples:**
- `did:plc:bv6ggkxzsnbjrsxtsyrdypa` — User DID (PLC method)
- `did:web:pds.example.com` — Service DID (Web method)
- `did:key:z6MkhaXgBZDvotDkL5257faWxcqV6qGlN5aNiMEE5zcvKV1b` — Key DID

### DID Methods

The AT Protocol primarily uses two DID methods:

**PLC (Placeholder) Method:**
- Used for user identifiers
- Registered with a PLC directory service
- Allows key rotation and handle changes
- Example: `did:plc:bv6ggkxzsnbjrsxtsyrdypa`

**Web Method:**
- Used for service identifiers
- Resolved via HTTPS
- Example: `did:web:pds.example.com`

### DID Resolution

To resolve a DID to its document:

```objc
// In XrpcIdentityHelper.m
- (void)resolveDID:(NSString *)did 
         completion:(void (^)(NSDictionary *document, NSError *error))completion {
    if ([did hasPrefix:@"did:plc:"]) {
        // Query PLC directory
        [self resolvePLCDID:did completion:completion];
    } else if ([did hasPrefix:@"did:web:"]) {
        // Fetch from HTTPS endpoint
        [self resolveWebDID:did completion:completion];
    }
}
```

## Namespaced Identifiers (NSIDs)

### What is an NSID?

An NSID (Namespaced Identifier) is a hierarchical identifier for RPC methods and record types. It's similar to a reverse domain name.

**Format:** `authority.namespace.method`

**Examples:**
- `com.atproto.server.createAccount` — Create account method
- `com.atproto.repo.createRecord` — Create record method
- `app.bsky.feed.post` — Bluesky post record type
- `app.bsky.feed.like` — Bluesky like record type

### NSID Structure

```
com.atproto.server.createAccount
│   │       │      │
│   │       │      └─ Method name
│   │       └──────── Namespace
│   └──────────────── Service
└─────────────────── Authority (reverse domain)
```

### NSID Routing

The XRPC dispatcher uses NSIDs to route requests:

```objc
// In XrpcDispatcher.m
- (void)dispatchRequest:(XrpcRequest *)request 
               response:(XrpcResponse *)response {
    NSString *nsid = request.method;  // e.g., "com.atproto.repo.createRecord"
    
    XrpcMethodHandler handler = [self.registry handlerForNSID:nsid];
    if (handler) {
        handler(request, response);
    } else {
        response.error = @"MethodNotFound";
    }
}
```

## Repositories

### What is a Repository?

A repository is a versioned data store for a user. It contains:
- **Records** — User data (posts, profiles, likes, etc.)
- **Blobs** — Binary files (images, videos, etc.)
- **Commits** — Versioned snapshots of the repository state

Each user has exactly one repository, identified by their DID.

### Repository Structure

```
Repository (did:plc:user123)
├── Records
│   ├── app.bsky.feed.post/abc123
│   ├── app.bsky.feed.post/def456
│   ├── app.bsky.actor.profile/self
│   └── app.bsky.feed.like/ghi789
├── Blobs
│   ├── bafyreiabc123...
│   └── bafyredef456...
└── Commits
    ├── Commit 1 (root)
    ├── Commit 2
    └── Commit 3 (head)
```

### Record Keys (RKeys)

Records are identified by a collection name and a record key (rkey):

```
Collection: app.bsky.feed.post
RKey: abc123
Full URI: at://did:plc:user123/app.bsky.feed.post/abc123
```

RKeys are typically:
- TID (Timestamp Identifier) for time-ordered records
- Random strings for unordered records
- "self" for singleton records (like profile)

## Commits and Versioning

### What is a Commit?

A commit is a snapshot of the repository state at a point in time. It contains:
- **Root CID** — Hash of the repository's Merkle Search Tree
- **Timestamp** — When the commit was created
- **Signature** — Cryptographic signature by the user's key

### Commit Flow

```
User creates/updates record
    ↓
Record is inserted into repository
    ↓
Merkle Search Tree is updated
    ↓
New root CID is calculated
    ↓
Commit is created with new root CID
    ↓
Commit is signed with user's key
    ↓
Commit is broadcast to subscribers (firehose)
```

## Merkle Search Trees (MST)

### What is an MST?

A Merkle Search Tree is a data structure that:
- Stores all records in a repository
- Provides efficient lookups and range queries
- Generates a deterministic root hash (CID)
- Enables efficient synchronization

### MST Properties

- **Deterministic** — Same records always produce same root CID
- **Efficient** — O(log n) lookup time
- **Verifiable** — Root CID proves repository state
- **Syncable** — Differences can be computed efficiently

### MST in Code

```objc
// In PDSRepositoryService.m
- (void)updateMSTWithRecord:(NSDictionary *)record
                   collection:(NSString *)collection
                        rkey:(NSString *)rkey
                  completion:(void (^)(NSString *rootCID, NSError *error))completion {
    // 1. Get current MST
    MST *mst = [self getMSTForDID:self.did];
    
    // 2. Insert/update record in MST
    [mst setRecord:record forKey:[NSString stringWithFormat:@"%@/%@", collection, rkey]];
    
    // 3. Calculate new root CID
    NSString *rootCID = [mst calculateRootCID];
    
    // 4. Create commit
    [self createCommitWithRootCID:rootCID completion:completion];
}
```

## Content Addressing (CID)

### What is a CID?

A CID (Content Identifier) is a hash-based identifier for content. It's used to:
- Identify records and blobs
- Verify content integrity
- Enable content-addressed storage

**Format:** `bafy...` (base32-encoded multihash)

**Example:** `bafyreiabc123def456ghi789jkl012mno345pqr678stu901vwx234yz`

### CID Calculation

```objc
// In CID.m
- (NSString *)calculateCIDForData:(NSData *)data {
    // 1. Hash data with SHA-256
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    
    // 2. Create multihash (SHA-256 prefix + hash)
    NSMutableData *multihash = [NSMutableData data];
    [multihash appendBytes:"\x12\x20" length:2];  // SHA-256 prefix
    [multihash appendBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    
    // 3. Encode as base32
    NSString *cid = [self base32Encode:multihash];
    return [NSString stringWithFormat:@"bafy%@", cid];
}
```

## Lexicons

### What is a Lexicon?

A lexicon is a schema definition for:
- **Record types** — Structure of user data
- **RPC methods** — Parameters and return types
- **Tokens** — Authentication token formats

Lexicons are defined in JSON Schema format.

### Example Lexicon

```json
{
  "lexicon": 1,
  "id": "app.bsky.feed.post",
  "description": "A post record",
  "type": "record",
  "record": {
    "type": "object",
    "required": ["text", "createdAt"],
    "properties": {
      "text": {
        "type": "string",
        "maxLength": 300
      },
      "createdAt": {
        "type": "string",
        "format": "date-time"
      },
      "facets": {
        "type": "array",
        "items": { "$ref": "#/definitions/facet" }
      }
    }
  }
}
```

## Handles

### What is a Handle?

A handle is a human-readable identifier for a user, like a username. Examples:
- `alice.bsky.social`
- `bob.example.com`
- `charlie.localhost`

### Handle Resolution

Handles are resolved to DIDs through:
1. **DNS TXT records** — For custom domains
2. **PLC directory** — For `.bsky.social` handles

```objc
// In XrpcIdentityHelper.m
- (void)resolveHandle:(NSString *)handle 
            completion:(void (^)(NSString *did, NSError *error))completion {
    if ([handle hasSuffix:@".bsky.social"]) {
        // Query PLC directory
        [self resolveBskyHandle:handle completion:completion];
    } else {
        // Query DNS TXT record
        [self resolveDNSHandle:handle completion:completion];
    }
}
```

## Authentication

### Access Tokens

Access tokens are JWT tokens that:
- Identify the authenticated user (DID)
- Specify the scope of access
- Have an expiration time
- Are signed with the server's key

**Token Structure:**
```
Header: { "alg": "ES256", "typ": "JWT" }
Payload: { "iss": "did:web:pds.example.com", "sub": "did:plc:user123", "exp": 1234567890 }
Signature: <ECDSA signature>
```

### Refresh Tokens

Refresh tokens are long-lived tokens used to obtain new access tokens without re-authenticating.

## Next Steps

- **[CBOR and CAR](./cbor-and-car)** — Data serialization formats
- **[MST Trees](./mst-trees)** — Merkle Search Tree details
- **[Cryptography](./cryptography)** — Cryptographic operations
- **[Application Layer](../03-application-layer/pds-application)** — Service implementation
