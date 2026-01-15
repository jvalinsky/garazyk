# did:web Implementation Analysis

**Author:** Antigravity  
**Date:** January 14, 2026  
**Repository:** `/Users/jack/Software/objpds`

---

## Executive Summary

This document provides a comprehensive analysis of `did:web` account creation support in the September PDS codebase. The analysis reveals that **most required functionality already exists** across several feature branches, with the `wip-pre-mst-viewer` branch containing the most critical missing pieces.

---

## 1. JWT Verification for `createAccount`

### Location
- **Branch:** `wip-pre-mst-viewer`
- **Commit:** `77ea749`
- **File:** `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- **Lines:** ~60-170

### How to View
```bash
git show 77ea749:ATProtoPDS/Sources/Network/XrpcMethodRegistry.m | sed -n '60,170p'
```

### What It Does

When a `did` parameter is passed to `com.atproto.server.createAccount`, the code:

1. **Extracts JWT from Authorization header:**
   ```objectivec
   NSString *authHeader = [request headerForKey:@"Authorization"];
   // Parses "Bearer <token>" format
   ```

2. **Resolves the DID document:**
   ```objectivec
   DIDResolver *resolver = [[DIDResolver alloc] init];
   NSDictionary *atprotoData = [resolver resolveAtprotoDataForDID:did error:&resolveError];
   NSData *signingKeyBytes = atprotoData[@"signingKeyBytes"];
   ```

3. **Normalizes the public key:**
   ```objectivec
   NSData *publicKey = [[Secp256k1 shared] normalizedPublicKey:signingKeyBytes error:&keyError];
   ```

4. **Verifies the JWT signature:**
   ```objectivec
   JWTVerifier *verifier = [[JWTVerifier alloc] init];
   verifier.publicKey = publicKey;
   verifier.allowedAlgorithms = @[@"ES256K"];
   verifier.expectedIssuer = did;
   verifier.allowMissingSubject = YES;
   BOOL verified = [verifier verifyJWT:jwt error:&verifyError];
   ```

5. **Validates JWT claims:**
   - `iss` must match the provided `did`
   - `aud` must be in the server's expected audiences
   - `lxm` must be `com.atproto.server.createAccount`

### Dependencies
- `DIDResolver` (exists in main: `Core/DID.m`)
- `JWTVerifier` (exists in main: `Auth/JWT.m`)
- `Secp256k1` (exists in main: `Auth/Secp256k1.m`)

---

## 2. `getRecommendedDidCredentials` Endpoint

### Location
- **Branch:** `wip-pre-mst-viewer`
- **Commit:** `77ea749`
- **File:** `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- **Lines:** ~870-900

### How to View
```bash
git show 77ea749:ATProtoPDS/Sources/Network/XrpcMethodRegistry.m | sed -n '870,900p'
```

### What It Does

Returns the recommended DID credentials for updating a user's `did:web` document:

```objectivec
// Resolve the caller's DID
DIDResolver *resolver = [[DIDResolver alloc] init];
NSDictionary *atprotoData = [resolver resolveAtprotoDataForDID:did error:&resolveError];

NSMutableDictionary *result = [NSMutableDictionary dictionary];

// Return handle as alsoKnownAs
NSString *handle = atprotoData[@"handle"];
if (handle) {
    result[@"alsoKnownAs"] = @[handle];
}

// Return signing key in did:key format
NSString *signingKey = atprotoData[@"signingKey"];
if (signingKey) {
    result[@"verificationMethods"] = @{
        @"atproto": [NSString stringWithFormat:@"did:key:%@", signingKey]
    };
}

// Return PDS endpoint
NSString *pds = atprotoData[@"pds"];
if (pds) {
    result[@"services"] = @{@"atproto_pds": pds};
}
```

### Response Format
```json
{
  "alsoKnownAs": ["at://handle.example.com"],
  "verificationMethods": {
    "atproto": "did:key:zQ3sh..."
  },
  "services": {
    "atproto_pds": "https://pds.example.com"
  }
}
```

---

## 3. Account Deactivation/Reactivation

