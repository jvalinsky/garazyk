// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Repository/CAR.h"
#import "Repository/MST.h"
#import "Repository/MSTWalker.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"
#import <CommonCrypto/CommonDigest.h>
#import <arpa/inet.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdatomic.h>

// objc/runtime.h does not declare these ARC runtime entry points; the atomic
// root publication path below (`-root`/`-setRoot:`) calls them directly to
// manage retain counts across the lock-free `atomic_load_explicit`/
// `atomic_exchange_explicit` boundary.
extern id objc_retain(id);
extern void objc_release(id);
extern id objc_autorelease(id);

#pragma mark - Internal Classes

@interface MSTNodeEntry ()
@property (nonatomic, strong, readwrite, nullable) MSTNode *internalTree;
@property (nonatomic, strong, readwrite, nullable) CID *treeCID;
@property (nonatomic, copy, readwrite) NSString *fullKey;
@end

@interface MSTNode ()
@property (nonatomic, assign, readwrite) uint32_t level;
@property (nonatomic, strong, readwrite, nullable) MSTNode *internalLeft;
@property (nonatomic, strong, readwrite, nullable) CID *leftCID;
@property (nonatomic, strong, readwrite, nullable) CID *originalCID;
@property (nonatomic, strong, readwrite, nullable) NSData *originalCBOR;
@property (nonatomic, strong, readwrite) NSMutableArray<MSTNodeEntry *> *internalEntries;
- (instancetype)initWithLevel:(uint32_t)level;
- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache;
- (void)split:(NSString *)key left:(MSTNode **)leftOut right:(MSTNode **)rightOut;
- (MSTNode *)trim;
- (NSInteger)binarySearchIndexForKey:(NSString *)key;
- (MSTNode *)subtreeAtIndex:(NSInteger)idx;
@end

@implementation MSTEntry

+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID {
    return [self entryWithKey:key valueCID:valueCID subKey:nil];
}

+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID subKey:(NSString *)subKey {
    return [[self alloc] initWithKey:key valueCID:valueCID subKey:subKey];
}

- (instancetype)initWithKey:(NSString *)key valueCID:(CID *)valueCID subKey:(NSString *)subKey {
    self = [super init];
    if (self) {
        _key = [key copy];
        _valueCID = valueCID;
        _subKey = [subKey copy];
    }
    return self;
}

- (NSData *)keyBytes {
    return [self.key dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSUInteger)keyLength {
    return [self keyBytes].length;
}

- (NSData *)serialize {
    NSMutableData *data = [NSMutableData data];

    uint16_t keyLen = htons((uint16_t)[self keyLength]);
    [data appendBytes:&keyLen length:2];

    NSData *keyData = [self keyBytes];
    [data appendData:keyData];

    NSData *cidBytes = [self.valueCID bytes];
    uint16_t cidLen = htons((uint16_t)cidBytes.length);
    [data appendBytes:&cidLen length:2];
    [data appendData:cidBytes];

    return [data copy];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[MSTEntry allocWithZone:zone] initWithKey:self.key valueCID:self.valueCID subKey:self.subKey];
}

@end

#pragma mark - MSTDiffOperation

@implementation MSTDiffOperation

+ (instancetype)addOperationWithKey:(NSString *)key currentCID:(CID *)currentCID {
    MSTDiffOperation *op = [[MSTDiffOperation alloc] init];
    op.key = key;
    op.type = MSTDiffOperationTypeAdd;
    op.previousCID = nil;
    op.currentCID = currentCID;
    return op;
}

+ (instancetype)updateOperationWithKey:(NSString *)key previousCID:(CID *)previousCID currentCID:(CID *)currentCID {
    MSTDiffOperation *op = [[MSTDiffOperation alloc] init];
    op.key = key;
    op.type = MSTDiffOperationTypeUpdate;
    op.previousCID = previousCID;
    op.currentCID = currentCID;
    return op;
}

+ (instancetype)deleteOperationWithKey:(NSString *)key previousCID:(CID *)previousCID {
    MSTDiffOperation *op = [[MSTDiffOperation alloc] init];
    op.key = key;
    op.type = MSTDiffOperationTypeDelete;
    op.previousCID = previousCID;
    op.currentCID = nil;
    return op;
}

@end

#pragma mark - MSTNodeEntry

@implementation MSTNodeEntry

+ (instancetype)entryWithPrefixLen:(NSUInteger)prefixLen
                          keySuffix:(NSData *)keySuffix
                              value:(CID *)value
                              tree:(CID *)tree {
    MSTNodeEntry *entry = [[MSTNodeEntry alloc] init];
    entry.prefixLen = prefixLen;
    entry.keySuffix = keySuffix;
    entry.value = value;
    entry.tree = tree;
    return entry;
}

- (instancetype)initWithKey:(NSString *)key value:(CID *)value tree:(MSTNode *)tree {
    self = [super init];
    if (self) {
        _value = value;
        _internalTree = tree;
        _fullKey = [key copy];
    }
    return self;
}

- (NSData *)serialize {
    NSMutableData *data = [NSMutableData data];

    uint8_t p = (uint8_t)self.prefixLen;
    [data appendBytes:&p length:1];

    uint16_t kLen = htons((uint16_t)self.keySuffix.length);
    [data appendBytes:&kLen length:2];
    [data appendData:self.keySuffix];

    NSData *vBytes = [self.value bytes];
    uint16_t vLen = htons((uint16_t)vBytes.length);
    [data appendBytes:&vLen length:2];
    [data appendData:vBytes];

    CID *tCID = self.tree;
    uint16_t tLen = tCID ? htons((uint16_t)[tCID bytes].length) : 0;
    [data appendBytes:&tLen length:2];
    if (tCID) {
        [data appendData:[tCID bytes]];
    }

    return data;
}

@end

#pragma mark - MSTNode implementation

@implementation MSTNode

