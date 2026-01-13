# Chapter 7: CAR Files & Repository Commits

CAR (Content Addressable aRchive) files package content-addressed blocks for storage and transmission. Repository commits sign the current state of the MST, creating an auditable history. This chapter covers both.

## What is a CAR File?

A CAR file is a simple container format:

```
┌─────────────────┐
│  Header         │ ← Version + Root CID
├─────────────────┤
│  Block 1        │ ← CID + Data
├─────────────────┤
│  Block 2        │
├─────────────────┤
│  ...            │
└─────────────────┘
```

CAR files are used to:
- Export entire repositories
- Transfer data between PDSes
- Sync repository state
- Archive content

## CAR Format Structure

### Header Format (CARv1)

```
[Version: 4 bytes, big-endian]  = 0x00000001
[Root CID Length: 4 bytes, big-endian]
[Root CID Data: variable]
```

### Block Format

```
[Block Length: 4 bytes, big-endian]
[Block Data: variable]  ← Raw CBOR, CID computed from hash
```

## Implementing CAR Classes

### CARBlock: Individual Blocks

```objc
// CAR.h
@interface CARBlock : NSObject

@property (nonatomic, strong, readonly) CID *cid;
@property (nonatomic, strong, readonly) NSData *data;

+ (instancetype)blockWithCID:(CID *)cid data:(NSData *)data;

@end

// CAR.m
@implementation CARBlock

+ (instancetype)blockWithCID:(CID *)cid data:(NSData *)data {
    return [[self alloc] initWithCID:cid data:data];
}

- (instancetype)initWithCID:(CID *)cid data:(NSData *)data {
    self = [super init];
    if (self) {
        _cid = cid;
        _data = data;
    }
    return self;
}

@end
```

### CARWriter: Creating Archives

```objc
@interface CARWriter : NSObject

@property (nonatomic, strong, readonly) CID *rootCID;
@property (nonatomic, strong, readonly) NSMutableArray<CARBlock *> *blocks;

+ (instancetype)writerWithRootCID:(CID *)rootCID;
- (void)addBlock:(CARBlock *)block;
- (NSData *)serialize;

@end

@implementation CARWriter

- (NSData *)serialize {
    NSMutableData *data = [NSMutableData data];

    // Write version (CARv1 = 1)
    uint32_t version = OSSwapHostToBigInt32(1);
    [data appendBytes:&version length:4];

    // Write root CID (length-prefixed)
    NSData *rootCIDBytes = [self.rootCID bytes];
    uint32_t rootLen = OSSwapHostToBigInt32((uint32_t)rootCIDBytes.length);
    [data appendBytes:&rootLen length:4];
    [data appendData:rootCIDBytes];

    // Write blocks (length-prefixed)
    for (CARBlock *block in self.blocks) {
        NSData *blockData = block.data;
        uint32_t blockLen = OSSwapHostToBigInt32((uint32_t)blockData.length);
        [data appendBytes:&blockLen length:4];
        [data appendData:blockData];
    }

    return [data copy];
}

- (BOOL)writeToPath:(NSString *)path error:(NSError **)error {
    NSData *data = [self serialize];
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

@end
```

### CARReader: Parsing Archives

