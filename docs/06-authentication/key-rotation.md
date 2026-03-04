---
title: Key Rotation
---

# Key Rotation

## Overview

Key rotation is the process of periodically replacing cryptographic keys used for signing and authentication. Regular key rotation reduces the impact of key compromise and follows security best practices.

## Key Types

The PDS manages several types of keys:

| Key Type | Purpose | Rotation Frequency |
|----------|---------|-------------------|
| Account signing key | Sign repository commits | Annually |
| OAuth client secret | OAuth authentication | Quarterly |
| JWT signing key | Sign access tokens | Annually |
| DPoP key | DPoP proof generation | Per-session |

## Rotation Strategy

### Account Signing Key Rotation

```

Current Key (Active)
    ↓
    ├─ Used for new commits
    ├─ Stored in account database
    └─ Published in DID document
    
Old Key (Deprecated)
    ├─ Still valid for verification
    ├─ Kept for 30 days
    └─ Removed after expiration
    
New Key (Staged)
    ├─ Generated before rotation
    ├─ Published in DID document
    └─ Activated at rotation time
```

### Rotation Timeline

```

Day 1: Generate new key
Day 2: Publish new key in DID document
Day 3: Activate new key (start using for signing)
Day 4-33: Keep old key for verification
Day 34: Remove old key
```

## Implementation

### Key Rotation Manager

The `PLCRotationKeyManager` handles secure key generation, storage, and rotation:

```objc
@interface PLCRotationKeyManager : NSObject

// Singleton instance
+ (instancetype)sharedManager;

// Initialize with storage path
- (instancetype)initWithStoragePath:(nullable NSString *)path;

// Load or generate rotation key
- (BOOL)loadOrGenerateKeyWithError:(NSError **)error;

// Sign data with rotation key
- (BOOL)signHash:(NSData *)hash result:(NSData * _Nullable * _Nullable)result error:(NSError **)error;

// Clear key from memory and storage
- (void)clearKey;

// Get the DID key string representation
@property (nonatomic, copy, readonly, nullable) NSString *rotationKeyDidKey;

@end
```

**Source:** `ATProtoPDS/Sources/PLC/PLCRotationKeyManager.m`

### Loading or Generating Keys

Keys are loaded from secure storage or generated if they don't exist:

```objc
// In PLCRotationKeyManager.m (ATProtoPDS/Sources/PLC/PLCRotationKeyManager.m)
- (BOOL)loadOrGenerateKeyWithError:(NSError **)error {
    if (self.rotationKeyPair) {
        return YES;
    }
    
    NSString *keyPath = [self keyFilePath];
    
    if (keyPath) {
        // Proactively secure permissions if the file already exists
        [self ensureSecurePermissionsForPath:keyPath isDirectory:NO];
        NSString *directory = [keyPath stringByDeletingLastPathComponent];
        [self ensureSecurePermissionsForPath:directory isDirectory:YES];
    }
    
    // 1. Check if key file exists
    if ([[NSFileManager defaultManager] fileExistsAtPath:keyPath]) {
        NSData *keyData = [NSData dataWithContentsOfFile:keyPath];
        NSData *privateKeyData = nil;
        
        // 2. Handle legacy unencrypted keys
        if (keyData.length == 32) {
            privateKeyData = keyData;
            PDS_LOG_INFO(@"Detected legacy unencrypted rotation key.");
            
            // Migrate to encrypted if master secret is available
            NSData *encKey = [self encryptionKeyWithError:nil];
            if (encKey) {
                NSData *encrypted = [CryptoUtils encryptData:privateKeyData withKey:encKey];
                if (encrypted) {
                    if ([encrypted writeToFile:keyPath atomically:YES]) {
                        PDS_LOG_INFO(@"Successfully migrated rotation key to encrypted storage.");
                        [self ensureSecurePermissionsForPath:keyPath isDirectory:NO];
                    }
                }
            }
        } else if (keyData.length > 32) {
            // 3. Decrypt encrypted key
            NSData *encKey = [self encryptionKeyWithError:error];
            if (encKey) {
                privateKeyData = [CryptoUtils decryptData:keyData withKey:encKey];
                if (!privateKeyData) {
                    PDS_LOG_ERROR(@"Failed to decrypt rotation key. Possible invalid master secret.");
                    if (error && !*error) {
                        *error = [NSError errorWithDomain:PLCRotationKeyManagerErrorDomain
                                                     code:PLCRotationKeyManagerErrorKeyStorageFailed
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to decrypt rotation key"}];
                    }
                    return NO;
                }
            } else {
                return NO;
            }
        }
        
        // 4. Reconstruct key pair from private key data
        if (privateKeyData && privateKeyData.length == 32) {
            NSError *keyError = nil;
            self.rotationKeyPair = [[Secp256k1 shared] keyPairFromPrivateKey:privateKeyData error:&keyError];
            if (self.rotationKeyPair) {
                self.rotationKeyDidKey = self.rotationKeyPair.didKeyString;
                PDS_LOG_INFO(@"Loaded rotation key: %@", self.rotationKeyDidKey);
                return YES;
            }
            PDS_LOG_ERROR(@"Failed to reconstruct rotation key: %@", keyError);
        }
    }
    
    // 5. Generate new key if none exists
    NSError *genError = nil;
    self.rotationKeyPair = [[Secp256k1 shared] generateKeyPairWithError:&genError];
    if (!self.rotationKeyPair) {
        if (error) {
            *error = [NSError errorWithDomain:PLCRotationKeyManagerErrorDomain
                                         code:PLCRotationKeyManagerErrorKeyGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: genError.localizedDescription ?: @"Failed to generate rotation key"}];
        }
        return NO;
    }
    
    self.rotationKeyDidKey = self.rotationKeyPair.didKeyString;
    
    // 6. Save new key to secure storage
    if (keyPath) {
        NSString *directory = [keyPath stringByDeletingLastPathComponent];
        NSError *dirError = nil;
        if (![[NSFileManager defaultManager] fileExistsAtPath:directory]) {
            NSDictionary *attrs = @{NSFilePosixPermissions: @(0700)};
            [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                      withIntermediateDirectories:YES
                                                       attributes:attrs
                                                            error:&dirError];
        } else {
            [self ensureSecurePermissionsForPath:directory isDirectory:YES];
        }
        
        NSData *dataToSave = self.rotationKeyPair.privateKey;
        NSData *encKey = [self encryptionKeyWithError:nil];
        if (encKey) {
            NSData *encrypted = [CryptoUtils encryptData:dataToSave withKey:encKey];
            if (encrypted) {
                dataToSave = encrypted;
            }
        }
        
        if (![dataToSave writeToFile:keyPath atomically:YES]) {
            PDS_LOG_ERROR(@"Failed to write rotation key to: %@", keyPath);
        } else {
            [self ensureSecurePermissionsForPath:keyPath isDirectory:NO];
            PDS_LOG_INFO(@"Generated and saved new PLC rotation key: %@", self.rotationKeyDidKey);
        }
    }
    
    return YES;
}
```

**Source:** `ATProtoPDS/Sources/PLC/PLCRotationKeyManager.m` lines 40-130

### Signing with Rotation Key

The rotation key is used to sign PLC operations:

```objc
// In PLCRotationKeyManager.m (ATProtoPDS/Sources/PLC/PLCRotationKeyManager.m)
- (BOOL)signHash:(NSData *)hash result:(NSData * _Nullable * _Nullable)result error:(NSError **)error {
    // 1. Ensure key is loaded
    if (!self.rotationKeyPair) {
        if (![self loadOrGenerateKeyWithError:error]) {
            return NO;
        }
    }
    
    // 2. Validate hash is 32 bytes (SHA-256)
    if (!hash || hash.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PLCRotationKeyManagerErrorDomain
                                         code:PLCRotationKeyManagerErrorInvalidKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid hash (must be 32 bytes)"}];
        }
        return NO;
    }
    
    // 3. Sign hash with private key
    NSError *signError = nil;
    NSData *signature = [[Secp256k1 shared] signHash:hash withPrivateKey:self.rotationKeyPair.privateKey error:&signError];
    if (!signature) {
        if (error) {
            *error = [NSError errorWithDomain:PLCRotationKeyManagerErrorDomain
                                         code:PLCRotationKeyManagerErrorKeyStorageFailed
                                     userInfo:@{NSLocalizedDescriptionKey: signError.localizedDescription ?: @"Failed to sign hash"}];
        }
        return NO;
    }
    
    // 4. Return signature
    if (result) {
        *result = signature;
    }
    return YES;
}
```