- (instancetype)initWithLevel:(uint32_t)level {
    self = [super init];
    if (self) {
        _level = level;
        _internalEntries = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithLevel:(uint32_t)level left:(MSTNode *)left entries:(NSArray<MSTNodeEntry *> *)entries {
    self = [self initWithLevel:level];
    if (self) {
        _internalLeft = left;
        [_internalEntries addObjectsFromArray:entries];
    }
    return self;
}

- (NSArray<MSTNodeEntry *> *)entries {
    return [self.internalEntries copy];
}

- (NSInteger)binarySearchIndexForKey:(NSString *)key {
    NSInteger left = 0, right = (NSInteger)self.internalEntries.count;
    while (left < right) {
        NSInteger mid = left + (right - left) / 2;
        NSComparisonResult cmp = [self.internalEntries[mid].fullKey compare:key];
        if (cmp == NSOrderedAscending) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    return left;
}

- (MSTNode *)subtreeAtIndex:(NSInteger)idx {
    if (idx == 0) {
        return self.internalLeft;
    }
    if (idx - 1 < (NSInteger)self.internalEntries.count) {
        return self.internalEntries[idx - 1].internalTree;
    }
    return nil;
}

- (CID *)left {
    return [self.internalLeft getCID:[NSMapTable strongToStrongObjectsMapTable]];
}

- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache {
    if (!self) return nil;
    CID *cached = [cache objectForKey:self];
    if (cached) return cached;
    
    // Preserve original CID if the node hasn't been modified
    if (self.originalCID) {
        [cache setObject:self.originalCID forKey:self];
        return self.originalCID;
    }
    
    NSData *cbor = [self serializeToCBOR:cache];
    CID *cid = [CID cidWithDigest:[CID sha256Digest:cbor] codec:0x71];
    [cache setObject:cid forKey:self];
    return cid;
}

- (NSData *)serializeToCBOR:(NSMapTable<MSTNode *, CID *> *)cache {
    // Preserve original CBOR if the node hasn't been modified
    if (self.originalCBOR) return self.originalCBOR;

    NSMutableArray<CBORValue *> *entriesCBOR = [NSMutableArray array];
    NSData *prevKeyData = [NSData data];
    
    for (MSTNodeEntry *entry in self.internalEntries) {
        NSData *fullKeyData = [entry.fullKey dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger p = 0;
        NSUInteger minLen = MIN(prevKeyData.length, fullKeyData.length);
        
        const uint8_t *prevBytes = prevKeyData.bytes;
        const uint8_t *currBytes = fullKeyData.bytes;
        
        for (NSUInteger i = 0; i < minLen; i++) {
            if (prevBytes[i] == currBytes[i]) {
                p++;
            } else {
                break;
            }
        }
        
        NSData *kSuffix = [fullKeyData subdataWithRange:NSMakeRange(p, fullKeyData.length - p)];
        
        // TreeEntry spec order: k, p, t, v
        NSMutableDictionary<CBORValue *, CBORValue *> *dict = [NSMutableDictionary dictionary];
        dict[[CBORValue textString:@"k"]] = [CBORValue byteString:kSuffix];
        dict[[CBORValue textString:@"p"]] = [CBORValue unsignedInteger:p];
        
        if (entry.internalTree) {
            CID *tCID = [entry.internalTree getCID:cache];
            NSMutableData *tData = [NSMutableData dataWithBytes:"\x00" length:1];
            [tData appendData:tCID.bytes];
            dict[[CBORValue textString:@"t"]] = [CBORValue tag:42 value:[CBORValue byteString:tData]];
        } else if (entry.treeCID) {
            NSMutableData *tData = [NSMutableData dataWithBytes:"\x00" length:1];
            [tData appendData:entry.treeCID.bytes];
            dict[[CBORValue textString:@"t"]] = [CBORValue tag:42 value:[CBORValue byteString:tData]];
        } else {
            dict[[CBORValue textString:@"t"]] = [CBORValue nilValue];
        }
        
        NSMutableData *vData = [NSMutableData dataWithBytes:"\x00" length:1];
        [vData appendData:entry.value.bytes];
        dict[[CBORValue textString:@"v"]] = [CBORValue tag:42 value:[CBORValue byteString:vData]];
        
        [entriesCBOR addObject:[CBORValue map:dict]];
        prevKeyData = fullKeyData;
    }
    
    // NodeData spec order: e, l
    NSMutableDictionary<CBORValue *, CBORValue *> *nodeDict = [NSMutableDictionary dictionary];
    nodeDict[[CBORValue textString:@"e"]] = [CBORValue array:entriesCBOR];
    if (self.internalLeft) {
        CID *lCID = [self.internalLeft getCID:cache];
        NSMutableData *lData = [NSMutableData dataWithBytes:"\x00" length:1];
        [lData appendData:lCID.bytes];
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue tag:42 value:[CBORValue byteString:lData]];
    } else if (self.leftCID) {
        NSMutableData *lData = [NSMutableData dataWithBytes:"\x00" length:1];
        [lData appendData:self.leftCID.bytes];
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue tag:42 value:[CBORValue byteString:lData]];
    } else {
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue nilValue];
    }
    
    return [[CBORValue map:nodeDict] encode];
}

- (void)split:(NSString *)key left:(MSTNode **)leftOut right:(MSTNode **)rightOut {
    NSInteger idx = [self binarySearchIndexForKey:key];
    
    NSArray *leftData = [self.internalEntries subarrayWithRange:NSMakeRange(0, idx)];
    NSArray *rightData = [self.internalEntries subarrayWithRange:NSMakeRange(idx, self.internalEntries.count - idx)];
    
    MSTNode *leftNode = [[MSTNode alloc] initWithLevel:self.level left:self.internalLeft entries:leftData];
    MSTNode *rightNode = [[MSTNode alloc] initWithLevel:self.level left:nil entries:rightData];
    
    if (idx == 0) {
        if (self.internalLeft) {
            MSTNode *subL = nil;
            MSTNode *subR = nil;
            [self.internalLeft split:key left:&subL right:&subR];
            leftNode.internalLeft = subL;
            rightNode.internalLeft = subR;
        }
    } else {
        MSTNodeEntry *lastInLeft = leftData.lastObject;
        if (lastInLeft.internalTree) {
            NSMutableArray *nLeftEntries = [leftData mutableCopy];
            [nLeftEntries removeLastObject];
            
            MSTNode *subL = nil;
            MSTNode *subR = nil;
            [lastInLeft.internalTree split:key left:&subL right:&subR];
            
            MSTNodeEntry *newLast = [[MSTNodeEntry alloc] initWithKey:lastInLeft.fullKey value:lastInLeft.value tree:subL];
            [nLeftEntries addObject:newLast];
            leftNode.internalEntries = nLeftEntries;
            rightNode.internalLeft = subR;
        }
    }
    
    *leftOut = [leftNode trim];
    *rightOut = [rightNode trim];
}

- (MSTNode *)trim {
    if (self.internalEntries.count == 0) {
        return [self.internalLeft trim];
    }
    return self;
}

#pragma mark - Public Interface Methods

- (NSData *)serialize {
    // Use CBOR serialization for the canonical format
    return [self serializeToCBOR:[NSMapTable strongToStrongObjectsMapTable]];
}

- (NSData *)computeHash {
    // Compute SHA-256 of the CBOR-serialized node
    NSData *cbor = [self serialize];
    if (!cbor || cbor.length == 0) return [NSData data];
    
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cbor.bytes, (CC_LONG)cbor.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

- (void)setNodeHash:(CID *)hash {
    // Store the computed hash (used for caching)
    // Note: In our implementation, hashes are computed on-demand via getCID:
    // Kept for API compatibility; current code paths do not persist nodeHash here.
}

- (NSArray<MSTEntry *> *)fullEntries {
    // Return all key-value entries in this node as MSTEntry objects
    NSMutableArray<MSTEntry *> *entries = [NSMutableArray array];
    for (MSTNodeEntry *nodeEntry in self.internalEntries) {
        MSTEntry *entry = [MSTEntry entryWithKey:nodeEntry.fullKey valueCID:nodeEntry.value];
        [entries addObject:entry];
    }
    return [entries copy];
}

- (instancetype)initWithKind:(MSTNodeKind)kind entries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left {
    // Legacy init - convert CID left to node (not fully supported, use initWithLevel:left:entries: instead)
    uint32_t level = (kind == MSTNodeKindLeaf) ? 0 : 1;
    return [self initWithLevel:level left:nil entries:entries];
}

+ (instancetype)leafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries {
    return [[self alloc] initWithLevel:0 left:nil entries:entries];
}

+ (instancetype)nonLeafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left {
    // Note: left is a CID, but our internal representation uses MSTNode
    // This factory method creates a non-leaf without resolving the CID
    return [[self alloc] initWithLevel:1 left:nil entries:entries];
}

@end

#pragma mark - MST implementation

@interface MST ()
{
    /// C11 atomic storage backing the `root` property. Updated only via
    /// `atomic_store_explicit` (release) on the publish path (-put:/-delete:)
    /// and read via `atomic_load_explicit` (acquire) on every walker entry.
    /// Per-instance (every MST has its own cell); no global lock.
    _Atomic(MSTNode *) _rootAtomic;
}
@property (strong, readwrite, nullable) MSTNode *root;
@property (nonatomic, copy, readwrite) NSData *emptyTreeHash;
@property (nonatomic, copy, nullable) MSTBlockProvider blockProvider;
/// Per-instance cache of lazy-resolved MSTNode subtrees indexed by their CID.
/// Populated by -collectProofNodes:on-the-fly during proof collection so
/// repeated proofs for the same key skip redundant deserialize work.
/// Invalidated by -put:/-delete: when the published tree changes; the cache
/// only holds subtrees consistent with the **currently-published** root.
///
/// This side-table completes the atomic-publish copy-on-write invariant:
/// lazy resolution no longer writes back into the published
/// MSTNode._internalLeft / MSTNodeEntry.internalTree ivars. Read and
/// written under @synchronized(self) for thread-safe publish-during-proof.
@property (nonatomic, strong, nullable)
    NSMutableDictionary<CID *, MSTNode *> *lazySubtreeCache;
/// Recency order for the bounded lazy-subtree cache (least recent first).
@property (nonatomic, strong, nullable) NSMutableArray<CID *> *lazySubtreeCacheOrder;
- (BOOL)enumerateStreamableNode:(MSTNode *)node
                          cache:(NSMapTable<MSTNode *, CID *> *)cache
                     addedCIDs:(NSMutableSet<NSString *> *)addedCIDs
                          block:(BOOL (^)(CID *cid, NSData *data, NSError **error))block
                recordProvider:(nullable MSTBlockProvider)recordProvider
                          error:(NSError **)error;
@end

/// Sync 1.1 "Streamable CAR Block Ordering" feature flag. ON by default —
/// Sync 1.1 has promoted from draft to required, so the PDS repo export
/// paths now use the pre-order / depth-first enumerator with interleaved
/// record blocks (`enumerateStreamableCARBlocksUsingBlock:recordProvider:`).
/// MST block retrieval via `enumerateNodeCARBlocksUsingBlock:` is unchanged
/// and unaffected by this flag — it is the legacy BFS walker retained for
/// callers that explicitly want node-only emission.
///
/// C11 `<stdatomic.h>` acquire/release ordering: concurrent reads observe
/// the latest published value; concurrent read-write pairs serialize
/// correctly. Production callers may flip the flag from any thread.
static atomic_bool gMSTStreamableCARBlockOrderingEnabled = true;
static const NSUInteger kMSTLazySubtreeCacheCapacity = 256;

@implementation MST

- (instancetype)initWithRootNode:(nullable MSTNode *)rootNode {
    self = [super init];
    if (self) {
        // `atomic_store_explicit` is a raw C11 primitive: it does not go
        // through ARC's write barrier, so it never retains the value it
        // stores. `_rootAtomic` must therefore be manually retained before
        // publication (see `-root`/`-setRoot:`/`-dealloc` for the matching
        // manual release sites) — otherwise the initial node can be
        // deallocated out from under the cell as soon as this local's own
        // strong reference goes out of scope, leaving a dangling pointer.
        MSTNode *initialRoot = rootNode ?: [[MSTNode alloc] initWithLevel:0];
        objc_retain(initialRoot);
        // Initialize the atomic root cell with release ordering so any later
        // acquire-load observes a fully published tree.
        atomic_store_explicit(&_rootAtomic, initialRoot, memory_order_release);
        _emptyTreeHash = [self computeEmptyTreeHash];
    }
    return self;
}

/// Manually releases the final published root, mirroring the manual
/// `objc_retain` calls in `-initWithRootNode:`/`-setRoot:`. `_rootAtomic`
/// is opaque to ARC (see above), so ARC's synthesized `-dealloc` cannot
/// see or release its contents on its own.
- (void)dealloc {
    MSTNode *finalRoot =
        atomic_load_explicit(&_rootAtomic, memory_order_acquire);
    objc_release(finalRoot);
}

#pragma mark - Atomic Root Publication (C11 stdatomic)

/// Thread safety of root publication. The MST object's mutable state is
/// the `root` pointer, published through a per-instance `_Atomic(MSTNode *)`
/// cell. Writers (e.g., `-put:`, `-delete:`) construct a new immutable tree
/// from the existing root via copy-on-write (`addRecursive:`/
/// `deleteRecursive:` return newly allocated MSTNodes; existing nodes
/// are never mutated in place) and atomically publish via
/// `atomic_store_explicit` (release). Readers (every walker entry point
/// in this file) load the root via `atomic_load_explicit` (acquire) once
/// at the top and operate on the captured snapshot — a concurrent writer
/// cannot disturb the walker's view because the OLD tree remains valid
/// as long as the walker's autoreleased reference to it is in scope, and
/// the NEW tree is produced from FRESHLY ALLOCATED nodes that share no
/// mutable state with the OLD tree. ARC reclamation of intermediate
/// trees is bounded by refcount: as soon as no walker holds a strong
/// reference, ARC releases the old root and its immutable children.
/// There is no global lock; the protocol is fully per-instance and
/// lock-free. New walker entry points MUST capture `self.root` into a
/// `__strong` local before traversing; the documented audit point is
/// `enumerateStreamableCARBlocksUsingBlock:` and `enumerateNodeCARBlocksUsingBlock:`.

/// C11 acquire-load on `_rootAtomic`, then autoreleased through
/// `objc_retain`/`objc_autorelease` so callers receive the standard
/// property-getter reference contract under ARC. Walking callers bind the
/// return to a `MSTNode *` local, which ARC retains for the walker's
/// duration; concurrent writer activity does not disturb the captured
/// snapshot because the old tree remains valid as long as any caller
/// holds a strong reference.
- (nullable MSTNode *)root {
    MSTNode *currentRoot =
        atomic_load_explicit(&_rootAtomic, memory_order_acquire);
    if (currentRoot) {
        // Match Apple's synthesized-getter contract: retain + autorelease so
        // the returned reference is consumed correctly under ARC without
        // requiring callers to declare a `__strong` qualifier.
        return objc_autorelease(objc_retain(currentRoot));
    }
    return nil;
}

/// C11 acq_rel exchange on `_rootAtomic`, manually retaining `newRoot`
/// before publication and releasing the previous value after — raw
/// `atomic_exchange_explicit` bypasses ARC's write barrier entirely, so
/// neither side of this swap is retained/released automatically. A
/// `__strong`-qualified parameter only guarantees `newRoot` is valid for
/// the duration of this call, not that anything retains it on our behalf
/// once it is copied into non-ARC-visible storage.
/// Pairs with `-root`'s acquire-load so the synchronization is fully
/// sequenced: stores that happened before the publish are visible to any
/// load that observes the new pointer.
- (void)setRoot:(nullable MSTNode *)newRoot {
    objc_retain(newRoot);
    MSTNode *oldRoot =
        atomic_exchange_explicit(&_rootAtomic,
                                 newRoot,
                                 memory_order_acq_rel);
    objc_release(oldRoot);
}

- (instancetype)initWithRootCID:(CID *)rootCID {
    return [self initWithRootNode:nil];
}

- (instancetype)init {
    return [self initWithRootNode:nil];
}

- (NSData *)computeEmptyTreeHash {
    NSDictionary *dict = @{
        [CBORValue textString:@"e"]: [CBORValue array:@[]],
        [CBORValue textString:@"l"]: [CBORValue nilValue]
    };
    NSData *cbor = [[CBORValue map:dict] encode];
    return [CID sha256Digest:cbor];
}

- (CID *)rootCID {
    return [self.root getCID:[NSMapTable strongToStrongObjectsMapTable]];
}

+ (uint32_t)keyDepthFromBytes:(const uint8_t *)bytes length:(NSUInteger)len {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes, (CC_LONG)len, hash);

    uint32_t depth = 0;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t byte = hash[i];
        if (byte == 0) {
            depth += 4;
            continue;
        }
        if ((byte & 0xC0) == 0) {
            depth++;
            if ((byte & 0x30) == 0) {
                depth++;
                if ((byte & 0x0C) == 0) {
                    depth++;
                }
            }
        }
        break;
    }
    return depth;
}