```objc
@interface CARReader : NSObject

@property (nonatomic, strong, readonly) CID *rootCID;
@property (nonatomic, strong, readonly) NSArray<CARBlock *> *blocks;

+ (nullable instancetype)readFromData:(NSData *)data error:(NSError **)error;
- (nullable CARBlock *)blockWithCID:(CID *)cid;

@end

@implementation CARReader

- (BOOL)parseData:(NSData *)data error:(NSError **)error {
    if (data.length < 8) {
        if (error) {
            *error = [NSError errorWithDomain:@"CAR" code:-1
                userInfo:@{NSLocalizedDescriptionKey: @"Data too short"}];
        }
        return NO;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;

    // Read version
    uint32_t version;
    memcpy(&version, bytes + offset, 4);
    version = OSSwapBigToHostInt32(version);
    offset += 4;

    if (version != 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"CAR" code:-2
                userInfo:@{NSLocalizedDescriptionKey: @"Unsupported CAR version"}];
        }
        return NO;
    }

    // Read root CID length
    uint32_t rootCidLength;
    memcpy(&rootCidLength, bytes + offset, 4);
    rootCidLength = OSSwapBigToHostInt32(rootCidLength);
    offset += 4;

    // Read root CID
    NSData *rootCidData = [data subdataWithRange:NSMakeRange(offset, rootCidLength)];
    offset += rootCidLength;
    _rootCID = [CID cidFromBytes:rootCidData];

    // Read blocks
    NSMutableArray<CARBlock *> *blocks = [NSMutableArray array];
    NSMutableDictionary<NSString *, CARBlock *> *index = [NSMutableDictionary dictionary];

    while (offset < data.length) {
        // Read block length
        uint32_t blockLen;
        memcpy(&blockLen, bytes + offset, 4);
        blockLen = OSSwapBigToHostInt32(blockLen);
        offset += 4;

        // Read block data
        NSData *blockData = [data subdataWithRange:NSMakeRange(offset, blockLen)];
        offset += blockLen;

        // Compute CID from hash
        CID *blockCID = [self computeBlockCID:blockData];
        if (blockCID) {
            CARBlock *block = [CARBlock blockWithCID:blockCID data:blockData];
            [blocks addObject:block];
            index[blockCID.stringValue] = block;
        }
    }

    _blocks = [blocks copy];
    _blockIndex = [index copy];
    return YES;
}

- (CID *)computeBlockCID:(NSData *)blockData {
    NSData *digest = [CID sha256Digest:blockData];
    return [CID cidWithDigest:digest codec:0x71];  // dag-cbor
}

- (CARBlock *)blockWithCID:(CID *)cid {
    return self.blockIndex[cid.stringValue];
}

@end
```

## Repository Commits

A commit represents a signed snapshot of the repository state:

```objc
// RepoCommit.h
@interface RepoCommit : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *did;         // Repository owner
@property (nonatomic, assign) NSInteger version;   // Commit format version
@property (nonatomic, strong) CID *dataCID;        // MST root CID
@property (nonatomic, copy) NSString *rev;         // Revision ID (TID)
@property (nonatomic, strong) CID *prevCID;        // Previous commit CID
@property (nonatomic, strong) NSData *signature;   // secp256k1 signature

+ (instancetype)createCommitWithDid:(NSString *)did
                              data:(CID *)dataCID
                               rev:(NSString *)rev
                              prev:(CID *)prevCID;

- (NSData *)serialize;
- (BOOL)signWithPrivateKey:(NSData *)privateKey error:(NSError **)error;
- (BOOL)verifySignatureWithPublicKey:(NSData *)publicKey error:(NSError **)error;

@end
```

### Commit Structure (CBOR)

The commit is serialized as DAG-CBOR:

```objc
- (NSData *)serialize {
    NSMutableDictionary<CBORValue *, CBORValue *> *dict = [NSMutableDictionary dictionary];
    
    // did: The repository owner's DID
    dict[[CBORValue textString:@"did"]] = [CBORValue textString:self.did];
    
    // version: Commit format version
    dict[[CBORValue textString:@"version"]] = [CBORValue unsignedInteger:self.version];
    
    // data: CID of the MST root (tag 42)
    if (self.dataCID) {
        NSMutableData *dataLink = [NSMutableData dataWithBytes:"\x00" length:1];
        [dataLink appendData:self.dataCID.bytes];
        dict[[CBORValue textString:@"data"]] = [CBORValue tag:42 
            value:[CBORValue byteString:dataLink]];
    }
    
    // rev: Revision TID
    dict[[CBORValue textString:@"rev"]] = [CBORValue textString:self.rev];
    
    // prev: Previous commit CID (null for first commit)
    if (self.prevCID) {
        NSMutableData *prevLink = [NSMutableData dataWithBytes:"\x00" length:1];
        [prevLink appendData:self.prevCID.bytes];
        dict[[CBORValue textString:@"prev"]] = [CBORValue tag:42 
            value:[CBORValue byteString:prevLink]];
    } else {
        dict[[CBORValue textString:@"prev"]] = [CBORValue nilValue];
    }
    
    // sig: Signature (excluded when computing hash for signing)
    if (self.signature) {
        dict[[CBORValue textString:@"sig"]] = [CBORValue byteString:self.signature];
    }
    
    return [[CBORValue map:dict] encode];
}
```

### Signing Commits

