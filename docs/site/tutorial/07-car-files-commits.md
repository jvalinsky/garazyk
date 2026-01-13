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

<script setup>
const carRunnerCode = `#import <Foundation/Foundation.h>

// --- Simplified CID ---
@interface CID : NSObject
@property NSData *digest;
@property NSUInteger codec;
+ (instancetype)cidWithDigest:(NSData *)d codec:(NSUInteger)c;
@end
@implementation CID
+ (instancetype)cidWithDigest:(NSData *)d codec:(NSUInteger)c {
    CID *o = [CID new]; o.digest = d; o.codec = c; return o;
}
- (NSData *)bytes {
    NSMutableData *d = [NSMutableData data];
    uint8_t ver = 1, codec = (uint8_t)self.codec, algo = 0x12, len = 32;
    [d appendBytes:&ver length:1]; [d appendBytes:&codec length:1];
    [d appendBytes:&algo length:1]; [d appendBytes:&len length:1];
    [d appendData:self.digest];
    return d;
}
@end

// --- Minimal CAR Implementation ---

void writeCAR(CID *root, NSDictionary *blocks, NSMutableData *outData) {
    // Header: Version 1 (LEB128=1), Root (CID)
    uint8_t header[] = { 0x01 }; // Mock
    
    printf("Writing CAR Header... (Simulated)\\n");
    printf("Block 0: Root CID %s\\n", root.description.UTF8String);
    
    for (NSString *key in blocks) {
        NSData *data = blocks[key];
        printf("Writing Block: %s (%lu bytes)\\n", key.UTF8String, data.length);
    }
}

int main() {
    @autoreleasepool {
        printf("--- CAR File Demo ---\\n");
        
        NSData *data1 = [@"Hello" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *data2 = [@"World" dataUsingEncoding:NSUTF8StringEncoding];
        
        NSMutableData *h1 = [NSMutableData dataWithLength:32]; ((char*)h1.bytes)[0] = 0xA1;
        CID *cid1 = [CID cidWithDigest:h1 codec:0x55];
        
        NSDictionary *blocks = @{@"bafy...1": data1, @"bafy...2": data2};
        NSMutableData *carFile = [NSMutableData data];
        writeCAR(cid1, blocks, carFile);
        
        printf("\\nDone. Created virtual CAR archive.\\n");
    }
    return 0;
}`;

const exercise1Code = `#import <Foundation/Foundation.h>

// --- Mock Classes ---
@interface CID : NSObject
@property NSString *str;
+ (instancetype)cidWithStr:(NSString *)s;
- (BOOL)isEqual:(id)object;
@end
@implementation CID
+ (instancetype)cidWithStr:(NSString *)s { CID *c=[CID new]; c.str=s; return c; }
- (BOOL)isEqual:(id)object { return [self.str isEqualToString:[object str]]; }
- (NSString *)description { return self.str; }
@end

@interface CARBlock : NSObject
@property CID *cid;
@property NSData *data;
+ (instancetype)block:(CID *)c data:(NSData *)d;
@end
@implementation CARBlock
+ (instancetype)block:(CID *)c data:(NSData *)d { CARBlock *b=[CARBlock new]; b.cid=c; b.data=d; return b; }
@end

// --- EXERCISE ---

BOOL validateCAR(NSArray<CARBlock *> *blocks, CID *rootCID) {
    // TODO: Implement validation logic
    // 1. Check if blocks are empty
    // 2. Verify rootCID exists in blocks
    
    if (blocks.count == 0) return NO;
    
    BOOL rootFound = NO;
    for (CARBlock *b in blocks) {
        if ([b.cid isEqual:rootCID]) {
            rootFound = YES;
        }
    }
    return rootFound;
}

// --- TEST ---

int main() {
    @autoreleasepool {
        CID *root = [CID cidWithStr:@"bafyroot"];
        CID *child = [CID cidWithStr:@"bafychild"];
        
        // Case 1: Valid
        NSArray *valid = @[
            [CARBlock block:root data:[@"root" dataUsingEncoding:NSUTF8StringEncoding]],
            [CARBlock block:child data:[@"child" dataUsingEncoding:NSUTF8StringEncoding]]
        ];
        printf("Test 1 (Valid): %s\\n", validateCAR(valid, root) ? "PASS" : "FAIL");
        
        // Case 2: No Root
        NSArray *bad = @[
            [CARBlock block:child data:[@"child" dataUsingEncoding:NSUTF8StringEncoding]]
        ];
        printf("Test 2 (No Root): %s\\n", !validateCAR(bad, root) ? "PASS" : "FAIL");
    }
    return 0;
}`;