+ (NSUInteger)keyDepthString:(NSString *)key {
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    return [self keyDepthFromBytes:keyData.bytes length:keyData.length];
}

+ (uint32_t)keyDepth:(NSString *)key {
    return [self keyDepthString:key];
}

+ (NSUInteger)keyDepthBytes:(NSData *)keyBytes {
    return [self keyDepthFromBytes:keyBytes.bytes length:keyBytes.length];
}

- (nullable CID *)get:(NSString *)key {
    return [self get:key subKey:nil];
}

- (nullable CID *)get:(NSString *)key subKey:(NSString *)subKey {
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    return [self getRecursive:self.root key:fullKey];
}

- (CID *)getRecursive:(MSTNode *)node key:(NSString *)key {
    if (!node) return nil;
    NSInteger idx = [node binarySearchIndexForKey:key];
    
    if (idx < (NSInteger)node.internalEntries.count && [node.internalEntries[idx].fullKey isEqualToString:key]) {
        return node.internalEntries[idx].value;
    }
    
    MSTNode *subtree = [node subtreeAtIndex:idx];
    return [self getRecursive:subtree key:key];
}

- (void)put:(NSString *)key valueCID:(CID *)valueCID {
    [self put:key valueCID:valueCID subKey:nil];
}

- (void)put:(NSString *)key valueCID:(CID *)valueCID subKey:(NSString *)subKey {
    // Invalidate any cached lazy-resolved subtrees before publishing a new
    // root. The cache holds subtrees consistent with the *previous* published
    // root; without invalidation, future proof queries would walk OLD data.
    // Synchronization is non-blocking — publish first, then invalidate —
    // because the cache contents are immutable (deserialized MSTNodes never
    // change), so a stale read after the publish is observable but never
    // corrupting.
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    uint32_t depth = [MST keyDepth:fullKey];
    self.root = [self addRecursive:self.root key:fullKey value:valueCID depth:depth];
    @synchronized(self) {
        if (self.lazySubtreeCache) {
            [self.lazySubtreeCache removeAllObjects];
            [self.lazySubtreeCacheOrder removeAllObjects];
        }
    }
}