```objc
- (BOOL)signWithPrivateKey:(NSData *)privateKey error:(NSError **)error {
    // 1. Serialize without signature
    NSData *savedSig = self.signature;
    self.signature = nil;
    NSData *unsigned = [self serialize];
    
    // 2. Hash the unsigned commit
    NSData *hash = [CID rawSha256:unsigned];
    
    // 3. Sign with secp256k1
    self.signature = [Secp256k1 signHash:hash withPrivateKey:privateKey error:error];
    
    if (!self.signature) {
        self.signature = savedSig;  // Restore on failure
        return NO;
    }
    return YES;
}

- (BOOL)verifySignatureWithPublicKey:(NSData *)publicKey error:(NSError **)error {
    if (!self.signature) {
        if (error) {
            *error = [NSError errorWithDomain:@"RepoCommit" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"No signature"}];
        }
        return NO;
    }
    
    // Hash the unsigned data
    NSData *savedSig = self.signature;
    self.signature = nil;
    NSData *unsigned = [self serialize];
    self.signature = savedSig;
    
    NSData *hash = [CID rawSha256:unsigned];
    
    return [Secp256k1 verifySignature:self.signature 
                             forHash:hash 
                       withPublicKey:publicKey 
                               error:error];
}
```

## Practical Example: Export Repository

```objc
- (NSData *)exportRepositoryAsCAR {
    // 1. Get MST root and collect all nodes
    CID *rootCID = self.mst.rootCID;
    NSMutableArray<CARBlock *> *blocks = [NSMutableArray array];
    
    // 2. Serialize each MST node
    [self collectBlocks:self.mst.root into:blocks];
    
    // 3. Create commit
    NSString *rev = [TID tid].stringValue;
    RepoCommit *commit = [RepoCommit createCommitWithDid:self.did 
                                                   data:rootCID 
                                                    rev:rev 
                                                   prev:self.lastCommitCID];
    [commit signWithPrivateKey:self.signingKey error:nil];
    
    // 4. Add commit as a block
    NSData *commitData = [commit serialize];
    CID *commitCID = [CID cidWithDigest:[CID rawSha256:commitData] codec:0x71];
    [blocks insertObject:[CARBlock blockWithCID:commitCID data:commitData] atIndex:0];
    
    // 5. Write CAR
    CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
    for (CARBlock *block in blocks) {
        [writer addBlock:block];
    }
    
    return [writer serialize];
}

- (void)collectBlocks:(MSTNode *)node into:(NSMutableArray<CARBlock *> *)blocks {
    if (!node) return;
    
    // Serialize this node
    NSData *cbor = [node serializeToCBOR:self.cidCache];
    CID *nodeCID = [CID cidWithDigest:[CID rawSha256:cbor] codec:0x71];
    [blocks addObject:[CARBlock blockWithCID:nodeCID data:cbor]];
    
    // Recurse into children
    if (node.left) [self collectBlocks:node.left into:blocks];
    for (MSTNodeEntry *entry in node.entries) {
        if (entry.tree) [self collectBlocks:entry.tree into:blocks];
    }
}
```

## TIDs: Timestamp Identifiers

The `rev` field uses TIDs (Timestamp Identifiers) for sortable, unique revision IDs:

```objc
// Generate new revision
NSString *rev = [TID tid].stringValue;  // e.g., "3jwdwj2ctlk26"

// TIDs are:
// - 13 characters, base32-sortable
// - Timestamp in microseconds
// - Lexicographically sortable by time
```

---

## Common Mistakes

### Mistake 1: Forgetting to Include All Blocks

❌ **What people do:**
```objc
// WRONG: Only include the commit, not MST nodes
CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
[writer addBlock:[CARBlock blockWithCID:commitCID data:commitData]];
// Missing: MST root, intermediate nodes, record blocks
```

**Why this fails:**
- CAR files are self-contained archives
- Missing blocks make the archive useless for import
- Verifiers can't reconstruct the MST

✅ **Correct approach:**
```objc
// RIGHT: Traverse and include ALL blocks
CARWriter *writer = [CARWriter writerWithRootCID:commitCID];
[writer addBlock:[CARBlock blockWithCID:commitCID data:commitData]];
[self collectAllMSTBlocks:mstRoot into:writer];  // Recursively add all nodes
[self collectAllRecordBlocks:into:writer];        // Add all records too
```

### Mistake 2: Computing CIDs Incorrectly

