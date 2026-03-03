# PLC Directory

The PLC (Public Ledger of Credentials) directory is a critical component of the AT Protocol that provides decentralized identity management through DID (Decentralized Identifier) resolution. September PDS includes both a PLC client for resolving DIDs and a standalone PLC server (`campagnola`) for running your own directory.

## Overview

The PLC directory serves as a distributed registry for `did:plc` identifiers, maintaining an immutable audit log of DID operations. Each DID has a hash-linked chain of operations that define its state over time, including:

- **Rotation Keys** — Keys authorized to update the DID
- **Verification Methods** — Public keys for authentication
- **Also Known As** — Alternative identifiers (handles)
- **Services** — Service endpoints (PDS URL, etc.)

## PLC Protocol

### DID Format

PLC DIDs follow the format: `did:plc:<base32-identifier>`

```objc
// From ATProtoPDS/Sources/PLC/PLCOperation.h

+ (BOOL)isValidDidPlc:(NSString *)did {
    // Format: did:plc:[a-z2-7]{24}
    if (![did hasPrefix:@"did:plc:"]) {
        return NO;
    }
    
    NSString *identifier = [did substringFromIndex:8];
    if (identifier.length != 24) {
        return NO;
    }
    
    // Validate base32 lowercase characters
    NSCharacterSet *base32 = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz234567"];
    NSCharacterSet *identifierChars = [NSCharacterSet characterSetWithCharactersInString:identifier];
    
    return [base32 isSupersetOfSet:identifierChars];
}
```

**Valid DIDs:**
- `did:plc:z72i7hdynmk6r22z27h6tvur`
- `did:plc:ewvi7nxzyoun6zhxrhs64oiz`

**Invalid DIDs:**
- `did:plc:UPPERCASE` (must be lowercase)
- `did:plc:tooshort` (must be exactly 24 characters)
- `did:plc:invalid!chars` (only base32 characters)

### Operation Types

#### 1. PLC Operation (plc_operation)

Standard operation for updating DID state:

```json
{
  "type": "plc_operation",
  "rotationKeys": [
    "did:key:zQ3shXjHeiBuRCKmM36cuYnm7YEMzhGnCmCyW92sRJ9pribSF"
  ],
  "verificationMethods": {
    "atproto": "did:key:zQ3shXjHeiBuRCKmM36cuYnm7YEMzhGnCmCyW92sRJ9pribSF"
  },
  "alsoKnownAs": [
    "at://alice.bsky.social"
  ],
  "services": {
    "atproto_pds": {
      "type": "AtprotoPersonalDataServer",
      "endpoint": "https://pds.garazyk.xyz"
    }
  },
  "prev": "bafyreib2rxk3rh...",
  "sig": "base64-signature"
}
```

**Fields:**
- `rotationKeys` — Array of `did:key` identifiers authorized to sign updates (max 10)
- `verificationMethods` — Map of key IDs to `did:key` identifiers (max 10)
- `alsoKnownAs` — Array of alternative identifiers (max 10, max 258 chars each)
- `services` — Map of service definitions (max 10)
- `prev` — CID of previous operation (null for genesis)
- `sig` — Base64-encoded signature of operation hash

#### 2. PLC Tombstone (plc_tombstone)

Permanently deactivates a DID:

```json
{
  "type": "plc_tombstone",
  "prev": "bafyreib2rxk3rh...",
  "sig": "base64-signature"
}
```

**Important:** Tombstoning is irreversible. The DID cannot be reactivated.

### Operation Chain

Operations form a hash-linked chain where each operation references the previous one:

```
Genesis Operation (prev: null)
    ↓ (CID: bafyreiabc...)
Update Operation 1 (prev: bafyreiabc...)
    ↓ (CID: bafyreidef...)
Update Operation 2 (prev: bafyreidef...)
    ↓ (CID: bafyreighi...)
Current State
```

The DID's current state is computed by replaying all operations in order.

## DID Resolution

### Using DIDPLCResolver

The `DIDPLCResolver` class provides both synchronous and asynchronous DID resolution:

```objc
// From ATProtoPDS/Sources/PLC/DIDPLCResolver.h

// Initialize resolver
DIDPLCResolver *resolver = [[DIDPLCResolver alloc] initWithPlcUrl:@"https://plc.directory"];
resolver.timeout = 5.0;  // 5 second timeout

// Synchronous resolution
NSError *error = nil;
NSDictionary *document = [resolver resolveDID:@"did:plc:z72i7hdynmk6r22z27h6tvur" error:&error];
if (document) {
    NSString *pdsEndpoint = document[@"service"][0][@"serviceEndpoint"];
    NSLog(@"PDS endpoint: %@", pdsEndpoint);
}

// Asynchronous resolution
[resolver resolveDID:@"did:plc:z72i7hdynmk6r22z27h6tvur" 
          completion:^(NSDictionary *document, NSError *error) {
    if (document) {
        // Process DID document
    } else {
        NSLog(@"Resolution failed: %@", error.localizedDescription);
    }
}];
```