- (MSTNode *)addRecursive:(MSTNode *)node key:(NSString *)key value:(CID *)value depth:(uint32_t)depth {
    if (!node) node = [[MSTNode alloc] initWithLevel:0];
    
    if (depth > node.level) {
        MSTNode *splitLeft = nil;
        MSTNode *splitRight = nil;
        [node split:key left:&splitLeft right:&splitRight];
        
        uint32_t currentLevel = node.level;
        MSTNode *left = splitLeft;
        MSTNode *right = splitRight;
        
        for (uint32_t i = currentLevel + 1; i < depth; i++) {
            if (left) left = [[MSTNode alloc] initWithLevel:i left:left entries:@[]];
            if (right) right = [[MSTNode alloc] initWithLevel:i left:right entries:@[]];
        }
        
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] initWithKey:key value:value tree:right];
        return [[MSTNode alloc] initWithLevel:depth left:left entries:@[newEntry]];
    }
    
    NSInteger idx = [node binarySearchIndexForKey:key];
    
    if (idx < (NSInteger)node.internalEntries.count && [node.internalEntries[idx].fullKey isEqualToString:key]) {
        MSTNodeEntry *oldEntry = node.internalEntries[idx];
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] initWithKey:key value:value tree:oldEntry.internalTree];
        NSMutableArray *newEntries = [node.internalEntries mutableCopy];
        newEntries[idx] = newEntry;
        return [[MSTNode alloc] initWithLevel:node.level left:node.internalLeft entries:newEntries];
    }
    
    if (depth == node.level) {
        MSTNode *subtree = [node subtreeAtIndex:idx];
        MSTNode *splitLeft = nil;
        MSTNode *splitRight = nil;
        if (subtree) {
            [subtree split:key left:&splitLeft right:&splitRight];
        }
        
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] initWithKey:key value:value tree:splitRight];
        NSMutableArray *newEntries = [node.internalEntries mutableCopy];
        [newEntries insertObject:newEntry atIndex:idx];
        
        MSTNode *leftToUse = node.internalLeft;
        if (idx == 0) {
            leftToUse = splitLeft;
        } else {
            MSTNodeEntry *prevEntry = newEntries[idx-1];
            MSTNodeEntry *updatedPrev = [[MSTNodeEntry alloc] initWithKey:prevEntry.fullKey value:prevEntry.value tree:splitLeft];
            newEntries[idx-1] = updatedPrev;
        }
        return [[MSTNode alloc] initWithLevel:node.level left:leftToUse entries:newEntries];
    }
    
    MSTNode *subtree = (idx == 0) ? node.internalLeft : node.internalEntries[idx-1].internalTree;
    if (!subtree) subtree = [[MSTNode alloc] initWithLevel:node.level - 1];
    MSTNode *newSubtree = [self addRecursive:subtree key:key value:value depth:depth];
    
    NSMutableArray *newEntries = [node.internalEntries mutableCopy];
    MSTNode *leftToUse = node.internalLeft;
    if (idx == 0) {
        leftToUse = newSubtree;
    } else {
        MSTNodeEntry *prevEntry = newEntries[idx-1];
        MSTNodeEntry *updatedPrev = [[MSTNodeEntry alloc] initWithKey:prevEntry.fullKey value:prevEntry.value tree:newSubtree];
        newEntries[idx-1] = updatedPrev;
    }
    return [[MSTNode alloc] initWithLevel:node.level left:leftToUse entries:newEntries];
}

- (void)delete:(NSString *)key {
    [self delete:key subKey:nil];
}

- (void)delete:(NSString *)key subKey:(NSString *)subKey {
    // See -put:subKey: for the lazySubtreeCache invalidation rationale.
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    self.root = [self deleteRecursive:self.root key:fullKey];
    if (!self.root) self.root = [[MSTNode alloc] initWithLevel:0];
    @synchronized(self) {
        if (self.lazySubtreeCache) {
            [self.lazySubtreeCache removeAllObjects];
            [self.lazySubtreeCacheOrder removeAllObjects];
        }
    }
}

- (MSTNode *)deleteRecursive:(MSTNode *)node key:(NSString *)key {
    if (!node) return nil;
    NSInteger idx = [node binarySearchIndexForKey:key];
    
    if (idx < (NSInteger)node.internalEntries.count && [node.internalEntries[idx].fullKey isEqualToString:key]) {
        MSTNodeEntry *entryToDelete = node.internalEntries[idx];
        MSTNode *leftSubtree = [node subtreeAtIndex:idx];
        MSTNode *rightSubtree = entryToDelete.internalTree;
        
        MSTNode *merged = [self merge:leftSubtree and:rightSubtree];
        
        NSMutableArray *newEntries = [node.internalEntries mutableCopy];
        [newEntries removeObjectAtIndex:idx];
        
        MSTNode *leftToUse = node.internalLeft;
        if (idx == 0) {
            leftToUse = merged;
        } else {
            MSTNodeEntry *prevEntry = newEntries[idx-1];
            MSTNodeEntry *updatedPrev = [[MSTNodeEntry alloc] initWithKey:prevEntry.fullKey value:prevEntry.value tree:merged];
            newEntries[idx-1] = updatedPrev;
        }
        MSTNode *newNode = [[MSTNode alloc] initWithLevel:node.level left:leftToUse entries:newEntries];
        return [newNode trim];
    }
    
    MSTNode *subtree = [node subtreeAtIndex:idx];
    if (subtree) {
        MSTNode *newSubtree = [self deleteRecursive:subtree key:key];
        NSMutableArray *newEntries = [node.internalEntries mutableCopy];
        
        MSTNode *leftToUse = node.internalLeft;
        if (idx == 0) {
            leftToUse = newSubtree;
        } else {
            MSTNodeEntry *prevEntry = newEntries[idx-1];
            MSTNodeEntry *updatedPrev = [[MSTNodeEntry alloc] initWithKey:prevEntry.fullKey value:prevEntry.value tree:newSubtree];
            newEntries[idx-1] = updatedPrev;
        }
        MSTNode *newNode = [[MSTNode alloc] initWithLevel:node.level left:leftToUse entries:newEntries];
        return [newNode trim];
    }
    return node;
}

- (MSTNode *)merge:(MSTNode *)left and:(MSTNode *)right {
    if (!left) return right;
    if (!right) return left;

    // Handle level mismatch by wrapping the lower-level subtree in
    // passthrough nodes (nodes with only a left pointer, no entries)
    // until it matches the higher level. This preserves all entries.
    if (left.level < right.level) {
        while (left.level < right.level) {
            left = [[MSTNode alloc] initWithLevel:left.level + 1 left:left entries:@[]];
        }
    } else if (right.level < left.level) {
        while (right.level < left.level) {
            right = [[MSTNode alloc] initWithLevel:right.level + 1 left:right entries:@[]];
        }
    }
    
    MSTNodeEntry *lastInLeft = left.internalEntries.lastObject;
    if (lastInLeft.internalTree && right.internalLeft) {
        MSTNode *mergedSubtree = [self merge:lastInLeft.internalTree and:right.internalLeft];
        NSMutableArray *newEntries = [NSMutableArray array];
        for (NSUInteger i = 0; i < left.internalEntries.count - 1; i++) {
            [newEntries addObject:left.internalEntries[i]];
        }
        MSTNodeEntry *updatedLast = [[MSTNodeEntry alloc] initWithKey:lastInLeft.fullKey value:lastInLeft.value tree:mergedSubtree];
        [newEntries addObject:updatedLast];
        [newEntries addObjectsFromArray:right.internalEntries];
        return [[MSTNode alloc] initWithLevel:left.level left:left.internalLeft entries:newEntries];
    } else {
        NSMutableArray *newEntries = [left.internalEntries mutableCopy];
        MSTNode *newLeftChild = nil;
        if (right.internalLeft) {
            if (lastInLeft) {
                MSTNodeEntry *updatedLast = [[MSTNodeEntry alloc] initWithKey:lastInLeft.fullKey value:lastInLeft.value tree:right.internalLeft];
                newEntries[newEntries.count-1] = updatedLast;
            } else {
                // Empty-entries edge case: capture the recursive merge result
                // into a local; do NOT mutate `left.internalLeft` here.
                // `left` may be a published subtree of self.root during
                // -delete: (this path is reached when the entry being deleted
                // is in a node with zero sibling entries and the substitute
                // subtree has a left pointer). A concurrent walker reading
                // `left.internalLeft` would otherwise see a non-atomic
                // in-place pointer write and observe a torn MST. The atomic
                // publish protocol depends on copy-on-write — see MST.h
                // documentation for the thread-safety invariant.
                newLeftChild = [self merge:left.internalLeft and:right.internalLeft];
            }
        }
        [newEntries addObjectsFromArray:right.internalEntries];
        return [[MSTNode alloc] initWithLevel:left.level
                                         left:newLeftChild ?: left.internalLeft
                                     entries:newEntries];
    }
}