### Location
- **Branch:** `routing-rewrite`
- **Commit:** `be53ebc`
- **File:** `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- **Lines:** ~593-620

### How to View
```bash
git show be53ebc:ATProtoPDS/Sources/Network/XrpcMethodRegistry.m | sed -n '593,620p'
```

### What It Does

The `com.atproto.admin.updateSubjectStatus` endpoint handles account activation/deactivation:

```objectivec
[dispatcher registerComAtprotoAdminUpdateSubjectStatus:^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *body = request.jsonBody;
    NSDictionary *subject = body[@"subject"];
    NSDictionary *takedown = body[@"takedown"];
    NSDictionary *deactivated = body[@"deactivated"];

    NSDictionary *result = [controller updateSubjectStatus:subject
                                                   takedown:takedown
                                                deactivated:deactivated
                                                      error:&error];
}];
```

### CLI Implementation (Main Branch)
- **File:** `ATProtoPDS/Sources/CLI/PDSCLIAccountCommand.m`
- **Lines:** 194-201, 498-514

```objectivec
+ (BOOL)deactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
+ (BOOL)reactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
```

---

## 4. DID Document Serving

### Location (Main Branch)
- **File:** `ATProtoPDS/Sources/CLI/PDSCLIServeCommand.m`
- **Lines:** 224-249

### How to View
```bash
cat ATProtoPDS/Sources/CLI/PDSCLIServeCommand.m | sed -n '224,249p'
```

### What It Does

Serves the server's own DID document at `/.well-known/did.json`:

```objectivec
[httpServer addRoute:@"GET" path:@"/.well-known/did.json" handler:^(...) {
    NSString *hostname = config.publicHostname;
    if (port != 80 && port != 443 && [hostname isEqualToString:@"localhost"]) {
        hostname = [NSString stringWithFormat:@"%@:%ld", hostname, (long)port];
    }
    
    NSString *did = [NSString stringWithFormat:@"did:web:%@", hostname];
    NSString *serviceEndpoint = [NSString stringWithFormat:@"http://%@", hostname];
    
    NSDictionary *doc = @{
        @"@context": @[@"https://www.w3.org/ns/did/v1"],
        @"id": did,
        @"service": @[@{
            @"id": @"#atproto_pds",
            @"type": @"AtprotoPersonalDataServer",
            @"serviceEndpoint": serviceEndpoint
        }],
        @"verificationMethod": @[],  // ⚠️ EMPTY - needs population
        @"authentication": @[]
    };
}];
```

### Gap
The `verificationMethod` array is empty. It should include the server's signing key.

---

## 5. Identity Infrastructure (Main Branch)

### DID Key Encoding
- **File:** `ATProtoPDS/Sources/Identity/DIDKeyEncoder.m`
- **Commit:** `431617c`

Encodes secp256k1 public keys as `did:key` format:
```objectivec
+ (NSString *)encodeDIDKeyFromPublicKey:(NSData *)publicKey error:(NSError **)error;
+ (NSData *)decodePublicKeyFromDIDKey:(NSString *)didKey error:(NSError **)error;
```

### PLC Operation Builder
- **File:** `ATProtoPDS/Sources/Identity/PLCOperationBuilder.m`
- **Commit:** `431617c`

Builds and signs PLC genesis operations for `did:plc` creation.

### DNS TXT Resolution
- **File:** `ATProtoPDS/Sources/Identity/HandleResolver.m`
- **Line:** 280

```objectivec
NSString *dnsName = [NSString stringWithFormat:@"_atproto.%@", handle];
// Queries TXT record, parses "did=did:web:..." format
```

### Secp256k1 Key Generation
- **File:** `ATProtoPDS/Sources/Auth/Secp256k1.m`

```objectivec
+ (nullable instancetype)generateKeyPair:(NSError **)error;
- (nullable NSData *)signHash:(NSData *)hash error:(NSError **)error;
```

---

## 6. Actor Signing Keys

### Location (Main Branch)
- **File:** `ATProtoPDS/Sources/Database/ActorStore/ActorStore.m`
- **Lines:** 1071-1092

### What It Does

Generates and stores per-actor secp256k1 signing keys:

```objectivec
- (BOOL)generateSigningKeyWithError:(NSError **)error {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&genError];
    return [self storeSigningKeyData:keyPair.privateKey forDid:self.did error:error];
}
```

Keys are stored in the Keychain (macOS) or file-based secure storage (Linux).

---

## 7. Git Structure Overview

### Worktrees
```
/Users/jack/Software/objpds                    main
/Users/jack/Software/objpds-fix                fix-pds-transport-actor
/Users/jack/Software/objpds-worktree           codex-test-gap
```

### Key Branches
| Branch | Status | Relevant Content |
|--------|--------|-----------------|
| `main` | Active | DID resolution, Secp256k1, HandleResolver |
| `wip-pre-mst-viewer` | Stale | JWT verification, getRecommendedDidCredentials |
| `routing-rewrite` | Stale | Account deactivation, OpenAPI docs |
| `fix-pds-transport-actor` | Active | HTTP/1.1 chunked encoding |
| `codex-test-gap` | Active | Lexicon registry, Linux fixes |

---

## 8. Recommended Actions

### High Priority: Merge `wip-pre-mst-viewer`
```bash
git cherry-pick 77ea749
```
This adds:
- JWT verification on `createAccount`
- `getRecommendedDidCredentials` endpoint

### Medium Priority: Populate Server DID Document
Edit `PDSCLIServeCommand.m:229` to include:
```objectivec
@"verificationMethod": @[@{
    @"id": [NSString stringWithFormat:@"%@#atproto", did],
    @"type": @"Multikey",
    @"controller": did,
    @"publicKeyMultibase": serverPublicKeyMultibase
}]
```

### Low Priority: Add `activateAccount` XRPC
Wrap `PDSCLIAccountCommand.reactivateAccount` as XRPC endpoint.

---

## Appendix: Verification Commands

### View JWT verification code
```bash
git show 77ea749:ATProtoPDS/Sources/Network/XrpcMethodRegistry.m | head -200
```

### View getRecommendedDidCredentials
```bash
git show 77ea749:ATProtoPDS/Sources/Network/XrpcMethodRegistry.m | sed -n '870,900p'
```

### View account deactivation
```bash
git show be53ebc:ATProtoPDS/Sources/Network/XrpcMethodRegistry.m | sed -n '590,650p'
```

### List all relevant commits
```bash
git log --all --oneline -S "getRecommendedDidCredentials"
git log --all --oneline --grep="did:web"
git log --all --oneline --grep="identity"
```
