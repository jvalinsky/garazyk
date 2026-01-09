# ATProto PDS Implementation - Detailed Plan

## Current Status

**Completed:**
- CBOR encoding/decoding
- MST data structure (v3 spec)
- CAR file format
- JWT signing (ES256)
- OAuth 2.1 (PKCE, DPoP, PAR, metadata endpoints)
- Unit tests for core types

**In Progress:**
- OAuth goal tracking

**Pending:**
- ES256K/secp256k1 signing
- WebSocket firehose
- Relay client
- Integration tests
- Production hardening

---

## Part 1: secp256k1 Integration (Critical Path)

### Recommended Library: bitcoin-core/secp256k1

**Rationale:**
1. Most audited secp256k1 implementation
2. Used by Bitcoin Core with high security standards
3. Supports ECDSA and recovery mode for commit signing
4. Compilable as static library for macOS/iOS

### Implementation Steps

1. **Build secp256k1 as static library**
```bash
git clone https://github.com/bitcoin-core/secp256k1.git
cd secp256k1
./autogen.sh
./configure --enable-module-recovery --enable-module-ecdh
make
# Results: libsecp256k1.a (static library)
```

2. **Create Objective-C wrapper** (`Secp256k1.h/m`)
```objective-c
// Key generation
Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPair];

// Signing
NSData *signature = [[Secp256k1 shared] signHash:hash 
                                    withPrivateKey:keyPair.privateKey];

// Verification
BOOL valid = [[Secp256k1 shared] verifySignature:signature 
                                          forHash:hash 
                                      withPublicKey:keyPair.publicKey];
```

3. **Update Makefile with secp256k1**
```makefile
SECP_FLAGS = -I/secp256k1/include -DSECP256K1_API
SECP_LIBS = -L/secp256k1/.libs -lsecp256k1
CFLAGS += $(SECP_FLAGS)
LDFLAGS += $(SECP_LIBS)
```

### Files to Create
- `ATProtoPDS/ATProtoPDS/Auth/Secp256k1.h`
- `ATProtoPDS/ATProtoPDS/Auth/Secp256k1.m`
- Build scripts for secp256k1

---

## Part 2: Repository Commit Signing

### Required Changes

1. **Commit Structure (v3)**
```json
{
  "did": "did:plc:...",
  "version": 3,
  "data": "bafyrei...",
  "rev": "3k5xyz...",
  "prev": null,
  "sig": <64-byte ECDSA signature>
}
```

2. **Signing Process**
```objective-c
- (NSData *)signCommit:(NSDictionary *)commitDict privateKey:(NSData *)privKey {
    NSData *commitData = dag_cbor_encode(commitDict);
    NSData *commitHash = sha256(commitData);
    return ecdsa_sign(privKey, commitHash);
}
```

3. **Verification Process**
```objective-c
- (BOOL)verifyCommit:(NSDictionary *)commitDict signature:(NSData *)sig {
    NSData *commitData = dag_cbor_encode(commitDict);
    NSData *commitHash = sha256(commitData);
    NSData *pubKey = getAccountSigningKey(commitDict[@"did"]);
    return ecdsa_verify(pubKey, commitHash, sig);
}
```

### Files to Modify
- `ATProtoPDS/ATProtoPDS/Repository/RepoCommit.h`
- `ATProtoPDS/ATProtoPDS/Repository/RepoCommit.m`
- `ATProtoPDS/ATProtoPDS/PDSController.m` (integrate signing)

---

## Part 3: WebSocket Firehose

### com.atproto.sync.subscribeRepos Implementation

1. **WebSocket Endpoint**
```objective-c
@interface FirehoseServer : NSObject
- (void)startOnPort:(uint16_t)port;
- (void)broadcastCommit:(NSDictionary *)commit forDid:(NSString *)did;
- (void)handleSubscription:(WebSocket *)ws params:(NSDictionary *)params;
@end
```

2. **Event Format**
```json
{
  "kind": "commit",
  "repo": "did:plc:...",
  "commit": "bafyrei...",
  "rev": "3k5xyz...",
  "since": "3k5xww...",
  "blocks": <CAR bytes>,
  "ops": [
    {"action": "create", "path": "app.bsky.feed.post/3k5xyz", "cid": "bafyrei..."}
  ]
}
```

3. **Sequence Management**
```objective-c
@interface FirehoseSequence : NSObject
@property (nonatomic, assign) uint64_t sequence;
@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy) NSString *rev;
- (void)persistState;
+ (nullable instancetype)loadStateForDid:(NSString *)did;
@end
```