- (NSArray<MSTEntry *> *)allEntries {
    NSMutableArray<MSTEntry *> *result = [NSMutableArray array];
    [self walk:self.root callback:^(MSTNodeEntry *entry) {
        [result addObject:[MSTEntry entryWithKey:entry.fullKey valueCID:entry.value]];
    }];
    return result;
}

- (void)walk:(MSTNode *)node callback:(void(^)(MSTNodeEntry *))callback {
    if (!node) return;
    if (node.internalLeft) [self walk:node.internalLeft callback:callback];
    for (MSTNodeEntry *entry in node.internalEntries) {
        callback(entry);
        if (entry.internalTree) [self walk:entry.internalTree callback:callback];
    }
}

- (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix {
    NSMutableArray<MSTEntry *> *result = [NSMutableArray array];
    [self walk:self.root callback:^(MSTNodeEntry *entry) {
        if ([entry.fullKey hasPrefix:prefix]) {
            [result addObject:[MSTEntry entryWithKey:entry.fullKey valueCID:entry.value]];
        }
    }];
    return result;
}

- (NSData *)exportCAR {
    if (!self.root) return nil;

    CID *rootCID = self.rootCID;
    if (!rootCID) return nil;

    CARWriter *writer = [CARWriter writerWithRootCID:rootCID];

    BOOL traversed = [self enumerateNodeCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **error) {
        (void)error;
        [writer addBlock:[CARBlock blockWithCID:cid data:data]];
        return YES;
    } error:nil];
    if (!traversed) {
        return nil;
    }

    return [writer serialize];
}

- (BOOL)enumerateNodeCARBlocksUsingBlock:(BOOL (^)(CID *cid, NSData *data, NSError **error))block
                                   error:(NSError **)error {
    if (!block) {
        return YES;
    }
    // Capture the root atomically once. The autoreleased reference is bound
    // to -rootSnapshot for the rest of the walk; ARC retains the published
    // root so a concurrent -put:/-delete: cannot tear the tree this BFS is
    // observing (copy-on-write invariant on addRecursive:/deleteRecursive:).
    MSTNode * __strong rootSnapshot = self.root;
    if (!rootSnapshot) {
        return YES;
    }

    NSMapTable<MSTNode *, CID *> *cache = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableArray<MSTNode *> *queue = [NSMutableArray arrayWithObject:rootSnapshot];
    NSMutableSet<NSString *> *addedCIDs = [NSMutableSet set];
    NSUInteger queueHead = 0;

    while (queueHead < queue.count) {
        MSTNode *node = queue[queueHead++];

        CID *cid = [node getCID:cache];
        if (!cid) {
            continue;
        }

        NSString *cidString = cid.stringValue ?: @"";
        if ([addedCIDs containsObject:cidString]) {
            continue;
        }
        [addedCIDs addObject:cidString];

        NSData *data = [node serializeToCBOR:cache];
        if (!data) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.mst"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize MST node"}];
            }
            return NO;
        }

        NSError *callbackError = nil;
        if (!block(cid, data, &callbackError)) {
            if (error && callbackError) {
                *error = callbackError;
            }
            return NO;
        }

        if (node.internalLeft) {
            [queue addObject:node.internalLeft];
        }

        for (MSTNodeEntry *entry in node.internalEntries) {
            if (entry.internalTree) {
                [queue addObject:entry.internalTree];
            }
        }
    }

    return YES;
}
- (NSData *)serializeToCBOR {
    return [self.root serializeToCBOR:[NSMapTable strongToStrongObjectsMapTable]];
}
- (nullable NSData *)serializeNode:(MSTNode *)node {
    if (!node) return nil;
    return [node serializeToCBOR:[NSMapTable strongToStrongObjectsMapTable]];
}

+ (nullable instancetype)deserializeFromCBOR:(NSData *)data {
    return [self deserializeFromCBOR:data blockProvider:nil];
}

+ (nullable instancetype)deserializeFromCBOR:(NSData *)data
                               blockProvider:(nullable MSTBlockProvider)blockProvider {
    if (!data) return nil;
    
    MSTNode *rootNode = [self deserializeNodeFromCBOR:data blockProvider:blockProvider];
    if (!rootNode) return nil;
    
    return [[MST alloc] initWithRootNode:rootNode];
}

+ (nullable MSTNode *)deserializeNodeFromCBOR:(NSData *)data
                                blockProvider:(nullable MSTBlockProvider)blockProvider {
    MSTNode *node = [self deserializeNodeFromCBOR:data];
    if (!node) return nil;
    
    // Recursively resolve left subtree CID
    if (node.leftCID && blockProvider) {
        NSData *leftData = blockProvider(node.leftCID);
        if (leftData) {
            node.internalLeft = [self deserializeNodeFromCBOR:leftData blockProvider:blockProvider];
        }
    }
    
    // Recursively resolve each entry's subtree CID
    for (NSUInteger i = 0; i < node.internalEntries.count; i++) {
        MSTNodeEntry *entry = node.internalEntries[i];
        if (entry.treeCID && blockProvider) {
            NSData *childData = blockProvider(entry.treeCID);
            if (childData) {
                entry.internalTree = [self deserializeNodeFromCBOR:childData blockProvider:blockProvider];
            }
        }
    }
    
    return node;
}

+ (nullable MSTNode *)deserializeNodeFromCBOR:(NSData *)data {
    CBORValue *rootValue = [CBORValue decode:data];
    if (!rootValue || rootValue.type != CBORTypeMap) {
        return nil;
    }

    CBORValue *entriesValue = rootValue.map[[CBORValue textString:@"e"]];
    NSArray<CBORValue *> *entriesArray = (entriesValue && entriesValue.type == CBORTypeArray)
        ? entriesValue.array
        : @[];

    NSMutableArray<MSTNodeEntry *> *entries = [NSMutableArray array];
    NSData *prevKeyData = [NSData data];

    for (CBORValue *entryMap in entriesArray) {
        if (entryMap.type != CBORTypeMap) {
            continue;
        }

        CBORValue *keyValue = entryMap.map[[CBORValue textString:@"k"]];
        NSData *suffixData = keyValue.byteString ?: [NSData data];

        CBORValue *prefixValue = entryMap.map[[CBORValue textString:@"p"]];
        NSUInteger prefixLen = prefixValue.unsignedInteger.unsignedIntegerValue;
        NSUInteger safePrefixLen = MIN(prefixLen, prevKeyData.length);
        
        NSMutableData *fullKeyData = [NSMutableData dataWithData:[prevKeyData subdataWithRange:NSMakeRange(0, safePrefixLen)]];
        [fullKeyData appendData:suffixData];
        
        NSString *fullKey = [[NSString alloc] initWithData:fullKeyData encoding:NSUTF8StringEncoding] ?: @"";
        prevKeyData = [fullKeyData copy];

        CBORValue *valueTag = entryMap.map[[CBORValue textString:@"v"]];
        CBORValue *valueBytes = valueTag.tagValue;
        if (!valueBytes || valueBytes.type != CBORTypeByteString || valueBytes.byteString.length <= 1) {
            continue;
        }

        NSData *vCidBytes = [valueBytes.byteString subdataWithRange:NSMakeRange(1, valueBytes.byteString.length - 1)];
        CID *valueCID = [CID cidFromBytes:vCidBytes];
        if (!valueCID) {
            continue;
        }

        CID *treeCID = nil;
        CBORValue *treeTag = entryMap.map[[CBORValue textString:@"t"]];
        if (treeTag && treeTag.type == CBORTypeTag) {
            NSData *tCidBytes = treeTag.tagValue.byteString;
            if (tCidBytes.length > 1) {
                treeCID = [CID cidFromBytes:[tCidBytes subdataWithRange:NSMakeRange(1, tCidBytes.length - 1)]];
            }
        }

        MSTNodeEntry *entry = [[MSTNodeEntry alloc] initWithKey:fullKey value:valueCID tree:nil];
        entry.treeCID = treeCID;
        [entries addObject:entry];
    }

    CID *leftCID = nil;
    CBORValue *leftTag = rootValue.map[[CBORValue textString:@"l"]];
    if (leftTag && leftTag.type == CBORTypeTag) {
        NSData *lCidBytes = leftTag.tagValue.byteString;
        if (lCidBytes.length > 1) {
            leftCID = [CID cidFromBytes:[lCidBytes subdataWithRange:NSMakeRange(1, lCidBytes.length - 1)]];
        }
    }

    // Determine level based on the first key's depth (approximation for deserialized nodes)
    uint32_t level = 0;
    if (entries.count > 0) {
        level = [MST keyDepth:entries[0].fullKey];
    }

    MSTNode *node = [[MSTNode alloc] initWithLevel:level left:nil entries:entries];
    node.leftCID = leftCID;
    node.originalCBOR = data;
    node.originalCID = [CID cidWithDigest:[CID sha256Digest:data] codec:0x71];
    return node;
}