const exercise2Code = `#import <Foundation/Foundation.h>

// --- Mocks ---
@interface CID : NSObject <NSCopying>
@property NSString *val;
+ (instancetype)c:(NSString *)v;
@end
@implementation CID
+ (instancetype)c:(NSString *)v { CID *x=[CID new]; x.val=v; return x; }
- (BOOL)isEqual:(id)o { return [self.val isEqualToString:[o val]]; }
- (NSUInteger)hash { return self.val.hash; }
- (id)copyWithZone:(NSZone *)z { return self; }
- (NSString *)description { return self.val; }
@end

@interface Node : NSObject
@property CID *cid;
@property NSArray<CID *> *children;
+ (instancetype)n:(CID *)c children:(NSArray *)ch;
@end
@implementation Node
+ (instancetype)n:(CID *)c children:(NSArray *)ch { Node *n=[Node new]; n.cid=c; n.children=ch; return n; }
@end

// Context: A global global store of blocks (Map CID -> Node)
static NSDictionary<CID *, Node *> *store;

// --- EXERCISE ---

// Goal: Traverse 'current' tree. Collect CIDs that are NOT in 'knownCIDs'.
// Recursively visit children. STOP if you hit a CID that is in 'knownCIDs'.

void collectNewBlocks(CID *current, NSSet<CID *> *knownCIDs, NSMutableSet<CID *> *result) {
    // TODO:
    // 1. If current is nil, return.
    // 2. If knownCIDs contains current, return (we found the cut-off point).
    // 3. If result already contains current, return (avoid cycles/dup work).
    // 4. Add current to result.
    // 5. Retrieve node from 'store' (using current as key).
    // 6. Recurse for each child.
    
    // START YOUR CODE HERE
    if (!current) return;
    
    // ...
}

// --- TEST ---

int main() {
    @autoreleasepool {
        // Setup Tree
        // oldRoot -> sharedChild
        // newRoot -> [sharedChild, newChild]
        
        CID *shared = [CID c:@"shared"];
        CID *oldRoot = [CID c:@"oldRoot"];
        CID *newRoot = [CID c:@"newRoot"];
        CID *newChild = [CID c:@"newChild"];
        
        store = @{
            shared: [Node n:shared children:@[]],
            oldRoot: [Node n:oldRoot children:@[shared]],
            newRoot: [Node n:newRoot children:@[shared, newChild]],
            newChild: [Node n:newChild children:@[]]
        };
        
        NSSet *known = [NSSet setWithObjects:oldRoot, shared, nil];
        NSMutableSet *result = [NSMutableSet set];
        
        collectNewBlocks(newRoot, known, result);
        
        printf("Found: %lu blocks\\n", result.count);
        // Expected: newRoot and newChild (2 blocks). shared is known.
        
        if (result.count == 2 && [result containsObject:newRoot] && [result containsObject:newChild]) {
            printf("PASS: Correctly identified new blocks.\\n");
        } else {
            printf("FAIL: Expected 2 (newRoot, newChild), got %lu\\n", result.count);
            for(CID *c in result) printf("- %s\\n", c.description.UTF8String);
        }
    }
    return 0;
}`;

