# AT Protocol Basics

## Why This Matters

Traditional social networks trap you in walled gardens. Your identity, your data, your social graph—all locked to a single company's servers. If they ban you, change their policies, or shut down, you lose everything.

The AT Protocol fundamentally changes this power dynamic:

- **You own your identity** — Your DID is cryptographically yours, not controlled by any company
- **You own your data** — Your posts, likes, and follows live in your repository, which you can move between servers
- **You choose your provider** — Don't like your PDS? Move to another without losing your identity or followers
- **You control your experience** — Choose your own moderation, algorithms, and clients

This isn't just philosophical—it's practical. The AT Protocol makes "credible exit" possible: the ability to leave a service provider without losing your digital life.

## Overview

The AT Protocol (Authenticated Transfer Protocol) is a decentralized social protocol that enables users to own their data and choose their service providers. This document covers the fundamental concepts you need to understand to implement a PDS.

### Real-World Impact

Consider Alice, who has 10,000 followers on a traditional social network. If the platform bans her account (rightly or wrongly), she loses:
- Her username and identity
- Her 10,000 followers
- Years of posts and content
- Her social graph and connections

With AT Protocol, Alice's identity (`did:plc:alice123`) is cryptographically hers. Her followers follow her DID, not her server. Her posts are in her repository, which she controls. If her PDS operator misbehaves, she can:
1. Export her repository (a single CAR file)
2. Import it to a new PDS
3. Update her DID document to point to the new PDS
4. Her followers automatically discover her new location

She loses nothing. This is the power of decentralization.

## Decentralized Identifiers (DIDs)

### What is a DID?

A DID (Decentralized Identifier) is a globally unique identifier that doesn't depend on any central authority. DIDs are used to identify users, services, and other entities in the AT Protocol.

**Format:** `did:method:identifier`

**Examples:**
- `did:plc:bv6ggkxzsnbjrsxtsyrdypa` — User DID (PLC method)
- `did:web:pds.example.com` — Service DID (Web method)
- `did:key:z6MkhaXgBZDvotDkL5257faWxcqV6qGlN5aNiMEE5zcvKV1b` — Key DID

### Why DIDs Instead of Usernames?

Traditional usernames are controlled by the platform. Twitter owns `@alice`, Facebook owns `alice@facebook.com`. If the platform bans you or shuts down, your identity disappears.

DIDs flip this model:
- **Cryptographically owned** — Your DID is derived from your keys. Only you can prove ownership.
- **Globally unique** — No central registry needed. DIDs are mathematically guaranteed to be unique.
- **Portable** — Your DID works across all AT Protocol services. Move between PDSs without changing your identity.
- **Verifiable** — Anyone can verify you control your DID by checking your cryptographic signatures.

**Real-world analogy:** A username is like a hotel room number—it only makes sense within that hotel, and you lose it when you check out. A DID is like your passport number—it's yours forever, recognized globally, and proves your identity anywhere.

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

### Why Two DID Methods?

The choice of DID method reflects different trust models and use cases:

**PLC for users:** Users need the ability to rotate keys (in case of compromise) and change handles (for rebranding). The PLC directory provides a mutable registry that supports these operations while maintaining an immutable audit log. Users trust the PLC directory to store their DID operations, but they can verify the entire operation chain themselves.

**Web for services:** Services typically have stable DNS names and don't need key rotation as frequently. The `did:web` method leverages existing DNS infrastructure, making it simpler to set up and verify. A service's DID document is simply hosted at `https://pds.example.com/.well-known/did.json`.

**Design trade-off:** PLC requires trusting a directory service (though you can run your own), while `did:web` requires trusting DNS and HTTPS infrastructure. The protocol uses PLC for users because the benefits (key rotation, handle changes) outweigh the trust requirements.

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

### Why NSIDs?

NSIDs solve the namespace collision problem in a decentralized network. Without namespaces, how do you prevent conflicts when multiple developers create a "post" record type?

**Reverse domain naming:** By using reverse domain names (like Java packages), NSIDs ensure global uniqueness. If you own `example.com`, you control the `com.example.*` namespace. No central authority needed.

**Hierarchical organization:** The dot-separated structure provides natural organization:
- `com.atproto.*` — Core AT Protocol methods
- `app.bsky.*` — Bluesky application methods
- `com.example.*` — Your custom methods

**Discoverability:** NSIDs make it easy to discover related methods. All feed-related methods are under `app.bsky.feed.*`, all server methods under `com.atproto.server.*`.