**Source:** `ATProtoPDS/Sources/PLC/PLCRotationKeyManager.m` lines 132-160

### Secure Key Storage

Keys are stored with restricted file permissions and optional encryption:

```objc
// In PLCRotationKeyManager.m (ATProtoPDS/Sources/PLC/PLCRotationKeyManager.m)
- (void)ensureSecurePermissionsForPath:(NSString *)path isDirectory:(BOOL)isDir {
    if (!path) return;
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return;
    
    // 1. Set restrictive permissions
    short mode = isDir ? 0700 : 0600;  // Owner read/write only
    NSDictionary *attrs = @{NSFilePosixPermissions: @(mode)};
    
    // 2. Apply permissions
    NSError *error = nil;
    if (![fm setAttributes:attrs ofItemAtPath:path error:&error]) {
        PDS_LOG_ERROR(@"Failed to set secure permissions (mode %o) on %@: %@", mode, path, error);
    } else {
        PDS_LOG_DEBUG(@"Set secure permissions (mode %o) on %@", mode, path);
    }
}

- (nullable NSData *)encryptionKeyWithError:(NSError **)error {
    // 1. Get master secret from configuration
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSString *secret = config.masterSecret;
    if (secret.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCRotationKeyManagerErrorDomain
                                         code:PLCRotationKeyManagerErrorKeyStorageFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"PDS_MASTER_SECRET not configured"}];
        }
        return nil;
    }
    
    // 2. Derive encryption key from master secret using fixed salt
    static uint8_t saltBytes[] = { 0x41, 0x54, 0x50, 0x52, 0x4f, 0x54, 0x4f, 0x5f, 0x50, 0x44, 0x53, 0x5f, 0x4b, 0x45, 0x59, 0x53 };
    NSData *salt = [NSData dataWithBytes:saltBytes length:sizeof(saltBytes)];
    
    return [CryptoUtils deriveKeyFromPassword:secret salt:salt];
}
```

**Source:** `ATProtoPDS/Sources/PLC/PLCRotationKeyManager.m` lines 162-210

## Key Storage

### Secure Key Storage

Keys are stored securely:

```objc
// Store in Keychain (macOS)
SecKeychainItemRef item = nil;
SecKeychainAddGenericPassword(NULL,
                             (UInt32)strlen(serviceName),
                             serviceName,
                             (UInt32)strlen(accountName),
                             accountName,
                             (UInt32)keyData.length,
                             keyData.bytes,
                             &item);

// Or in file with restricted permissions (Linux)
chmod(keyFilePath, 0600);  // Owner read/write only
```

### Key Metadata

```sql
CREATE TABLE signing_keys (
    key_id TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    key_data BLOB NOT NULL,
    status TEXT,  -- active, staged, deprecated
    created_at DATETIME NOT NULL,
    activated_at DATETIME,
    deprecated_at DATETIME,
    expires_at DATETIME,
    FOREIGN KEY (did) REFERENCES accounts(did)
);

CREATE INDEX idx_signing_keys_did ON signing_keys(did);
CREATE INDEX idx_signing_keys_status ON signing_keys(status);
```

## Rotation Policies

### Automatic Rotation