#pragma mark - Visualization & Export

- (nullable NSDictionary *)toJSON {
    if (!self.root) return nil;

    // Cache for CIDs
    NSMapTable<MSTNode *, CID *> *cache = [NSMapTable strongToStrongObjectsMapTable];

    // Compute root CID
    CID *rootCID = [self.root getCID:cache];
    if (!rootCID) return nil;

    // BFS traversal to collect all nodes
    NSMutableArray *queue = [NSMutableArray arrayWithObject:self.root];
    NSMutableSet<NSString *> *addedCIDs = [NSMutableSet set];
    NSMutableArray *nodesArray = [NSMutableArray array];
    NSUInteger entryCount = 0;
    NSUInteger maxDepth = 0;

    NSUInteger queueHead = 0;
    while (queueHead < queue.count) {
        MSTNode *node = queue[queueHead++];

        CID *cid = [node getCID:cache];
        if (!cid) continue;

        NSString *cidString = [cid stringValue];
        if ([addedCIDs containsObject:cidString]) continue;
        [addedCIDs addObject:cidString];

        // Track max depth
        if (node.level > maxDepth) {
            maxDepth = node.level;
        }

        // Build node dictionary
        NSMutableDictionary *nodeDict = [NSMutableDictionary dictionary];
        nodeDict[@"cid"] = cidString;
        nodeDict[@"level"] = @(node.level);
        nodeDict[@"kind"] = (node.level == 0) ? @"leaf" : @"non-leaf";

        // Build entries array
        NSMutableArray *entriesArray = [NSMutableArray array];
        for (MSTNodeEntry *entry in node.internalEntries) {
            entryCount++;
            NSMutableDictionary *entryDict = [NSMutableDictionary dictionary];
            entryDict[@"fullKey"] = entry.fullKey ?: @"";
            entryDict[@"value"] = [entry.value stringValue] ?: @"";

            if (entry.tree) {
                entryDict[@"tree"] = [entry.tree stringValue];
            }

            [entriesArray addObject:entryDict];
        }
        nodeDict[@"entries"] = entriesArray;

        // Add left pointer
        if (node.internalLeft) {
            CID *leftCID = [node.internalLeft getCID:cache];
            if (leftCID) {
                nodeDict[@"left"] = [leftCID stringValue];
            }
        }

        [nodesArray addObject:nodeDict];

        // Enqueue children
        if (node.internalLeft) {
            [queue addObject:node.internalLeft];
        }

        for (MSTNodeEntry *entry in node.internalEntries) {
            if (entry.internalTree) {
                [queue addObject:entry.internalTree];
            }
        }
    }

    return @{
        @"rootCID": [rootCID stringValue],
        @"nodeCount": @(nodesArray.count),
        @"entryCount": @(entryCount),
        @"maxDepth": @(maxDepth),
        @"nodes": nodesArray
    };
}

- (NSDictionary *)getStatistics {
    if (!self.root) {
        return @{
            @"nodeCount": @0,
            @"entryCount": @0,
            @"leafNodeCount": @0,
            @"internalNodeCount": @0,
            @"maxDepth": @0,
            @"avgDepth": @0.0,
            @"rootCID": @"",
            @"balanceFactor": @0.0
        };
    }

    // Cache for CIDs
    NSMapTable<MSTNode *, CID *> *cache = [NSMapTable strongToStrongObjectsMapTable];
    CID *rootCID = [self.root getCID:cache];

    // BFS traversal to collect statistics
    NSMutableArray *queue = [NSMutableArray arrayWithObject:self.root];
    NSMutableSet<NSString *> *visited = [NSMutableSet set];

    NSUInteger nodeCount = 0;
    NSUInteger entryCount = 0;
    NSUInteger leafNodeCount = 0;
    NSUInteger internalNodeCount = 0;
    NSUInteger maxDepth = 0;
    NSUInteger totalDepth = 0;

    NSUInteger queueHead = 0;
    while (queueHead < queue.count) {
        MSTNode *node = queue[queueHead++];

        CID *cid = [node getCID:cache];
        if (!cid) continue;

        NSString *cidString = [cid stringValue];
        if ([visited containsObject:cidString]) continue;
        [visited addObject:cidString];

        nodeCount++;
        totalDepth += node.level;

        if (node.level == 0) {
            leafNodeCount++;
        } else {
            internalNodeCount++;
        }

        if (node.level > maxDepth) {
            maxDepth = node.level;
        }

        entryCount += node.internalEntries.count;

        // Enqueue children
        if (node.internalLeft) {
            [queue addObject:node.internalLeft];
        }

        for (MSTNodeEntry *entry in node.internalEntries) {
            if (entry.internalTree) {
                [queue addObject:entry.internalTree];
            }
        }
    }

    double avgDepth = nodeCount > 0 ? (double)totalDepth / nodeCount : 0.0;

    // Balance factor: ratio of actual depth to ideal depth (log2(nodeCount))
    // Closer to 1.0 means better balance
    double idealDepth = nodeCount > 1 ? log2(nodeCount) : 0.0;
    double balanceFactor = idealDepth > 0 ? avgDepth / idealDepth : 1.0;

    return @{
        @"nodeCount": @(nodeCount),
        @"entryCount": @(entryCount),
        @"leafNodeCount": @(leafNodeCount),
        @"internalNodeCount": @(internalNodeCount),
        @"maxDepth": @(maxDepth),
        @"avgDepth": @(avgDepth),
        @"rootCID": rootCID ? [rootCID stringValue] : @"",
        @"balanceFactor": @(balanceFactor)
    };
}

- (nullable NSString *)toDOT {
    if (!self.root) return nil;

    // Cache for CIDs
    NSMapTable<MSTNode *, CID *> *cache = [NSMapTable strongToStrongObjectsMapTable];
    CID *rootCID = [self.root getCID:cache];
    if (!rootCID) return nil;

    NSMutableString *dot = [NSMutableString stringWithString:@"digraph MST {\n"];
    [dot appendString:@"  rankdir=TB;\n"];
    [dot appendString:@"  node [shape=box, style=filled];\n\n"];

    // BFS traversal
    NSMutableArray *queue = [NSMutableArray arrayWithObject:self.root];
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    NSMutableArray *edges = [NSMutableArray array];

    // Color palette for levels (blue gradient)
    NSArray *colors = @[@"#e3f2fd", @"#90caf9", @"#42a5f5", @"#1e88e5", @"#1565c0"];

    NSUInteger queueHead = 0;
    while (queueHead < queue.count) {
        MSTNode *node = queue[queueHead++];

        CID *cid = [node getCID:cache];
        if (!cid) continue;

        NSString *cidString = [cid stringValue];
        NSString *nodeID = [cidString substringToIndex:MIN(12, cidString.length)];

        if ([visited containsObject:cidString]) continue;
        [visited addObject:cidString];

        // Node label and color
        NSString *color = colors[MIN(node.level, colors.count - 1)];
        NSString *kind = (node.level == 0) ? @"leaf" : @"internal";
        [dot appendFormat:@"  \"%@\" [label=\"L%u\\n%@\\n%lu entries\", fillcolor=\"%@\"];\n",
         nodeID, node.level, kind, (unsigned long)node.internalEntries.count, color];

        // Add left edge
        if (node.internalLeft) {
            CID *leftCID = [node.internalLeft getCID:cache];
            if (leftCID) {
                NSString *leftID = [[leftCID stringValue] substringToIndex:MIN(12, [[leftCID stringValue] length])];
                [edges addObject:[NSString stringWithFormat:@"  \"%@\" -> \"%@\" [label=\"left\", color=\"#666666\"];\n",
                                nodeID, leftID]];
                [queue addObject:node.internalLeft];
            }
        }

        // Add entry tree edges
        for (NSUInteger i = 0; i < node.internalEntries.count; i++) {
            MSTNodeEntry *entry = node.internalEntries[i];
            if (entry.internalTree) {
                CID *treeCID = [entry.internalTree getCID:cache];
                if (treeCID) {
                    NSString *treeID = [[treeCID stringValue] substringToIndex:MIN(12, [[treeCID stringValue] length])];
                    NSString *entryKey = entry.fullKey ?: @"";
                    if (entryKey.length > 20) {
                        entryKey = [[entryKey substringToIndex:17] stringByAppendingString:@"..."];
                    }
                    [edges addObject:[NSString stringWithFormat:@"  \"%@\" -> \"%@\" [label=\"%@\", color=\"#1976d2\"];\n",
                                    nodeID, treeID, entryKey]];
                    [queue addObject:entry.internalTree];
                }
            }
        }
    }

    // Append all edges
    [dot appendString:@"\n"];
    for (NSString *edge in edges) {
        [dot appendString:edge];
    }

    [dot appendString:@"}\n"];

    return [dot copy];
}