const exercise3Code = `#import <Foundation/Foundation.h>

// --- Mocks ---
@interface CID : NSObject <NSCopying>
@property NSString *val;
+ (instancetype)c:(NSString *)v;
@end
@implementation CID
+ (instancetype)c:(NSString *)v { CID *x=[CID new]; x.val=v; return x; }
- (BOOL)isEqual:(id)o { return [self.val isEqualToString:[o val]]; }
- (NSString *)description { return self.val; }
- (id)copyWithZone:(NSZone *)z { return self; }
@end

@interface RepoCommit : NSObject
@property CID *dataCID;
@property CID *prevCID;
@property CID *commitCID; // The CID of this commit itself (mock)
+ (instancetype)commit:(CID *)prev;
@end
@implementation RepoCommit
+ (instancetype)commit:(CID *)prev { RepoCommit *c=[RepoCommit new]; c.prevCID=prev; return c; }
@end

// Context: Global store of commits (CID -> RepoCommit)
static NSDictionary<CID *, RepoCommit *> *commitStore;

RepoCommit * fetchCommit(CID *cid) {
    if (!cid) return nil;
    return commitStore[cid];
}

// --- EXERCISE ---

NSArray<RepoCommit *> * getCommitHistory(NSInteger limit, CID *headCID) {
    // TODO: Walk backwards from headCID for 'limit' steps or until null.
    // Use fetchCommit(cid) to get the commit object.
    // Return array of RepoCommit objects.
    
    // START YOUR CODE HERE
    if (!headCID) return @[];
    // ...
    
    return @[];
}

// --- TEST ---
int main() {
    @autoreleasepool {
        // Build chain: Genesis -> C1 -> C2 -> Head
        CID *genesisCID = [CID c:@"genesis"];
        CID *c1CID = [CID c:@"c1"];
        CID *c2CID = [CID c:@"c2"];
        CID *headCID = [CID c:@"head"];
        
        RepoCommit *genesis = [RepoCommit commit:nil]; genesis.commitCID = genesisCID;
        RepoCommit *c1 = [RepoCommit commit:genesisCID]; c1.commitCID = c1CID;
        RepoCommit *c2 = [RepoCommit commit:c1CID]; c2.commitCID = c2CID;
        RepoCommit *head = [RepoCommit commit:c2CID]; head.commitCID = headCID;
        
        commitStore = @{
            genesisCID: genesis,
            c1CID: c1,
            c2CID: c2,
            headCID: head
        };
        
        // Test 1: Full history (limit 10)
        NSArray *hist1 = getCommitHistory(10, headCID);
        printf("Test 1 (Full): Found %lu (Expected 4)\\n", hist1.count);
        
        // Test 2: Limit 2
        NSArray *hist2 = getCommitHistory(2, headCID);
        printf("Test 2 (Limit 2): Found %lu (Expected 2)\\n", hist2.count);
        
        if (hist1.count == 4 && hist2.count == 2) {
            printf("PASS: History walking works.\\n");
        } else {
            printf("FAIL: Counts incorrect.\\n");
        }
    }
    return 0;
}`;
</script>

<ObjcRunner :initialCode="carRunnerCode" />


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

Implement a method to validate a CAR file's integrity. We've provided a skeleton and some corrupted/valid test cases.



<ObjcRunner :initialCode="exercise1Code" />


📝 **Exercise 2: Incremental CAR Export**

Create a method that exports only blocks changed since a given commit:


```objc
- (NSData *)exportChangesSince:(CID *)sinceCommitCID;
```

- Hint: Walk both MST versions and find differences
- Challenge: Handle the case where `sinceCommitCID` doesn't exist

<ObjcRunner :initialCode="exercise2Code" />




📝 **Exercise 3: Commit Chain Walker**

Implement a method that walks backwards through commit history:

```objc
- (NSArray<RepoCommit *> *)getCommitHistory:(NSInteger)limit 
                            startingFrom:(CID *)headCID;
```

- Hint: Follow `prevCID` links
- Consider: What happens when you reach the genesis commit (`prev = null`)?

<ObjcRunner :initialCode="exercise3Code" />


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