### DID Document Structure

A resolved DID document follows the W3C DID Core specification:

```json
{
  "@context": [
    "https://www.w3.org/ns/did/v1",
    "https://w3id.org/security/multikey/v1",
    "https://w3id.org/security/suites/secp256k1-2019/v1"
  ],
  "id": "did:plc:z72i7hdynmk6r22z27h6tvur",
  "alsoKnownAs": [
    "at://alice.bsky.social"
  ],
  "verificationMethod": [
    {
      "id": "did:plc:z72i7hdynmk6r22z27h6tvur#atproto",
      "type": "Multikey",
      "controller": "did:plc:z72i7hdynmk6r22z27h6tvur",
      "publicKeyMultibase": "zQ3shXjHeiBuRCKmM36cuYnm7YEMzhGnCmCyW92sRJ9pribSF"
    }
  ],
  "service": [
    {
      "id": "#atproto_pds",
      "type": "AtprotoPersonalDataServer",
      "serviceEndpoint": "https://pds.garazyk.xyz"
    }
  ]
}
```

### Audit Log Resolution

Retrieve the complete operation history for a DID:

```objc
// Synchronous audit log retrieval
NSError *error = nil;
NSArray *auditLog = [resolver resolveAuditLogForDID:@"did:plc:z72i7hdynmk6r22z27h6tvur" error:&error];

for (NSDictionary *operation in auditLog) {
    NSString *cid = operation[@"cid"];
    NSString *type = operation[@"type"];
    NSDate *createdAt = operation[@"createdAt"];
    
    NSLog(@"Operation %@ (%@) at %@", cid, type, createdAt);
}

// Asynchronous audit log retrieval
[resolver resolveAuditLogForDID:@"did:plc:z72i7hdynmk6r22z27h6tvur"
                     completion:^(NSArray *log, NSError *error) {
    if (log) {
        NSLog(@"Retrieved %lu operations", (unsigned long)log.count);
    }
}];
```

## State Replay

The `PLCStateReplayer` class computes the current DID state from operation history:

```objc
// From ATProtoPDS/Sources/PLC/PLCOperation.h

// Replay operation history
NSArray<PLCOperation *> *history = /* ... fetch from PLC ... */;

NSError *error = nil;
PLCDIDState *state = [PLCStateReplayer replayHistory:history error:&error];

if (state) {
    NSLog(@"DID: %@", state.did);
    NSLog(@"Rotation Keys: %@", state.rotationKeys);
    NSLog(@"Verification Methods: %@", state.verificationMethods);
    NSLog(@"Also Known As: %@", state.alsoKnownAs);
    NSLog(@"Services: %@", state.services);
    NSLog(@"Tombstoned: %@", state.tombstoned ? @"YES" : @"NO");
    
    // Convert to DID document
    NSDictionary *document = [state toDIDDocument];
}
```

**Replay Process:**

1. Start with empty state
2. For each operation in chronological order:
   - Verify signature with rotation keys
   - Verify `prev` links to previous operation CID
   - Apply operation to state
3. Return final computed state

## Running Campagnola (PLC Server)

September PDS includes `campagnola`, a standalone PLC directory server.

### Starting the Server

```bash
# Using in-memory mock store (development)
campagnola --port 2582

# Using persistent SQLite database (production)
campagnola --port 2582 --database /path/to/plc.db
```

**Command-line options:**
- `--port <number>` — Port to listen on (default: 2582)
- `--database <path>` — Path to SQLite database (optional, uses mock store if omitted)
- `--help, -h` — Show help information

### Server Implementation

```objc
// From ATProtoPDS/Sources/PLC/main.m

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSUInteger port = 2582;
        NSString *dbPath = nil;
        
        // Parse command-line arguments
        // ...
        
        // Initialize store
        id<PLCStore> store = nil;
        if (dbPath) {
            NSError *storeError = nil;
            store = [PLCPersistentStore storeWithPath:dbPath error:&storeError];
            if (!store) {
                PDS_LOG_CORE_ERROR(@"Failed to open persistent store: %@", storeError);
                return 1;
            }
        } else {
            store = [[PLCMockStore alloc] init];
        }
        
        // Initialize auditor and server
        PLCAuditor *auditor = [[PLCAuditor alloc] initWithStore:store];
        PLCServer *server = [[PLCServer alloc] initWithStore:store 
                                                     auditor:auditor 
                                                        port:port];
        
        // Start server
        NSError *error = nil;
        if (![server startWithError:&error]) {
            PDS_LOG_CORE_ERROR(@"Failed to start PLC server: %@", error);
            return 1;
        }
        
        printf("PLC server listening on port %lu\n", (unsigned long)port);
        
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
```