❌ **What people do:**
```objc
// WRONG: Using raw codec for CBOR data
CID *nodeCID = [CID cidWithDigest:hash codec:0x55];  // 0x55 = raw
```

**Why this fails:**
- CBOR-encoded data should use dag-cbor codec (0x71)
- Raw codec (0x55) is for arbitrary binary blobs
- Other AT Protocol implementations won't recognize it

✅ **Correct approach:**
```objc
// RIGHT: Use dag-cbor codec for structured data
CID *nodeCID = [CID cidWithDigest:hash codec:0x71];  // 0x71 = dag-cbor
CID *blobCID = [CID cidWithDigest:blobHash codec:0x55];  // 0x55 = raw (for blobs)
```

### Mistake 3: Not Verifying CIDs Match Content

❌ **What people do:**
```objc
// WRONG: Trust CID without verification
CARBlock *block = [reader blockWithCID:requestedCID];
return block.data;  // What if content doesn't match CID?
```

**Why this fails:**
- Malicious archives could substitute block content
- CID verification is the core promise of content-addressing
- Data integrity not guaranteed

✅ **Correct approach:**
```objc
// RIGHT: Verify CID matches block content
CARBlock *block = [reader blockWithCID:requestedCID];
NSData *computedHash = [CID rawSha256:block.data];
CID *computedCID = [CID cidWithDigest:computedHash codec:0x71];

if (![computedCID isEqualToCID:requestedCID]) {
    NSLog(@"CID mismatch! Content may be corrupted.");
    return nil;
}
return block.data;
```

---

## Exercises

📝 **Exercise 1: CAR Validator**

Implement a method to validate a CAR file's integrity:

```objc
- (BOOL)validateCARFile:(NSData *)carData error:(NSError **)error;
// Should verify:
// - All blocks have correct CIDs
// - Root CID exists in blocks
// - No duplicate CIDs
```

- Hint: Compute CID for each block and compare to stored CID
- Bonus: Return detailed error with first invalid block

📝 **Exercise 2: Incremental CAR Export**

Create a method that exports only blocks changed since a given commit:

```objc
- (NSData *)exportChangesSince:(CID *)sinceCommitCID;
```

- Hint: Walk both MST versions and find differences
- Challenge: Handle the case where `sinceCommitCID` doesn't exist

📝 **Exercise 3: Commit Chain Walker**

Implement a method that walks backwards through commit history:

```objc
- (NSArray<RepoCommit *> *)getCommitHistory:(NSInteger)limit 
                            startingFrom:(CID *)headCID;
```

- Hint: Follow `prevCID` links
- Consider: What happens when you reach the genesis commit (`prev = null`)?

<details>
<summary>Solution</summary>

```objc
- (NSArray<RepoCommit *> *)getCommitHistory:(NSInteger)limit
                               startingFrom:(CID *)headCID {
    NSMutableArray<RepoCommit *> *history = [NSMutableArray array];
    CID *currentCID = headCID;
    
    while (currentCID && history.count < limit) {
        CARBlock *block = [self blockWithCID:currentCID];
        if (!block) break;
        
        RepoCommit *commit = [RepoCommit parseFromCBOR:block.data];
        [history addObject:commit];
        
        currentCID = commit.prevCID;  // May be nil for genesis
    }
    
    return [history copy];
}
```

</details>

---

## Summary

In this chapter, you learned:

- ✅ CAR file format structure
- ✅ Reading and writing CAR archives
- ✅ Repository commit structure
- ✅ Signing commits with secp256k1
- ✅ Linking commits to MST roots
- ✅ TIDs for revision tracking

## Key Takeaways

1. **CAR files are self-contained** - Include all blocks needed to reconstruct the data.

2. **Use correct codecs** - dag-cbor (0x71) for structured data, raw (0x55) for blobs.

3. **Always verify CIDs** - Content-addressing requires verification to be meaningful.

4. **Commits chain together** - Each commit references the previous via `prevCID`.

## Next Steps

Part II is complete! In **Part III: Cryptography & Identity**, we'll dive into **Chapter 8: Elliptic Curve Cryptography with secp256k1**.

---

**Files Referenced in This Chapter:**
- [CAR.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/CAR.h)
- [CAR.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/CAR.m)
- [RepoCommit.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/RepoCommit.h)
- [RepoCommit.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/RepoCommit.m)
- [TID.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Core/TID.h)
