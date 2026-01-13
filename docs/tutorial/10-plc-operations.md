# Chapter 10: PLC Operations & Account Creation

This chapter covers the PLC (Public Ledger of Credentials) operations that power AT Protocol account creation. We'll implement the genesis operation that creates a new `did:plc` identity.

## PLC Operation Structure

All PLC operations share a common structure:

```objc
// PLCOperation.h
@interface PLCOperation : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *type;
@property (nonatomic, strong) NSArray<NSString *> *rotationKeys;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *verificationMethods;
@property (nonatomic, strong) NSArray<NSString *> *alsoKnownAs;
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *services;
@property (nonatomic, copy, nullable) NSString *prev;
@property (nonatomic, copy, nullable) NSString *sig;

+ (instancetype)genesisOperationWithRotationKeys:(NSArray<NSString *> *)rotationKeys
                               verificationMethods:(NSDictionary<NSString *, NSString *> *)verificationMethods
                                      alsoKnownAs:(NSArray<NSString *> *)alsoKnownAs
                                         services:(NSDictionary<NSString *, NSDictionary *> *)services;

- (nullable NSData *)serializeForSigning:(NSError **)error;
- (nullable NSString *)computeCID:(NSError **)error;

@end
```

## Genesis Operation

The genesis operation creates a new DID. Its CID becomes the `did:plc` identifier:

```objc
+ (instancetype)genesisOperationWithRotationKeys:(NSArray<NSString *> *)rotationKeys
                               verificationMethods:(NSDictionary<NSString *, NSString *> *)verificationMethods
                                      alsoKnownAs:(NSArray<NSString *> *)alsoKnownAs
                                         services:(NSDictionary<NSString *, NSDictionary *> *)services {
    PLCOperation *op = [[PLCOperation alloc] init];
    op.type = @"plc_operation";
    op.rotationKeys = rotationKeys;
    op.verificationMethods = verificationMethods;
    op.alsoKnownAs = alsoKnownAs;
    op.services = services;
    op.prev = nil;  // Genesis has no previous operation
    return op;
}
```

### Operation Fields

| Field | Purpose |
|-------|---------|
| `type` | Operation type (`plc_operation` or `plc_tombstone`) |
| `rotationKeys` | Keys authorized to update/recover the DID |
| `verificationMethods` | Signing keys for the account |
| `alsoKnownAs` | Handle URIs (`at://handle`) |
| `services` | Service endpoints (PDS location) |
| `prev` | CID of previous operation (null for genesis) |
| `sig` | Signature from a rotation key |

## Serialization for Signing

Operations are serialized as DAG-CBOR (without the signature):

```objc
- (nullable NSData *)serializeForSigning:(NSError **)error {
    NSMutableDictionary<CBORValue *, CBORValue *> *dict = [NSMutableDictionary dictionary];
    
    // type
    dict[[CBORValue textString:@"type"]] = [CBORValue textString:self.type];
    
    // rotationKeys
    NSMutableArray<CBORValue *> *rkArray = [NSMutableArray array];
    for (NSString *key in self.rotationKeys) {
        [rkArray addObject:[CBORValue textString:key]];
    }
    dict[[CBORValue textString:@"rotationKeys"]] = [CBORValue array:rkArray];
    
    // verificationMethods
    NSMutableDictionary<CBORValue *, CBORValue *> *vmDict = [NSMutableDictionary dictionary];
    for (NSString *key in self.verificationMethods) {
        vmDict[[CBORValue textString:key]] = 
            [CBORValue textString:self.verificationMethods[key]];
    }
    dict[[CBORValue textString:@"verificationMethods"]] = [CBORValue map:vmDict];
    
    // alsoKnownAs
    NSMutableArray<CBORValue *> *akaArray = [NSMutableArray array];
    for (NSString *alias in self.alsoKnownAs) {
        [akaArray addObject:[CBORValue textString:alias]];
    }
    dict[[CBORValue textString:@"alsoKnownAs"]] = [CBORValue array:akaArray];
    
    // services
    NSMutableDictionary<CBORValue *, CBORValue *> *svcDict = [NSMutableDictionary dictionary];
    for (NSString *svcId in self.services) {
        NSDictionary *svc = self.services[svcId];
        NSMutableDictionary<CBORValue *, CBORValue *> *svcEntry = [NSMutableDictionary dictionary];
        for (NSString *key in svc) {
            svcEntry[[CBORValue textString:key]] = [CBORValue textString:svc[key]];
        }
        svcDict[[CBORValue textString:svcId]] = [CBORValue map:svcEntry];
    }
    dict[[CBORValue textString:@"services"]] = [CBORValue map:svcDict];
    
    // prev (null for genesis)
    if (self.prev) {
        dict[[CBORValue textString:@"prev"]] = [CBORValue textString:self.prev];
    } else {
        dict[[CBORValue textString:@"prev"]] = [CBORValue nilValue];
    }
    
    // Note: sig is NOT included when serializing for signing
    
    return [[CBORValue map:dict] encode];
}
```

## Computing the DID

The `did:plc` identifier is derived from the genesis operation's CID:

```objc
- (nullable NSString *)computeCID:(NSError **)error {
    NSData *unsigned = [self serializeForSigning:error];
    if (!unsigned) return nil;
    
    // Hash the unsigned operation
    NSData *hash = [CID rawSha256:unsigned];
    
    // Create CID with dag-cbor codec
    CID *cid = [CID cidWithDigest:hash codec:0x71];
    
    // Truncate to 24 characters and convert to base32
    NSString *cidString = cid.stringValue;
    // The DID is derived from the CID's multihash
    // did:plc uses a truncated base32 representation
    
    return [NSString stringWithFormat:@"did:plc:%@", 
        [[cidString substringFromIndex:1] substringToIndex:24]];
}
```

## Complete Account Creation Flow

```objc
- (NSString *)createAccountWithHandle:(NSString *)handle error:(NSError **)error {
    // 1. Generate key pairs
    DIDKey *signingKey = [DIDKey generateSecp256k1];
    DIDKey *recoveryKey = [DIDKey generateSecp256k1];
    
    // 2. Build genesis operation
    PLCOperation *genesis = [PLCOperation genesisOperationWithRotationKeys:
        @[recoveryKey.didKey, signingKey.didKey]
        verificationMethods:@{@"atproto": signingKey.didKey}
        alsoKnownAs:@[[NSString stringWithFormat:@"at://%@", handle]]
        services:@{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": self.pdsEndpoint
            }
        }
    ];
    
    // 3. Sign with rotation key
    NSData *unsigned = [genesis serializeForSigning:error];
    if (!unsigned) return nil;
    
    NSData *signature = [recoveryKey signData:unsigned error:error];
    if (!signature) return nil;
    
    genesis.sig = [self base64UrlEncode:signature];
    
    // 4. Compute DID
    NSString *did = [genesis computeCID:error];
    
    // 5. Store keys securely
    [self.keyStorage storePrivateKey:signingKey.privateKeyData forDID:did label:@"signing"];
    [self.keyStorage storePrivateKey:recoveryKey.privateKeyData forDID:did label:@"recovery"];
    
    // 6. Submit to PLC directory (or self-host)
    [self submitPLCOperation:genesis forDID:did];
    
    return did;
}
```

## Summary

In this chapter, you learned:

- ✅ PLC operation structure and fields
- ✅ Genesis operations for new accounts
- ✅ DAG-CBOR serialization for signing
- ✅ DID derivation from operation CID
- ✅ Complete account creation workflow

---

**Files Referenced in This Chapter:**
- [PLCOperation.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Identity/PLCOperation.h)