### Files to Create
- `ATProtoPDS/ATProtoPDS/Sync/Firehose/FirehoseServer.h`
- `ATProtoPDS/ATProtoPDS/Sync/firehose/FirehoseServer.m`
- `ATProtoPDS/ATProtoPDS/Sync/firehose/FirehoseEvent.h`

---

## Part 4: Bluesky Relay Client

### Relay Connection

1. **WebSocket Connection**
```objective-c
@interface RelayClient : NSObject
@property (nonatomic, strong) WebSocket *ws;
@property (nonatomic, strong) dispatch_queue_t receiveQueue;

- (void)connectToRelay:(NSURL *)relayURL;
- (void)subscribeToRepo:(NSString *)did;
- (void)handleMessage:(NSDictionary *)message;
@end
```

2. **Backfill Handling**
```objective-c
- (void)handleGap:(NSString *)did fromRev:(NSString *)fromRev toRev:(NSString *)toRev {
    NSData *repoData = [self getRepoDiff:did since:fromRev];
    [self applyRepoData:repoData forDid:did];
}
```

3. **Message Processing**
```objective-c
- (void)processCommitMessage:(NSDictionary *)message {
    NSString *did = message[@"repo"];
    NSString *rev = message[@"rev"];
    NSData *blocks = message[@"blocks"];
    NSArray *ops = message[@"ops"];

    for (NSDictionary *op in ops) {
        [self applyOperation:op blocks:blocks forDid:did];
    }
}
```

### Files to Create
- `ATProtoPDS/ATProtoPDS/Sync/RelayClient.h`
- `ATProtoPDS/ATProtoPDS/Sync/RelayClient.m`

---

## Part 5: Integration Tests

### OAuth Integration Tests
```bash
# Test PAR flow
1. POST /oauth/par with PKCE challenge
2. GET /oauth/authorize?request_uri=xxx
3. User authenticates
4. POST /oauth/token with code verifier
5. Verify DPoP binding on token requests
```

### Repository Tests
```bash
# Test commit signing
1. Create record (creates unsigned commit)
2. Sign commit with secp256k1
3. Verify signature
4. Export CAR
5. Import CAR (verify commit chain)
```

### Sync Tests
```bash
# Test firehose
1. Start WebSocket subscription
2. Create record on repo
3. Verify commit event received
4. Verify sequence ordering
```

---

## Part 6: Production Hardening

### TLS Configuration
```objective-c
nw_parameters_t params = nw_parameters_create_secure_tcp(
    NW_PARAMETERS_DISABLE_PROTOCOL,
    NW_PARAMETERS_DEFAULT_CONFIGURATION
);

// Configure TLS 1.3 only
if (@available(macOS 10.15, iOS 13.0, *)) {
    sec_protocol_options_set_tls_minimum_version(tlsOpts, tls_protocol_version_1_3);
}
```

### Rate Limiting
```objective-c
@interface RateLimiter : NSObject
- (BOOL)checkRateLimitForAccount:(NSString *)did limit:(NSUInteger)limit window:(NSTimeInterval)window;
- (BOOL)checkRateLimitForIP:(NSString *)ip limit:(NSUInteger)limit window:(NSTimeInterval)window;
@end
```

### Health Endpoints
- `GET /health` - Basic health check
- `GET /metrics` - Prometheus metrics
- `GET /debug/vars` - Go-style expvar

---

## Priority Order

| Priority | Task | Dependency |
|----------|------|------------|
| 1 | secp256k1 integration | None |
| 2 | Commit signing | secp256k1 |
| 3 | WebSocket firehose | None |
| 4 | Relay client | Firehose |
| 5 | Integration tests | All above |
| 6 | Production hardening | None |

---

## Estimated Effort

| Task | Effort |
|------|--------|
| secp256k1 build + wrapper | 2-4 hours |
| Commit signing | 4-6 hours |
| WebSocket firehose | 6-8 hours |
| Relay client | 4-6 hours |
| Integration tests | 4-8 hours |
| Production hardening | 4-6 hours |

**Total: 24-38 hours**

---

## Dependencies to Add

1. **bitcoin-core/secp256k1** - C library for secp256k1 ECDSA
2. **CocoaAsyncSocket** (optional) - WebSocket support if Network.framework insufficient

---

## References

- [ATProto Repository Spec](https://atproto.com/specs/repository)
- [ATProto Sync Spec](https://atproto.com/specs/sync)
- [OAuth ATProto Profile](https://atproto.com/specs/oauth)
- [bitcoin-core/secp256k1](https://github.com/bitcoin-core/secp256k1)