**Real-world analogy:** NSIDs are like URLs—they provide a globally unique, hierarchical naming system without requiring a central registry.

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

### Why Repositories?

Repositories are the key to data portability. Instead of your data being scattered across database tables controlled by a platform, your data is packaged in a self-contained, portable repository.

**Versioning:** Every change creates a new commit, providing a complete history. This enables:
- **Audit trails** — See exactly when and how data changed
- **Rollback** — Revert to previous states if needed
- **Synchronization** — Efficiently sync changes between servers

**Content addressing:** Records are identified by their cryptographic hash (CID), not by database IDs. This means:
- **Deduplication** — Identical content has the same CID, stored once
- **Verification** — Anyone can verify content hasn't been tampered with
- **Portability** — CIDs work across all servers, no ID translation needed

**Real-world analogy:** A repository is like a Git repository for your social media data. Just as you can clone a Git repo to any server, you can export your AT Protocol repository and import it anywhere.

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

### Why Commits?

Commits provide several critical guarantees:

**Atomicity:** A commit represents a complete, consistent state. Either all changes in a commit are applied, or none are. No partial updates.

**Authenticity:** Every commit is signed with the user's private key. This proves:
- The user authorized the changes
- The commit hasn't been tampered with
- The commit came from the claimed DID

**Ordering:** Commits form a chain, establishing a clear chronological order. This prevents:
- Ambiguity about which state is current
- Reordering attacks (replaying old commits)
- Concurrent update conflicts

**Synchronization:** The root CID in each commit enables efficient sync. If two servers have the same root CID, their repositories are identical. If they differ, the servers can walk the MST to identify exactly which records changed.

**Real-world analogy:** Commits are like blockchain blocks—each one references the previous one, creating an immutable, verifiable history. But unlike blockchains, each user has their own independent commit chain, enabling massive parallelism.

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

### Why MSTs?

MSTs solve a fundamental problem in decentralized systems: how do you efficiently synchronize data between servers while maintaining cryptographic proof of integrity?

**Traditional approaches fail:**
- **Timestamp-based sync** — Clocks drift, timestamps can be forged
- **Version numbers** — Require coordination, don't prove integrity
- **Full comparison** — Comparing every record is too slow at scale

**MSTs provide:**
- **Deterministic hashing** — Same records always produce the same root CID, regardless of insertion order
- **Efficient diff** — Compare root CIDs; if they match, repositories are identical. If they differ, walk the tree to find exactly which records changed
- **Cryptographic proof** — The root CID proves the entire repository state. Tampering with any record changes the root CID
- **Ordered access** — Records are stored in lexicographic order, enabling efficient range queries

**Real-world impact:** When Alice migrates from Server A to Server B, Server B can verify her entire repository (potentially millions of records) by comparing a single 32-byte hash. If the hashes match, the migration is verified. If they differ, the MST structure identifies exactly which records need to be transferred—often just a handful of recent posts.

### MST Properties

- **Deterministic** — Same records always produce same root CID
- **Efficient** — O(log n) lookup time
- **Verifiable** — Root CID proves repository state
- **Syncable** — Differences can be computed efficiently

### Design Trade-offs

**Why not a simple Merkle tree?** Traditional Merkle trees (like in Git) require records to be in a specific order. If you insert records in different orders, you get different root hashes. MSTs solve this by using lexicographic ordering—records are always sorted by key, ensuring deterministic hashing regardless of insertion order.

**Why not a hash table?** Hash tables provide O(1) lookups but don't support:
- Range queries (finding all posts in a date range)
- Ordered iteration (displaying posts chronologically)
- Efficient diff computation (identifying changes)

MSTs provide the best of both worlds: efficient lookups with the verifiability of Merkle trees and the ordering of search trees.

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

### Why Content Addressing?

Content addressing is a paradigm shift from location-based addressing:

**Location-based (traditional):**
- "Get the file at `/users/alice/posts/123`"
- Problem: What if the file moves? What if it's modified? What if the server lies?

**Content-based (CID):**
- "Get the content with hash `bafyreiabc...`"
- Benefit: The hash IS the identifier. Content can be anywhere, and you can verify it's correct by recomputing the hash.

**Real-world benefits:**

**Deduplication:** If Alice and Bob both post the same image, it has the same CID. The PDS stores it once, saving storage and bandwidth.

**Verification:** When you download a blob with CID `bafyreiabc...`, you can verify it's correct by hashing it. If the hash doesn't match, the content was corrupted or tampered with.

**Caching:** CDNs and relays can cache content by CID. Since CIDs are immutable (same content always has the same CID), cached content never becomes stale.