### API Endpoints

The PLC server implements the following HTTP endpoints:

#### GET /:did

Resolve a DID to its current document:

```bash
curl https://plc.directory/did:plc:z72i7hdynmk6r22z27h6tvur
```

**Response:**
```json
{
  "@context": ["https://www.w3.org/ns/did/v1"],
  "id": "did:plc:z72i7hdynmk6r22z27h6tvur",
  "alsoKnownAs": ["at://alice.bsky.social"],
  "verificationMethod": [...],
  "service": [...]
}
```

#### GET /:did/log

Retrieve the complete audit log for a DID:

```bash
curl https://plc.directory/did:plc:z72i7hdynmk6r22z27h6tvur/log
```

**Response:**
```json
[
  {
    "cid": "bafyreiabc...",
    "type": "plc_operation",
    "createdAt": "2024-01-15T10:30:00Z",
    "operation": {
      "type": "plc_operation",
      "rotationKeys": [...],
      "prev": null,
      "sig": "..."
    }
  },
  {
    "cid": "bafyreidef...",
    "type": "plc_operation",
    "createdAt": "2024-02-20T14:45:00Z",
    "operation": {
      "type": "plc_operation",
      "rotationKeys": [...],
      "prev": "bafyreiabc...",
      "sig": "..."
    }
  }
]
```

#### POST /:did

Submit a new operation for a DID:

```bash
curl -X POST https://plc.directory/did:plc:z72i7hdynmk6r22z27h6tvur \
  -H "Content-Type: application/json" \
  -d '{
    "type": "plc_operation",
    "rotationKeys": ["did:key:..."],
    "verificationMethods": {...},
    "alsoKnownAs": [...],
    "services": {...},
    "prev": "bafyreib2rxk3rh...",
    "sig": "base64-signature"
  }'
```

**Response:** HTTP 200 with operation CID on success, 400/403 on validation failure.

### Operation Validation

The `PLCAuditor` validates operations before accepting them:

```objc
// From ATProtoPDS/Sources/PLC/PLCServer.m

static BOOL PLCValidateIncomingOperation(NSDictionary *op, NSError **error) {
    // 1. Check CBOR size limit (4000 bytes)
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:op error:error];
    if (cbor.length > kPLCMaxOperationBytes) {
        // Reject: operation too large
        return NO;
    }
    
    // 2. Validate operation type
    NSString *type = op[@"type"];
    if (![type isEqualToString:@"plc_operation"] && 
        ![type isEqualToString:@"plc_tombstone"]) {
        // Reject: unsupported type
        return NO;
    }
    
    // 3. Validate signature format
    NSString *sig = op[@"sig"];
    if ([sig hasSuffix:@"="]) {
        // Reject: signature must be base64url (no padding)
        return NO;
    }
    
    // 4. Validate field limits
    NSArray *rotationKeys = op[@"rotationKeys"];
    if (rotationKeys.count > kPLCMaxRotationKeyEntries) {
        // Reject: too many rotation keys
        return NO;
    }
    
    // 5. Validate did:key format
    for (NSString *key in rotationKeys) {
        if (!PLCValidateDidKey(key, error)) {
            return NO;
        }
    }
    
    // 6. Check for duplicate alsoKnownAs entries
    NSArray *alsoKnownAs = op[@"alsoKnownAs"];
    NSSet *uniqueAKA = [NSSet setWithArray:alsoKnownAs];
    if (uniqueAKA.count != alsoKnownAs.count) {
        // Reject: duplicate entries
        return NO;
    }
    
    return YES;
}
```

**Validation Rules:**
- Maximum operation size: 4000 bytes (CBOR-encoded)
- Maximum rotation keys: 10
- Maximum verification methods: 10
- Maximum alsoKnownAs entries: 10 (max 258 chars each)
- Maximum services: 10
- Signature must be base64url (no padding)
- All `did:key` identifiers must be valid

## Submitting Operations

### From CLI

Use the `kaszlak` CLI to update PLC operations:

```bash
# Update PDS endpoint
kaszlak account update-plc-endpoint did:plc:abc123 https://new-pds.example.com

# Update handle
kaszlak account update-handle did:plc:abc123 newhandle.bsky.social
```

### Programmatically