#pragma mark - Depth-First Traversal

- (void)enumerateNodesDepthFirstUsingBlock:(void (^)(MSTNode *node, NSUInteger depth, BOOL *stop))block {
    // Snapshot root atomically; do not re-read self.root (a writer could
    // interleave between the guard and the recursive call and publish a
    // new tree, leaving the two reads to observe different roots).
    MSTNode * __strong rootSnapshot = self.root;
    if (!rootSnapshot || !block) return;
    BOOL stop = NO;
    [self enumerateNodesDepthFirst:rootSnapshot depth:0 block:block stop:&stop];
}

- (void)enumerateNodesDepthFirst:(MSTNode *)node
                           depth:(NSUInteger)depth
                           block:(void (^)(MSTNode *, NSUInteger, BOOL *))block
                            stop:(BOOL *)stop {
    if (!node || *stop) return;

    block(node, depth, stop);
    if (*stop) return;

    // Visit left subtree first (keys < first entry)
    if (node.internalLeft) {
        [self enumerateNodesDepthFirst:node.internalLeft
                                 depth:depth + 1
                                 block:block
                                  stop:stop];
        if (*stop) return;
    }

    // Visit each entry's subtree in key order
    for (MSTNodeEntry *entry in node.internalEntries) {
        if (entry.internalTree) {
            [self enumerateNodesDepthFirst:entry.internalTree
                                     depth:depth + 1
                                     block:block
                                      stop:stop];
            if (*stop) return;
        }
    }
}

#pragma mark - Diff Operations

- (NSArray<MSTDiffOperation *> *)diffFrom:(nullable MST *)oldTree {
    NSMutableDictionary<NSString *, CID *> *oldEntriesByKey = [NSMutableDictionary dictionary];
    for (MSTEntry *entry in [oldTree allEntries]) {
        if (entry.key.length > 0 && entry.valueCID) {
            oldEntriesByKey[entry.key] = entry.valueCID;
        }
    }

    NSMutableDictionary<NSString *, CID *> *newEntriesByKey = [NSMutableDictionary dictionary];
    for (MSTEntry *entry in [self allEntries]) {
        if (entry.key.length > 0 && entry.valueCID) {
            newEntriesByKey[entry.key] = entry.valueCID;
        }
    }

    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:oldEntriesByKey.allKeys];
    [keys addObjectsFromArray:newEntriesByKey.allKeys];
    NSArray<NSString *> *sortedKeys = [[keys allObjects] sortedArrayUsingSelector:@selector(compare:)];

    NSMutableArray<MSTDiffOperation *> *operations = [NSMutableArray array];
    for (NSString *key in sortedKeys) {
        CID *oldCID = oldEntriesByKey[key];
        CID *newCID = newEntriesByKey[key];

        if (!oldCID && newCID) {
            [operations addObject:[MSTDiffOperation addOperationWithKey:key currentCID:newCID]];
        } else if (oldCID && !newCID) {
            [operations addObject:[MSTDiffOperation deleteOperationWithKey:key previousCID:oldCID]];
        } else if (oldCID && newCID && ![oldCID isEqualToCID:newCID]) {
            [operations addObject:[MSTDiffOperation updateOperationWithKey:key
                                                               previousCID:oldCID
                                                                currentCID:newCID]];
        }
    }

    return [operations copy];
}

/// Consume all remaining entries from walker as additions
- (void)consumeWalker:(MSTWalker *)walker
   asAddIntoOperations:(NSMutableArray<MSTDiffOperation *> *)operations {
    while (!walker.status.isDone) {
        MSTNodeEntry *entry = walker.status.currentEntry;
        if (entry != nil && !walker.status.isTreeNode) {
            [operations addObject:[MSTDiffOperation addOperationWithKey:entry.fullKey
                                                             currentCID:entry.value]];
        }
        [walker advance];
    }
}

/// Consume all remaining entries from walker as deletions
- (void)consumeWalker:(MSTWalker *)walker
asDeleteIntoOperations:(NSMutableArray<MSTDiffOperation *> *)operations {
    while (!walker.status.isDone) {
        MSTNodeEntry *entry = walker.status.currentEntry;
        if (entry != nil && !walker.status.isTreeNode) {
            [operations addObject:[MSTDiffOperation deleteOperationWithKey:entry.fullKey
                                                               previousCID:entry.value]];
        }
        [walker advance];
    }
}

/// Collect all entries from node as additions (used when old tree is nil)
- (void)collectAllEntriesFromNode:(MSTNode *)node
               asAddIntoOperations:(NSMutableArray<MSTDiffOperation *> *)operations {
    if (!node) return;
    
    if (node.internalLeft) {
        [self collectAllEntriesFromNode:node.internalLeft
                     asAddIntoOperations:operations];
    }
    
    for (MSTNodeEntry *entry in node.internalEntries) {
        if (entry.fullKey.length > 0 && entry.value) {
            [operations addObject:[MSTDiffOperation addOperationWithKey:entry.fullKey
                                                             currentCID:entry.value]];
        }
        if (entry.internalTree) {
            [self collectAllEntriesFromNode:entry.internalTree
                         asAddIntoOperations:operations];
        }
    }
}

/// Collect all entries from node as deletions (used when new tree is nil)
- (void)collectAllEntriesFromNode:(MSTNode *)node
            asDeleteIntoOperations:(NSMutableArray<MSTDiffOperation *> *)operations {
    if (!node) return;
    
    if (node.internalLeft) {
        [self collectAllEntriesFromNode:node.internalLeft
                  asDeleteIntoOperations:operations];
    }
    
    for (MSTNodeEntry *entry in node.internalEntries) {
        if (entry.fullKey.length > 0 && entry.value) {
            [operations addObject:[MSTDiffOperation deleteOperationWithKey:entry.fullKey
                                                               previousCID:entry.value]];
        }
        if (entry.internalTree) {
            [self collectAllEntriesFromNode:entry.internalTree
                      asDeleteIntoOperations:operations];
        }
    }
}

#pragma mark - Proof Operations

- (nullable NSArray<MSTNode *> *)getProofNodesForKey:(NSString *)key {
    return [self getProofNodesForKey:key blockProvider:nil];
}

- (nullable NSArray<MSTNode *> *)getProofNodesForKey:(NSString *)key
                                       blockProvider:(nullable MSTBlockProvider)blockProvider {
    if (!self.root) return nil;
    
    NSMutableArray<MSTNode *> *proofPath = [NSMutableArray array];
    [self collectProofNodes:self.root
                     forKey:key
                       into:proofPath
              blockProvider:blockProvider ?: self.blockProvider];
    
    return proofPath.count > 0 ? [proofPath copy] : nil;
}