**Portability:** CIDs work across all servers. When Alice migrates her repository, her post references (which are CIDs) don't need to change—they work on the new server automatically.

**Real-world analogy:** A CID is like a fingerprint. Just as a fingerprint uniquely identifies a person regardless of where they are, a CID uniquely identifies content regardless of where it's stored.

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

### Why Lexicons?

In a decentralized network with multiple implementations, how do you ensure interoperability? Lexicons provide machine-readable schemas that define exactly what data looks like.

**Without lexicons:**
- Each implementation might interpret "post" differently
- Clients wouldn't know what fields are required
- Validation would be inconsistent across servers
- Breaking changes would go undetected

**With lexicons:**
- **Interoperability** — All implementations agree on data structure
- **Validation** — Servers can validate records against schemas
- **Documentation** — Schemas serve as authoritative documentation
- **Evolution** — Schema versioning enables backward-compatible changes

**Real-world impact:** When a client creates a post, it knows exactly what fields are required (text, createdAt) and what's optional (facets, embed). The PDS validates the post against the lexicon before accepting it. If the client sends invalid data, the PDS rejects it with a clear error message.

**Design philosophy:** Lexicons are intentionally simple—they're JSON Schema, a widely-understood standard. This makes it easy to generate code, validate data, and build tools across different programming languages.

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

### Why Handles AND DIDs?

This might seem redundant—why have both handles and DIDs? The answer lies in the different properties each provides:

**DIDs (permanent identity):**
- Cryptographically owned
- Never change
- Hard to remember (`did:plc:z72i7hdynmk6r22z27h6tvur`)
- Perfect for machines

**Handles (human-friendly aliases):**
- Easy to remember and share
- Can change (rebrand without losing identity)
- Can be custom domains (personal branding)
- Perfect for humans

**The relationship:** Handles are pointers to DIDs. When you follow `@alice.bsky.social`, you're actually following her DID. If Alice changes her handle to `@alice.example.com`, you're still following her—the DID never changed.

**Real-world analogy:** A DID is like your Social Security number (permanent, unique, hard to remember). A handle is like your name (changeable, memorable, human-friendly). You need both.

### Custom Domain Handles

One of the most powerful features of AT Protocol is custom domain handles. Instead of `alice.bsky.social`, you can use `alice.com` as your handle.

**Why this matters:**
- **Brand identity** — Your social handle matches your website
- **Verification** — Your domain proves your identity (no blue checkmark needed)
- **Independence** — Not tied to any platform's namespace

**How it works:** You configure a DNS TXT record pointing to your DID. When someone looks up `alice.com`, the protocol checks DNS, finds your DID, and resolves your profile. You control the DNS, so you control the verification.

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

### Why JWT Tokens?

JWT (JSON Web Tokens) are the standard for stateless authentication in distributed systems. Here's why they're perfect for AT Protocol:

**Stateless verification:** The PDS doesn't need to store session data. The token itself contains all the information needed to verify it. This enables:
- **Horizontal scaling** — Any PDS instance can verify any token
- **No database lookups** — Verification is purely cryptographic
- **Cross-server auth** — Tokens can be verified by relays and other services

**Cryptographic security:** Tokens are signed with the PDS's private key. This proves:
- The token was issued by the claimed PDS
- The token hasn't been tampered with
- The token is authentic

**Expiration:** Short-lived access tokens (typically 1 hour) limit the damage if a token is stolen. Even if an attacker intercepts a token, it becomes useless after expiration.

### Refresh Tokens

Refresh tokens are long-lived tokens used to obtain new access tokens without re-authenticating.

**Why separate tokens?**

**Security through separation:**
- **Access tokens** — Short-lived (1 hour), sent with every request, higher risk of interception
- **Refresh tokens** — Long-lived (90 days), sent rarely (only to refresh), lower risk of interception

If an access token is stolen, it's only useful for an hour. If a refresh token is stolen, it can be revoked.

**User experience:** Users don't need to log in every hour. The client automatically uses the refresh token to get new access tokens in the background.

**Design trade-off:** This adds complexity (two token types instead of one), but the security benefits outweigh the cost. The pattern is standard in OAuth 2.0 and widely understood.

## Next Steps

- **[CBOR and CAR](./cbor-and-car)** — Data serialization formats
- **[MST Trees](./mst-trees)** — Merkle Search Tree details
- **[Cryptography](./cryptography)** — Cryptographic operations
- **[Application Layer](../03-application-layer/pds-application)** — Service implementation