```objc
// Create operation
NSDictionary *operation = @{
    @"type": @"plc_operation",
    @"rotationKeys": @[@"did:key:zQ3sh..."],
    @"verificationMethods": @{
        @"atproto": @"did:key:zQ3sh..."
    },
    @"alsoKnownAs": @[@"at://alice.bsky.social"],
    @"services": @{
        @"atproto_pds": @{
            @"type": @"AtprotoPersonalDataServer",
            @"endpoint": @"https://pds.garazyk.xyz"
        }
    },
    @"prev": previousCID,
    @"sig": signature
};

// Submit to PLC directory
DIDPLCResolver *resolver = [[DIDPLCResolver alloc] initWithPlcUrl:@"https://plc.directory"];

NSInteger statusCode = 0;
NSError *error = nil;
NSData *response = [resolver submitOperation:operation 
                                         did:@"did:plc:abc123" 
                                  statusCode:&statusCode 
                                       error:&error];

if (statusCode == 200) {
    NSLog(@"Operation submitted successfully");
} else {
    NSLog(@"Submission failed: %ld", (long)statusCode);
}
```

## Configuration

### PDS Configuration

Configure PLC URL in `config.json`:

```json
{
  "plc": {
    "url": "https://plc.directory",
    "retry_count": 5,
    "retry_delay_ms": 2000
  }
}
```

**Options:**
- `url` — PLC directory URL (use `"mock"` for testing, never in production)
- `retry_count` — Number of retry attempts for failed requests
- `retry_delay_ms` — Delay between retries in milliseconds

### CLI Initialization

The `kaszlak init` command prompts for PLC configuration:

```bash
$ kaszlak init

PLC Directory Service:
  1. Production (plc.directory)
  2. Mock
  3. Custom URL

Select option [1]: 1
```

**Production:** Always use `https://plc.directory` for production deployments.

**Mock:** Use mock PLC for local development and testing only.

**Custom:** Use a custom PLC server (e.g., your own `campagnola` instance).

## Best Practices

### 1. Key Management

- **Rotate keys regularly** — Update rotation keys periodically
- **Secure key storage** — Store private keys in Keychain/secure storage
- **Backup rotation keys** — Keep secure backups of rotation keys
- **Separate keys** — Use different keys for rotation vs. verification

### 2. Operation Submission

- **Verify prev links** — Ensure `prev` references the current operation CID
- **Sign correctly** — Use the rotation key to sign operation hash
- **Validate before submit** — Check operation format before submission
- **Handle failures** — Implement retry logic with exponential backoff

### 3. Resolution

- **Cache DID documents** — Cache resolved documents with TTL
- **Handle timeouts** — Set appropriate timeout values (5-10 seconds)
- **Fallback strategy** — Have fallback PLC servers configured
- **Monitor resolution** — Track resolution failures and latency

### 4. Running a PLC Server

- **Use persistent storage** — Always use SQLite database in production
- **Regular backups** — Backup the PLC database regularly
- **Monitor disk space** — Audit logs grow over time
- **Rate limiting** — Implement rate limiting on submission endpoint
- **HTTPS only** — Always use TLS for production PLC servers

## Security Considerations

### Operation Signing

Operations must be signed with a rotation key:

```objc
// 1. Compute operation hash (CID)
NSString *cid = [PLCOperation calculateCIDForOperation:operation error:&error];

// 2. Sign the CID with rotation key
NSData *signature = [self signData:[cid dataUsingEncoding:NSUTF8StringEncoding] 
                           withKey:rotationKey];

// 3. Add base64url-encoded signature to operation
operation[@"sig"] = [signature base64EncodedStringWithOptions:0];
```

### Signature Verification

The PLC server verifies signatures before accepting operations:

1. Extract rotation keys from previous operation
2. Compute CID of new operation (excluding signature)
3. Verify signature matches one of the rotation keys
4. Verify `prev` links to previous operation CID

### Tombstone Protection

Tombstoning is irreversible. Verify before submitting:

```objc
// Warn before tombstoning
if ([operation[@"type"] isEqualToString:@"plc_tombstone"]) {
    NSLog(@"WARNING: Tombstoning is irreversible!");
    NSLog(@"DID will be permanently deactivated.");
    
    // Require explicit confirmation
    if (![self confirmTombstone]) {
        return NO;
    }
}
```

## Related Documentation

- [DID and NSID](atproto-basics.md) — AT Protocol identifiers
- [Identity Resolution](../05-identity/did-resolution.md) — DID resolution patterns
- [Key Rotation](../06-authentication/key-rotation.md) — Key management strategies
- [Secrets Management](../06-authentication/secrets-management.md) — Secure key storage

## External Resources

- AT Protocol DID Specification: https://atproto.com/specs/did
- PLC Directory: https://plc.directory
- W3C DID Core: https://www.w3.org/TR/did-core/
- DID Method Registry: https://w3c.github.io/did-spec-registries/