- (BOOL)collectProofNodes:(MSTNode *)node
                   forKey:(NSString *)key
                     into:(NSMutableArray<MSTNode *> *)path
            blockProvider:(nullable MSTBlockProvider)blockProvider {
    if (!node) return NO;
    
    [path addObject:node];
    
    // Binary search for key position
    NSInteger idx = [node binarySearchIndexForKey:key];
    
    // Check if we found the key at this level
    if (idx < (NSInteger)node.internalEntries.count && [node.internalEntries[idx].fullKey isEqualToString:key]) {
        return YES; // Found the key
    }
    
    // Recurse into appropriate subtree
    MSTNode *subtree = nil;
    CID *subtreeCID = nil;
    
    if (idx == 0) {
        subtree = node.internalLeft;
        subtreeCID = node.leftCID;
    } else {
        MSTNodeEntry *entry = node.internalEntries[idx - 1];
        subtree = entry.internalTree;
        subtreeCID = entry.treeCID;
    }
    
    // Lazy-load subtree if needed. Read through the per-instance
    // lazySubtreeCache side-table (thread-safe under @synchronized(self)).
    // The published node's _internalLeft / MSTNodeEntry.internalTree ivars
    // MUST NOT be written back here: doing so mutates a published subtree
    // and races the atomic-publish copy-on-write invariant. The side-table
    // cache is invalidated by -put:/-delete: so it stays consistent with
    // the currently-published root; see the lazySubtreeCache doc block on
    // the MST () class extension.
    if (!subtree && subtreeCID && blockProvider) {
        @synchronized(self) {
            subtree = [self.lazySubtreeCache objectForKey:subtreeCID];
            if (subtree) {
                [self.lazySubtreeCacheOrder removeObject:subtreeCID];
                [self.lazySubtreeCacheOrder addObject:subtreeCID];
            }
        }
        if (subtree) {
            return [self collectProofNodes:subtree forKey:key into:path blockProvider:blockProvider];
        }
        NSData *data = blockProvider(subtreeCID);
        if (!data) return NO;
        MSTNode *resolved = [MST deserializeNodeFromCBOR:data];
        if (!resolved) return NO;
        // Write only if absent so contending walkers don't redundantly
        // re-deserialize the same subtreeCID. The first inserter wins;
        // semantically equivalent subtrees (same data → same CIDs) are
        // interchangeable, so overwriting would only waste work.
        @synchronized(self) {
            if (!self.lazySubtreeCache) {
                self.lazySubtreeCache = [NSMutableDictionary dictionary];
                self.lazySubtreeCacheOrder = [NSMutableArray array];
            }
            MSTNode *existing = self.lazySubtreeCache[subtreeCID];
            if (!existing) {
                if (self.lazySubtreeCacheOrder.count >= kMSTLazySubtreeCacheCapacity) {
                    CID *leastRecentCID = self.lazySubtreeCacheOrder.firstObject;
                    if (leastRecentCID) {
                        [self.lazySubtreeCache removeObjectForKey:leastRecentCID];
                        [self.lazySubtreeCacheOrder removeObjectAtIndex:0];
                    }
                }
                self.lazySubtreeCache[subtreeCID] = resolved;
                [self.lazySubtreeCacheOrder addObject:subtreeCID];
                subtree = resolved;
            } else {
                [self.lazySubtreeCacheOrder removeObject:subtreeCID];
                [self.lazySubtreeCacheOrder addObject:subtreeCID];
                subtree = existing;
            }
        }
    }

    if (subtree) {
        return [self collectProofNodes:subtree forKey:key into:path blockProvider:blockProvider];
    }
    // Key not found — remove this node from path.
    [path removeLastObject];
    return NO;
}

#pragma mark - Sync 1.1 Streamable CAR Block Ordering

+ (BOOL)streamableCARBlockOrderingEnabled {
    return atomic_load_explicit(&gMSTStreamableCARBlockOrderingEnabled,
                                memory_order_acquire) ? YES : NO;
}

+ (void)setStreamableCARBlockOrderingEnabled:(BOOL)enabled {
    atomic_store_explicit(&gMSTStreamableCARBlockOrderingEnabled,
                           (bool)(enabled != NO),
                           memory_order_release);
}

- (BOOL)enumerateStreamableCARBlocksUsingBlock:(BOOL (^)(CID *cid, NSData *data, NSError **error))block
                                recordProvider:(nullable MSTBlockProvider)recordProvider
                                         error:(NSError **)error {
    // Snapshot the C11 atomic-enabled flag exactly once at entry. Concurrent
    // setter calls update the global, but this walk uses its captured
    // snapshot and ignores subsequent writes; the legacy BFS enumerator
    // (-enumerateNodeCARBlocksUsingBlock:) is a separate code path that does
    // not consult this flag.
    //
    // Anti-regression: this local is the ONLY consult site for the duration
    // of the walk — the recursive helper -enumerateStreamableNode: must NOT
    // re-read gMSTStreamableCARBlockOrderingEnabled. Adding such a check would
    // silently re-open the Time-Of-Check-To-Time-Of-Use (TOCTOU) window this
    // snapshot closes.
    //
    // Thread-safety interaction: -root is also snapshotted here via the
    // C11 acquire-load getter. The captured autoreleased reference is bound
    // to -rootSnapshot for the rest of the walk; ARC retains the published
    // root for the walker's duration, so a concurrent -put:/-delete: from
    // another thread that publishes a new root cannot tear the tree this
    // walker is observing (copy-on-write invariant on addRecursive:/
    // deleteRecursive:/split:/merge:).
    const bool orderingEnabled = atomic_load_explicit(
        &gMSTStreamableCARBlockOrderingEnabled,
        memory_order_acquire);
    if (!orderingEnabled) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.mst"
                                         code:100
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                @"Sync 1.1 'Streamable CAR Block Ordering' is not enabled. "
                                                @"Call +[MST setStreamableCARBlockOrderingEnabled:YES] "
                                                @"first to opt in (this feature targets a draft spec)."}];
        }
        return NO;
    }

    if (!block) {
        return YES;
    }
    MSTNode * __strong rootSnapshot = self.root;
    if (!rootSnapshot) {
        return YES;
    }

    NSMapTable<MSTNode *, CID *> *cache = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableSet<NSString *> *addedCIDs = [NSMutableSet set];

    return [self enumerateStreamableNode:rootSnapshot
                                    cache:cache
                              addedCIDs:addedCIDs
                                    block:block
                          recordProvider:recordProvider
                                    error:error];
}

- (BOOL)enumerateStreamableNode:(MSTNode *)node
                          cache:(NSMapTable<MSTNode *, CID *> *)cache
                     addedCIDs:(NSMutableSet<NSString *> *)addedCIDs
                          block:(BOOL (^)(CID *cid, NSData *data, NSError **error))block
                recordProvider:(nullable MSTBlockProvider)recordProvider
                          error:(NSError **)error {
    if (!node) {
        return YES;
    }

    CID *nodeCID = [node getCID:cache];
    NSString *nodeCIDString = nodeCID.stringValue ?: @"";
    if (nodeCIDString.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.mst"
                                         code:101
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                @"MST subtree node has no resolvable CID."}];
        }
        return NO;
    }

    if (![addedCIDs containsObject:nodeCIDString]) {
        [addedCIDs addObject:nodeCIDString];
        NSData *nodeData = [node serializeToCBOR:cache];
        if (nodeData.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.mst"
                                             code:102
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        @"Failed to serialize MST node to CBOR."}];
            }
            return NO;
        }
        NSError *cbErr = nil;
        if (!block(nodeCID, nodeData, &cbErr)) {
            if (error && cbErr) {
                *error = cbErr;
            }
            return NO;
        }
    }

    // Left subtree (keys < first entry) is walked first in pre-order.
    if (node.internalLeft) {
        if (![self enumerateStreamableNode:node.internalLeft
                                       cache:cache
                                  addedCIDs:addedCIDs
                                       block:block
                             recordProvider:recordProvider
                                       error:error]) {
            return NO;
        }
    }

    // Per entry: every entry has a value (the CID of the record at this key);
    // entries may additionally have an internalTree pointing to a subtree of
    // keys >= entry.fullKey and < the next entry's key. Emit the record for
    // entry.value (via recordProvider), then recurse into entry.internalTree
    // only when one exists. This matches the draft spec's "ordered by node
    // entries[]" rule and is by design — never coerce this into mutually
    // exclusive "leaf vs subtree" branches.
    for (MSTNodeEntry *entry in node.internalEntries) {
        if (entry.value) {
            NSString *recordCIDString = entry.value.stringValue ?: @"";
            if (recordCIDString.length > 0 && ![addedCIDs containsObject:recordCIDString]) {
                NSData *recordData = recordProvider ? recordProvider(entry.value) : nil;
                if (recordData.length > 0) {
                    [addedCIDs addObject:recordCIDString];
                    NSError *cbErr = nil;
                    if (!block(entry.value, recordData, &cbErr)) {
                        if (error && cbErr) {
                            *error = cbErr;
                        }
                        return NO;
                    }
                }
            }
        }

        if (entry.internalTree) {
            if (![self enumerateStreamableNode:entry.internalTree
                                           cache:cache
                                      addedCIDs:addedCIDs
                                          block:block
                                 recordProvider:recordProvider
                                          error:error]) {
                return NO;
            }
        }
    }

    return YES;
}

@end