```objc
// Rotate keys annually
dispatch_source_t rotationTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                         0, 0,
                                                         dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));

dispatch_source_set_timer(rotationTimer,
                         dispatch_time(DISPATCH_TIME_NOW, 365*24*3600*NSEC_PER_SEC),
                         365*24*3600*NSEC_PER_SEC,
                         24*3600*NSEC_PER_SEC);

dispatch_source_set_event_handler(rotationTimer, ^{
    NSArray *accounts = [self getAllAccounts];
    for (NSDictionary *account in accounts) {
        NSError *error = nil;
        [rotationManager rotateAccountSigningKey:account[@"did"] error:&error];
        if (error) {
            NSLog(@"Rotation failed for %@: %@", account[@"did"], error);
        }
    }
});

dispatch_resume(rotationTimer);
```

### Manual Rotation

```objc
// Rotate on demand
NSError *error = nil;
BOOL success = [rotationManager rotateAccountSigningKey:userDid error:&error];

if (success) {
    NSLog(@"Key rotated successfully");
} else {
    NSLog(@"Rotation failed: %@", error);
}
```

## Monitoring

### Key Status

```objc
- (NSDictionary *)getKeyStatus:(NSString *)keyId error:(NSError **)error {
    NSArray *result = [database executeQuery:
        @"SELECT * FROM signing_keys WHERE key_id = ?", keyId];
    
    if (result.count == 0) {
        return nil;
    }
    
    NSDictionary *keyRecord = result[0];
    return @{
        @"key_id": keyId,
        @"status": keyRecord[@"status"],
        @"created_at": keyRecord[@"created_at"],
        @"activated_at": keyRecord[@"activated_at"],
        @"deprecated_at": keyRecord[@"deprecated_at"],
        @"expires_at": keyRecord[@"expires_at"]
    };
}
```

### Rotation Audit Log

```sql
CREATE TABLE key_rotation_audit (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    did TEXT NOT NULL,
    old_key_id TEXT,
    new_key_id TEXT,
    rotation_type TEXT,  -- account_signing, oauth_secret, jwt_signing
    rotated_at DATETIME NOT NULL,
    rotated_by TEXT,
    reason TEXT,
    FOREIGN KEY (did) REFERENCES accounts(did)
);
```

## Best Practices

1. **Rotation Schedule**
   - Rotate account signing keys annually
   - Rotate OAuth secrets quarterly
   - Rotate JWT signing keys annually
   - Rotate DPoP keys per-session

2. **Key Generation**
   - Use cryptographically secure random generation
   - Use appropriate key sizes (256-bit for EC)
   - Store keys securely
   - Never log key material

3. **Transition Period**
   - Keep old keys valid for 30 days
   - Publish new keys before activation
   - Activate new keys gradually
   - Remove old keys after expiration

4. **Monitoring**
   - Track key rotation events
   - Alert on rotation failures
   - Monitor key expiration
   - Audit key access

5. **Emergency Rotation**
   - Rotate immediately if key is compromised
   - Revoke old key immediately
   - Notify users of rotation
   - Update all systems

## Common Patterns

### Scheduled Rotation

```objc
// Rotate keys on a schedule
- (void)setupKeyRotationSchedule {
    // Check for keys that need rotation
    NSArray *keysNeedingRotation = [self getKeysNeedingRotation];
    
    for (NSDictionary *key in keysNeedingRotation) {
        NSError *error = nil;
        [self rotateAccountSigningKey:key[@"did"] error:&error];
    }
}
```

### Emergency Rotation

```objc
// Rotate immediately if key is compromised
- (BOOL)emergencyRotateKey:(NSString *)keyId forDid:(NSString *)did error:(NSError **)error {
    // 1. Revoke compromised key immediately
    [self revokeKey:keyId];
    
    // 2. Generate new key
    SecKeyRef newKey = [self generateSigningKey];
    NSString *newKeyId = [self generateKeyId];
    
    // 3. Activate new key immediately
    [self storeKey:newKey withId:newKeyId forDid:did status:@"active"];
    
    // 4. Update DID document
    [self updateDidDocumentWithNewKey:newKeyId forDid:did];
    
    // 5. Notify user
    [self notifyUserOfEmergencyRotation:did];
    
    return YES;
}
```

## See Also

- [JWT Tokens](jwt-tokens)
- [OAuth 2.0 with DPoP](oauth2-dpop)
- [TOTP and WebAuthn](totp-webauthn)
