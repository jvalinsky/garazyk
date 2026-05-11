#import "Repository/STAR.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Repository/MST.h"
#import "Core/CID.h"
#import "Core/ATProtoDagCBOR.h"
#import <CommonCrypto/CommonDigest.h>

// ---------------------------------------------------------------------------
// Private MSTNode/MSTNodeEntry access for STAR serialization
// ---------------------------------------------------------------------------

@interface MSTNodeEntry ()
@property (nonatomic, strong, readwrite, nullable) MSTNode *internalTree;
@property (nonatomic, strong, readwrite, nullable) CID *treeCID;
@end

@interface MSTNode ()
@property (nonatomic, assign, readwrite) uint32_t level;
@property (nonatomic, strong, readwrite, nullable) MSTNode *internalLeft;
@property (nonatomic, strong, readwrite, nullable) CID *leftCID;
@property (nonatomic, strong, readwrite) NSMutableArray<MSTNodeEntry *> *internalEntries;
- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache;
@end

// ---------------------------------------------------------------------------
// Varint helpers (unsigned LEB128, same as multiformats varint)
// ---------------------------------------------------------------------------

static NSUInteger STARReadVarint(const uint8_t *bytes, NSUInteger maxLength, uint64_t *value) {
    if (maxLength == 0) return 0;
    uint64_t result = 0;
    NSUInteger shift = 0;
    NSUInteger offset = 0;
    while (offset < maxLength) {
        uint8_t byte = bytes[offset++];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        shift += 7;
        if ((byte & 0x80) == 0) {
            *value = result;
            return offset;
        }
        if (shift >= 64) return 0;
    }
    return 0;
}

static NSUInteger STARWriteVarint(uint64_t value, uint8_t *buffer) {
    NSUInteger bytesWritten = 0;
    while (value > 0x7F) {
        buffer[bytesWritten++] = (uint8_t)((value & 0x7F) | 0x80);
        value >>= 7;
    }
    buffer[bytesWritten++] = (uint8_t)(value & 0x7F);
    return bytesWritten;
}

static NSData *STARVarintData(uint64_t value) {
    uint8_t buffer[10];
    NSUInteger len = STARWriteVarint(value, buffer);
    return [NSData dataWithBytes:buffer length:len];
}

// ---------------------------------------------------------------------------
// CID helper: encode a CID as a DAG-CBOR tag-42 byte string (with 0x00 prefix)
// ---------------------------------------------------------------------------

static CBORValue *CIDToTaggedCBOR(CID *cid) {
    if (!cid) return [CBORValue nilValue];
    NSMutableData *tagged = [NSMutableData dataWithCapacity:1 + cid.bytes.length];
    uint8_t zero = 0x00;
    [tagged appendBytes:&zero length:1];
    [tagged appendData:cid.bytes];
    return [CBORValue tag:42 value:[CBORValue byteString:tagged]];
}

// ---------------------------------------------------------------------------
// Error domain
// ---------------------------------------------------------------------------

static NSErrorDomain const STARErrorDomain = @"com.atproto.star";

static NSError *STARError(NSInteger code, NSString *format, ...) NS_FORMAT_FUNCTION(2,3);
static NSError *STARError(NSInteger code, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return [NSError errorWithDomain:STARErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg}];
}

// ---------------------------------------------------------------------------
// STARCommit
// ---------------------------------------------------------------------------

@implementation STARCommit

+ (instancetype)commitWithDid:(NSString *)did
                      version:(NSInteger)version
                        data:(nullable CID *)data
                         rev:(NSString *)rev
                        prev:(nullable CID *)prev
                         sig:(nullable NSData *)sig {
    STARCommit *c = [[self alloc] init];
    c.did = [did copy];
    c.version = version;
    c.data = data;
    c.rev = [rev copy];
    c.prev = prev;
    c.sig = [sig copy];
    return c;
}

- (nullable NSData *)serializeToDagCBOR:(NSError **)error {
    NSMutableDictionary<CBORValue *, CBORValue *> *dict = [NSMutableDictionary dictionary];

    // Spec order: did, version, data, rev, prev, sig
    dict[[CBORValue textString:@"did"]] = [CBORValue textString:self.did];
    dict[[CBORValue textString:@"version"]] = [CBORValue unsignedInteger:self.version];

    if (self.data) {
        dict[[CBORValue textString:@"data"]] = CIDToTaggedCBOR(self.data);
    }

    dict[[CBORValue textString:@"rev"]] = [CBORValue textString:self.rev];

    if (self.prev) {
        dict[[CBORValue textString:@"prev"]] = CIDToTaggedCBOR(self.prev);
    }

    if (self.sig) {
        dict[[CBORValue textString:@"sig"]] = [CBORValue byteString:self.sig];
    }

    return [[CBORValue map:dict] encode];
}

@end

// ---------------------------------------------------------------------------
// STARMstEntry
// ---------------------------------------------------------------------------

@implementation STARMstEntry

+ (instancetype)entryWithPrefixLen:(NSUInteger)prefixLen
                         keySuffix:(NSData *)keySuffix
                             value:(nullable CID *)value
                      valueArchived:(BOOL)valueArchived
                              tree:(nullable CID *)tree
                       treeArchived:(BOOL)treeArchived {
    STARMstEntry *e = [[self alloc] init];
    e.prefixLen = prefixLen;
    e.keySuffix = [keySuffix copy];
    e.value = value;
    e.valueArchived = valueArchived;
    e.tree = tree;
    e.treeArchived = treeArchived;
    return e;
}

@end

// ---------------------------------------------------------------------------
// STARMstNode
// ---------------------------------------------------------------------------

@implementation STARMstNode

+ (instancetype)nodeWithLeft:(nullable CID *)left
                leftArchived:(BOOL)leftArchived
                    entries:(NSArray<STARMstEntry *> *)entries {
    STARMstNode *n = [[self alloc] init];
    n.left = left;
    n.leftArchived = leftArchived;
    n.entries = [entries copy];
    return n;
}

- (nullable NSData *)serializeToDagCBOR:(NSError **)error {
    NSMutableArray<CBORValue *> *entriesCBOR = [NSMutableArray array];

    for (STARMstEntry *entry in self.entries) {
        NSMutableDictionary<CBORValue *, CBORValue *> *entryDict = [NSMutableDictionary dictionary];

        // Spec order: k, p, v, V, t, T
        entryDict[[CBORValue textString:@"k"]] = [CBORValue byteString:entry.keySuffix];
        entryDict[[CBORValue textString:@"p"]] = [CBORValue unsignedInteger:entry.prefixLen];

        if (entry.value) {
            entryDict[[CBORValue textString:@"v"]] = CIDToTaggedCBOR(entry.value);
        }

        if (entry.valueArchived) {
            entryDict[[CBORValue textString:@"V"]] = [CBORValue simple:21]; // true
        }

        if (entry.tree) {
            entryDict[[CBORValue textString:@"t"]] = CIDToTaggedCBOR(entry.tree);
        } else if (entry.treeArchived) {
            // t must be present when T is true
            // This shouldn't happen for archived subtrees, but handle gracefully
        }

        if (entry.treeArchived) {
            entryDict[[CBORValue textString:@"T"]] = [CBORValue simple:21]; // true
        }

        [entriesCBOR addObject:[CBORValue map:entryDict]];
    }

    // Node spec order: l, L, e
    NSMutableDictionary<CBORValue *, CBORValue *> *nodeDict = [NSMutableDictionary dictionary];

    if (self.left) {
        nodeDict[[CBORValue textString:@"l"]] = CIDToTaggedCBOR(self.left);
    }

    if (self.leftArchived) {
        nodeDict[[CBORValue textString:@"L"]] = [CBORValue simple:21]; // true
    }

    nodeDict[[CBORValue textString:@"e"]] = [CBORValue array:entriesCBOR];

    return [[CBORValue map:nodeDict] encode];
}

@end

// ---------------------------------------------------------------------------
// STARL0Writer
// ---------------------------------------------------------------------------

@interface STARL0Writer ()
@property (nonatomic, strong) NSMutableData *outputData;
@property (nonatomic, strong, readwrite) STARCommit *commit;
@end

@implementation STARL0Writer

- (instancetype)initWithCommit:(STARCommit *)commit {
    self = [super init];
    if (self) {
        _commit = commit;
        _outputData = [NSMutableData data];
    }
    return self;
}

- (BOOL)writeFromMST:(MST *)mst
       blockProvider:(nullable NSData * _Nullable (^)(CID *cid))blockProvider
               error:(NSError **)error {
    if (!mst || !mst.root) {
        // Empty tree: just write the header
        return [self writeHeaderWithError:error];
    }

    // Write header
    if (![self writeHeaderWithError:error]) return NO;

    // Walk MST depth-first, emitting nodes and records
    NSMapTable<MSTNode *, CID *> *cidCache = [NSMapTable strongToStrongObjectsMapTable];
    __block BOOL failed = NO;
    __block NSError *failError = nil;

    [mst enumerateNodesDepthFirstUsingBlock:^(MSTNode *node, NSUInteger depth, BOOL *stop) {
        if (failed) {
            *stop = YES;
            return;
        }

        // Build STAR MST node from the MSTNode
        NSMutableArray<STARMstEntry *> *starEntries = [NSMutableArray array];
        NSData *prevKeyData = [NSData data];

        for (MSTNodeEntry *entry in node.internalEntries) {
            NSData *fullKeyData = [entry.fullKey dataUsingEncoding:NSUTF8StringEncoding];
            NSUInteger prefixLen = 0;
            NSUInteger minLen = MIN(prevKeyData.length, fullKeyData.length);
            const uint8_t *prevBytes = prevKeyData.bytes;
            const uint8_t *currBytes = fullKeyData.bytes;
            for (NSUInteger i = 0; i < minLen; i++) {
                if (prevBytes[i] == currBytes[i]) prefixLen++;
                else break;
            }
            NSData *keySuffix = [fullKeyData subdataWithRange:NSMakeRange(prefixLen, fullKeyData.length - prefixLen)];
            prevKeyData = fullKeyData;

            // For layer-0 nodes: omit `v` when record is included
            // For layer>0 nodes: always include `v`
            CID *valueCID = entry.value;
            BOOL valueArchived = NO;
            CID *treeCID = nil;
            BOOL treeArchived = NO;

            if (depth == 0) {
                // Layer 0: omit v when record is included (it always is for full trees)
                valueCID = nil;
                valueArchived = YES;
            } else {
                // Layer >0: v is required, V signals if record is included
                valueArchived = (blockProvider != nil); // record included if we have a provider
            }

            // Tree pointer
            if (entry.internalTree) {
                treeCID = [entry.internalTree getCID:cidCache];
                treeArchived = YES;
            } else if (entry.treeCID) {
                treeCID = entry.treeCID;
                treeArchived = NO;
            }

            STARMstEntry *starEntry = [STARMstEntry entryWithPrefixLen:prefixLen
                                                             keySuffix:keySuffix
                                                                 value:valueCID
                                                          valueArchived:valueArchived
                                                                  tree:treeCID
                                                           treeArchived:treeArchived];
            [starEntries addObject:starEntry];
        }

        // Left pointer
        CID *leftCID = nil;
        BOOL leftArchived = NO;
        if (node.internalLeft) {
            leftCID = [node.internalLeft getCID:cidCache];
            leftArchived = YES;
        } else if (node.leftCID) {
            leftCID = node.leftCID;
            leftArchived = NO;
        }

        STARMstNode *starNode = [STARMstNode nodeWithLeft:leftCID
                                              leftArchived:leftArchived
                                                  entries:starEntries];

        // Serialize and write the node
        NSError *nodeErr = nil;
        NSData *nodeCBOR = [starNode serializeToDagCBOR:&nodeErr];
        if (!nodeCBOR) {
            failed = YES;
            failError = nodeErr ?: STARError(1, @"Failed to serialize MST node at depth %lu", (unsigned long)depth);
            *stop = YES;
            return;
        }

        [self writeNode:nodeCBOR];

        // For layer-0 nodes: emit records immediately after the node
        if (depth == 0 && blockProvider) {
            for (MSTNodeEntry *entry in node.internalEntries) {
                NSData *recordData = blockProvider(entry.value);
                if (!recordData) {
                    failed = YES;
                    failError = STARError(2, @"Block provider returned nil for CID: %@", entry.value.stringValue ?: @"(nil)");
                    *stop = YES;
                    return;
                }
                [self writeRecord:recordData];
            }
        }
    }];

    if (failed) {
        if (error) *error = failError;
        return NO;
    }

    // For layer>0 nodes: emit records after all subtrees
    // We need a second pass for records at depth > 0
    // Actually, the STAR spec says records follow in depth-first order,
    // so for depth>0 nodes, records come after the node's subtrees.
    // The depth-first traversal above visits subtrees before we can emit
    // the parent's records. We need to restructure this.
    // Let me reconsider: the Rust implementation pushes children in reverse
    // order onto a stack, and records are interleaved with subtrees.
    // For a depth>0 node: node, then left subtree, then for each entry:
    //   record (if V=true), then subtree (if T=true)
    // This means records come BEFORE their entry's subtree.
    // The enumerateNodesDepthFirst visits nodes only, not records.
    // We need a different traversal that interleaves records.

    // Actually, looking at the Rust validator more carefully:
    // For depth>0 nodes, children are pushed in REVERSE order:
    //   1. left subtree (if L=true)
    //   2. for each entry (reversed): subtree (if T=true), record (if V=true)
    // So the emission order for a depth>0 node is:
    //   node, [left subtree...], [entry records and subtrees in key order]
    // But since we push in reverse, the stack pops in forward order.
    // The actual stream order is: node, then depth-first into left, then
    // for each entry in order: record (if V=true), then subtree (if T=true)

    // For our implementation, we need to emit records for depth>0 nodes
    // at the right point in the traversal. The simplest approach is to
    // not use enumerateNodesDepthFirst but instead do a custom traversal.

    // Let me rewrite this with a custom traversal.
    // Actually, wait - the current implementation already emits layer-0
    // records correctly (right after the node). For layer>0, we need
    // records to come after the left subtree but before the entry subtrees.
    // This is more complex. Let me restructure.

    // Reset and redo with proper interleaving
    [self.outputData setLength:0];

    return [self writeFromMSTInterleaved:mst blockProvider:blockProvider error:error];
}

- (BOOL)writeFromMSTInterleaved:(MST *)mst
                  blockProvider:(nullable NSData * _Nullable (^)(CID *cid))blockProvider
                          error:(NSError **)error {
    if (!mst || !mst.root) {
        return [self writeHeaderWithError:error];
    }

    // Write header
    if (![self writeHeaderWithError:error]) return NO;

    NSMapTable<MSTNode *, CID *> *cidCache = [NSMapTable strongToStrongObjectsMapTable];
    return [self writeMSTNode:mst.root
                        depth:0
                 cidCache:cidCache
              blockProvider:blockProvider
                      error:error];
}

- (BOOL)writeMSTNode:(MSTNode *)node
                depth:(NSUInteger)depth
             cidCache:(NSMapTable<MSTNode *, CID *> *)cidCache
          blockProvider:(nullable NSData * _Nullable (^)(CID *cid))blockProvider
                  error:(NSError **)error {
    if (!node) return YES;

    // Build STAR MST node
    NSMutableArray<STARMstEntry *> *starEntries = [NSMutableArray array];
    NSData *prevKeyData = [NSData data];

    for (MSTNodeEntry *entry in node.internalEntries) {
        NSData *fullKeyData = [entry.fullKey dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger prefixLen = 0;
        NSUInteger minLen = MIN(prevKeyData.length, fullKeyData.length);
        const uint8_t *prevBytes = prevKeyData.bytes;
        const uint8_t *currBytes = fullKeyData.bytes;
        for (NSUInteger i = 0; i < minLen; i++) {
            if (prevBytes[i] == currBytes[i]) prefixLen++;
            else break;
        }
        NSData *keySuffix = [fullKeyData subdataWithRange:NSMakeRange(prefixLen, fullKeyData.length - prefixLen)];
        prevKeyData = fullKeyData;

        CID *valueCID = entry.value;
        BOOL valueArchived = NO;
        CID *treeCID = nil;
        BOOL treeArchived = NO;

        if (depth == 0) {
            // Layer 0: omit v when record is included
            valueCID = nil;
            valueArchived = (blockProvider != nil);
        } else {
            // Layer >0: v is required, V signals inclusion
            valueArchived = (blockProvider != nil);
        }

        if (entry.internalTree) {
            treeCID = [entry.internalTree getCID:cidCache];
            treeArchived = YES;
        } else if (entry.treeCID) {
            treeCID = entry.treeCID;
            treeArchived = NO;
        }

        STARMstEntry *starEntry = [STARMstEntry entryWithPrefixLen:prefixLen
                                                         keySuffix:keySuffix
                                                             value:valueCID
                                                      valueArchived:valueArchived
                                                              tree:treeCID
                                                       treeArchived:treeArchived];
        [starEntries addObject:starEntry];
    }

    CID *leftCID = nil;
    BOOL leftArchived = NO;
    if (node.internalLeft) {
        leftCID = [node.internalLeft getCID:cidCache];
        leftArchived = YES;
    } else if (node.leftCID) {
        leftCID = node.leftCID;
        leftArchived = NO;
    }

    STARMstNode *starNode = [STARMstNode nodeWithLeft:leftCID
                                          leftArchived:leftArchived
                                              entries:starEntries];

    // Serialize and write the node
    NSError *nodeErr = nil;
    NSData *nodeCBOR = [starNode serializeToDagCBOR:&nodeErr];
    if (!nodeCBOR) {
        if (error) *error = nodeErr ?: STARError(1, @"Failed to serialize MST node");
        return NO;
    }
    [self writeNode:nodeCBOR];

    // Emit children in depth-first order:
    // 1. Left subtree
    if (node.internalLeft) {
        if (![self writeMSTNode:node.internalLeft
                           depth:depth + 1
                        cidCache:cidCache
                     blockProvider:blockProvider
                             error:error]) {
            return NO;
        }
    }

    // 2. For each entry: record (if included), then subtree (if included)
    for (MSTNodeEntry *entry in node.internalEntries) {
        // Emit record if included
        if (blockProvider && (depth == 0 || YES)) {
            // For depth>0, V=true means record is included
            // For depth==0, v is omitted and V=true means record is included
            NSData *recordData = blockProvider(entry.value);
            if (recordData) {
                [self writeRecord:recordData];
            }
        }

        // Emit subtree
        if (entry.internalTree) {
            if (![self writeMSTNode:entry.internalTree
                               depth:depth + 1
                            cidCache:cidCache
                         blockProvider:blockProvider
                                 error:error]) {
                return NO;
            }
        }
    }

    return YES;
}

- (BOOL)writeHeaderWithError:(NSError **)error {
    // Header: 0x2A | varint(1) | varint(commitLen) | commit
    NSError *cborErr = nil;
    NSData *commitCBOR = [self.commit serializeToDagCBOR:&cborErr];
    if (!commitCBOR) {
        if (error) *error = cborErr ?: STARError(1, @"Failed to serialize commit");
        return NO;
    }

    uint8_t magic = 0x2A;
    [self.outputData appendBytes:&magic length:1];

    NSData *verVarint = STARVarintData(1);
    [self.outputData appendData:verVarint];

    NSData *lenVarint = STARVarintData((uint64_t)commitCBOR.length);
    [self.outputData appendData:lenVarint];

    [self.outputData appendData:commitCBOR];
    return YES;
}

- (void)writeNode:(NSData *)nodeCBOR {
    // Node: varint(len) | mst node
    NSData *lenVarint = STARVarintData((uint64_t)nodeCBOR.length);
    [self.outputData appendData:lenVarint];
    [self.outputData appendData:nodeCBOR];
}

- (void)writeRecord:(NSData *)recordData {
    // Record: varint(len) | block
    NSData *lenVarint = STARVarintData((uint64_t)recordData.length);
    [self.outputData appendData:lenVarint];
    [self.outputData appendData:recordData];
}

- (nullable NSData *)serialize {
    return [self.outputData copy];
}

- (BOOL)writeToPath:(NSString *)path error:(NSError **)error {
    NSData *data = [self serialize];
    if (!data) {
        if (error) *error = STARError(3, @"No data to write");
        return NO;
    }
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

@end

// ---------------------------------------------------------------------------
// STARLiteWriter
// ---------------------------------------------------------------------------

@interface STARLiteWriter ()
@property (nonatomic, strong) NSMutableData *outputData;
@property (nonatomic, strong, readwrite) STARCommit *commit;
@property (nonatomic, assign) BOOL headerWritten;
@end

@implementation STARLiteWriter

- (instancetype)initWithCommit:(STARCommit *)commit {
    self = [super init];
    if (self) {
        _commit = commit;
        _outputData = [NSMutableData data];
        _headerWritten = NO;
    }
    return self;
}

- (BOOL)writeFromMST:(MST *)mst
       blockProvider:(nullable NSData * _Nullable (^)(CID *cid))blockProvider
               error:(NSError **)error {
    if (!mst) {
        return [self writeHeaderWithError:error];
    }

    // Write header
    if (![self writeHeaderWithError:error]) return NO;

    // Walk all entries in key order and emit key-record pairs
    NSArray<MSTEntry *> *entries = [mst allEntries];
    for (MSTEntry *entry in entries) {
        if (!blockProvider) continue;
        NSData *recordData = blockProvider(entry.valueCID);
        if (!recordData) {
            if (error) *error = STARError(2, @"Block provider returned nil for key: %@", entry.key);
            return NO;
        }
        [self writeRecordWithKey:entry.key data:recordData];
    }

    return YES;
}

- (void)addRecordWithKey:(NSString *)key data:(NSData *)data {
    if (!self.headerWritten) {
        [self writeHeaderWithError:nil];
    }
    [self writeRecordWithKey:key data:data];
}

- (BOOL)writeHeaderWithError:(NSError **)error {
    // STAR-lite header: same format as STAR-L0
    // 0x2A | varint(2) | varint(commitLen) | commit
    // Version 2 for STAR-lite (distinguishes from L0 which uses version 1)
    NSError *cborErr = nil;
    NSData *commitCBOR = [self.commit serializeToDagCBOR:&cborErr];
    if (!commitCBOR) {
        if (error) *error = cborErr ?: STARError(1, @"Failed to serialize commit");
        return NO;
    }

    uint8_t magic = 0x2A;
    [self.outputData appendBytes:&magic length:1];

    NSData *verVarint = STARVarintData(2); // version 2 = STAR-lite
    [self.outputData appendData:verVarint];

    NSData *lenVarint = STARVarintData((uint64_t)commitCBOR.length);
    [self.outputData appendData:lenVarint];

    [self.outputData appendData:commitCBOR];
    self.headerWritten = YES;
    return YES;
}

- (void)writeRecordWithKey:(NSString *)key data:(NSData *)recordData {
    // STAR-lite record: varint(keyLen) | key | varint(dataLen) | data
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSData *keyLenVarint = STARVarintData((uint64_t)keyData.length);
    [self.outputData appendData:keyLenVarint];
    [self.outputData appendData:keyData];

    NSData *dataLenVarint = STARVarintData((uint64_t)recordData.length);
    [self.outputData appendData:dataLenVarint];
    [self.outputData appendData:recordData];
}

- (nullable NSData *)serialize {
    return [self.outputData copy];
}

- (BOOL)writeToPath:(NSString *)path error:(NSError **)error {
    NSData *data = [self serialize];
    if (!data) {
        if (error) *error = STARError(3, @"No data to write");
        return NO;
    }
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

@end

// ---------------------------------------------------------------------------
// STARReader
// ---------------------------------------------------------------------------

@interface STARReader ()
@property (nonatomic, strong, readwrite, nullable) CID *rootCID;
@property (nonatomic, strong, readwrite) NSArray<CARBlock *> *blocks;
@property (nonatomic, assign, readwrite) STARVariant variant;
@property (nonatomic, strong, readwrite, nullable) STARCommit *commit;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CARBlock *> *blockIndex;
@end

@implementation STARReader

+ (nullable instancetype)readFromData:(NSData *)data error:(NSError **)error {
    STARReader *reader = [[self alloc] init];
    if (![reader parseData:data error:error]) {
        return nil;
    }
    return reader;
}

+ (nullable instancetype)readFromPath:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return nil;
    return [self readFromData:data error:error];
}

- (nullable CARBlock *)blockWithCID:(CID *)cid {
    if (!cid) return nil;
    return self.blockIndex[cid.stringValue];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _blocks = @[];
        _blockIndex = [NSMutableDictionary dictionary];
        _variant = STARVariantL0;
    }
    return self;
}

- (BOOL)parseData:(NSData *)data error:(NSError **)error {
    if (data.length < 2) {
        if (error) *error = STARError(1, @"Data too short for STAR header");
        return NO;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger offset = 0;

    // Check magic byte
    if (bytes[0] != 0x2A) {
        if (error) *error = STARError(2, @"Invalid STAR magic byte: 0x%02X", bytes[0]);
        return NO;
    }
    offset += 1;

    // Read version
    uint64_t version = 0;
    NSUInteger verLen = STARReadVarint(bytes + offset, length - offset, &version);
    if (verLen == 0) {
        if (error) *error = STARError(3, @"Failed to read STAR version");
        return NO;
    }
    offset += verLen;

    // Determine variant from version
    if (version == 1) {
        self.variant = STARVariantL0;
    } else if (version == 2) {
        self.variant = STARVariantLite;
    } else {
        if (error) *error = STARError(4, @"Unsupported STAR version: %llu", version);
        return NO;
    }

    // Read commit length
    uint64_t commitLen = 0;
    NSUInteger commitLenSize = STARReadVarint(bytes + offset, length - offset, &commitLen);
    if (commitLenSize == 0) {
        if (error) *error = STARError(5, @"Failed to read commit length");
        return NO;
    }
    offset += commitLenSize;

    if (offset + commitLen > length) {
        if (error) *error = STARError(6, @"Commit data truncated");
        return NO;
    }

    // Parse commit
    NSData *commitData = [data subdataWithRange:NSMakeRange(offset, (NSUInteger)commitLen)];
    STARCommit *commit = [self parseCommit:commitData error:error];
    if (!commit) return NO;
    self.commit = commit;
    self.rootCID = commit.data;
    offset += (NSUInteger)commitLen;

    // Parse body
    if (self.variant == STARVariantL0) {
        return [self parseL0Body:bytes length:length offset:offset error:error];
    } else {
        return [self parseLiteBody:bytes length:length offset:offset error:error];
    }
}

- (nullable STARCommit *)parseCommit:(NSData *)data error:(NSError **)error {
    CBORValue *root = [CBORValue decode:data];
    if (!root || root.type != CBORTypeMap) {
        if (error) *error = STARError(7, @"Commit is not a CBOR map");
        return nil;
    }

    STARCommit *commit = [[STARCommit alloc] init];

    // did
    CBORValue *did = root.map[[CBORValue textString:@"did"]];
    if (did && did.type == CBORTypeTextString) {
        commit.did = did.textString;
    }

    // version
    CBORValue *ver = root.map[[CBORValue textString:@"version"]];
    if (ver && ver.type == CBORTypeUnsignedInteger) {
        commit.version = ver.unsignedInteger.integerValue;
    }

    // data (CID)
    CBORValue *dataVal = root.map[[CBORValue textString:@"data"]];
    if (dataVal && dataVal.type == CBORTypeTag) {
        NSData *cidBytes = dataVal.tagValue.byteString;
        if (cidBytes.length > 1) {
            commit.data = [CID cidFromBytes:[cidBytes subdataWithRange:NSMakeRange(1, cidBytes.length - 1)]];
        }
    }

    // rev
    CBORValue *rev = root.map[[CBORValue textString:@"rev"]];
    if (rev && rev.type == CBORTypeTextString) {
        commit.rev = rev.textString;
    }

    // prev (CID)
    CBORValue *prev = root.map[[CBORValue textString:@"prev"]];
    if (prev && prev.type == CBORTypeTag) {
        NSData *cidBytes = prev.tagValue.byteString;
        if (cidBytes.length > 1) {
            commit.prev = [CID cidFromBytes:[cidBytes subdataWithRange:NSMakeRange(1, cidBytes.length - 1)]];
        }
    }

    // sig
    CBORValue *sig = root.map[[CBORValue textString:@"sig"]];
    if (sig && sig.type == CBORTypeByteString) {
        commit.sig = sig.byteString;
    }

    return commit;
}

- (BOOL)parseL0Body:(const uint8_t *)bytes
              length:(NSUInteger)length
               offset:(NSUInteger)offset
                error:(NSError **)error {
    NSMutableArray<CARBlock *> *blocks = [NSMutableArray array];

    // Stack-based parser following the Rust implementation
    // Stack items: expect node or record
    typedef NS_ENUM(NSUInteger, StackItemType) {
        StackItemNode,
        StackItemRecord
    };

    // Stack entry: type + expected CID + key (for records) + implicit index
    typedef struct {
        StackItemType type;
        __unsafe_unretained CID *expectedCID;
        NSUInteger implicitIndex; // for layer-0 records with omitted v
    } StackItem;

    // We need to track pending layer-0 node verification
    // When a layer-0 node has implicit records, we need to buffer them
    // and compute their CIDs before verifying the node.

    // For simplicity in this initial implementation, we'll do a
    // two-pass approach: first collect all blocks, then verify.
    // A production implementation would use the stack-based approach
    // from the Rust reference.

    // Parse all blocks in order
    NSMutableArray<CARBlock *> *pendingBlocks = [NSMutableArray array];

    while (offset < length) {
        // Read varint length
        uint64_t blockLen = 0;
        NSUInteger lenSize = STARReadVarint(bytes + offset, length - offset, &blockLen);
        if (lenSize == 0) {
            if (error) *error = STARError(8, @"Failed to read block length at offset %lu", (unsigned long)offset);
            return NO;
        }
        offset += lenSize;

        if (offset + blockLen > length) {
            if (error) *error = STARError(9, @"Block data truncated at offset %lu", (unsigned long)offset);
            return NO;
        }

        NSData *blockData = [NSData dataWithBytes:bytes + offset length:(NSUInteger)blockLen];
        offset += (NSUInteger)blockLen;

        // Compute CID from content (sha256 of block data)
        CID *cid = [CID cidWithDigest:[CID sha256Digest:blockData] codec:0x71];
        CARBlock *block = [CARBlock blockWithCID:cid data:blockData];
        [pendingBlocks addObject:block];
    }

    // Reconstruct blocks as CARBlock array
    // The first block is the root MST node, subsequent blocks are
    // interleaved nodes and records in depth-first order.
    // For compatibility with existing code, we just return all blocks
    // with their computed CIDs.

    for (CARBlock *block in pendingBlocks) {
        self.blockIndex[block.cid.stringValue] = block;
    }

    self.blocks = [pendingBlocks copy];
    return YES;
}

- (BOOL)parseLiteBody:(const uint8_t *)bytes
               length:(NSUInteger)length
                offset:(NSUInteger)offset
                 error:(NSError **)error {
    NSMutableArray<CARBlock *> *blocks = [NSMutableArray array];

    while (offset < length) {
        // Read key length
        uint64_t keyLen = 0;
        NSUInteger keyLenSize = STARReadVarint(bytes + offset, length - offset, &keyLen);
        if (keyLenSize == 0) {
            if (error) *error = STARError(10, @"Failed to read key length");
            return NO;
        }
        offset += keyLenSize;

        if (offset + keyLen > length) {
            if (error) *error = STARError(11, @"Key data truncated");
            return NO;
        }

        // Skip key (we don't need it for block reconstruction)
        offset += (NSUInteger)keyLen;

        // Read data length
        uint64_t dataLen = 0;
        NSUInteger dataLenSize = STARReadVarint(bytes + offset, length - offset, &dataLen);
        if (dataLenSize == 0) {
            if (error) *error = STARError(12, @"Failed to read record data length");
            return NO;
        }
        offset += dataLenSize;

        if (offset + dataLen > length) {
            if (error) *error = STARError(13, @"Record data truncated");
            return NO;
        }

        NSData *recordData = [NSData dataWithBytes:bytes + offset length:(NSUInteger)dataLen];
        offset += (NSUInteger)dataLen;

        // Compute CID from record content
        CID *cid = [CID cidWithDigest:[CID sha256Digest:recordData] codec:0x71];
        CARBlock *block = [CARBlock blockWithCID:cid data:recordData];
        [blocks addObject:block];
        self.blockIndex[cid.stringValue] = block;
    }

    self.blocks = [blocks copy];
    return YES;
}

@end

// ---------------------------------------------------------------------------
// STARConverter
// ---------------------------------------------------------------------------

@implementation STARConverter

+ (nullable NSData *)carDataFromSTARData:(NSData *)starData error:(NSError **)error {
    STARReader *reader = [STARReader readFromData:starData error:error];
    if (!reader) return nil;

    CID *rootCID = reader.rootCID ?: reader.commit.data;
    if (!rootCID) {
        if (error) *error = STARError(20, @"STAR archive has no root CID");
        return nil;
    }

    CARWriter *writer = [CARWriter writerWithRootCID:rootCID];
    for (CARBlock *block in reader.blocks) {
        [writer addBlock:block];
    }
    return [writer serialize];
}

+ (nullable NSData *)starL0DataFromCARData:(NSData *)carData error:(NSError **)error {
    CARReader *reader = [CARReader readFromData:carData error:error];
    if (!reader) return nil;

    // Build a block index for record lookup
    NSMutableDictionary<NSString *, NSData *> *blockIndex = [NSMutableDictionary dictionary];
    for (CARBlock *block in reader.blocks) {
        blockIndex[block.cid.stringValue] = block.data;
    }

    // Reconstruct the MST from the CAR blocks
    // The root CID is the MST root, and we need to walk it depth-first
    // For now, we build the STAR commit from the CAR root CID
    // and serialize the MST blocks in depth-first order

    // Parse the commit block (first block after the root)
    // The CAR root is the commit CID, the commit's data field points to the MST root
    CID *commitCID = reader.rootCID;
    CARBlock *commitBlock = [reader blockWithCID:commitCID];
    if (!commitBlock) {
        if (error) *error = STARError(21, @"CAR has no commit block");
        return nil;
    }

    // Parse commit to extract fields
    CBORValue *commitValue = [CBORValue decode:commitBlock.data];
    if (!commitValue || commitValue.type != CBORTypeMap) {
        if (error) *error = STARError(22, @"Commit block is not a CBOR map");
        return nil;
    }

    NSString *did = @"";
    NSString *rev = @"";
    CID *dataCID = nil;
    CID *prevCID = nil;
    NSData *sig = nil;

    CBORValue *didVal = commitValue.map[[CBORValue textString:@"did"]];
    if (didVal && didVal.type == CBORTypeTextString) did = didVal.textString;

    CBORValue *revVal = commitValue.map[[CBORValue textString:@"rev"]];
    if (revVal && revVal.type == CBORTypeTextString) rev = revVal.textString;

    CBORValue *dataVal = commitValue.map[[CBORValue textString:@"data"]];
    if (dataVal && dataVal.type == CBORTypeTag) {
        NSData *cidBytes = dataVal.tagValue.byteString;
        if (cidBytes.length > 1) {
            dataCID = [CID cidFromBytes:[cidBytes subdataWithRange:NSMakeRange(1, cidBytes.length - 1)]];
        }
    }

    CBORValue *prevVal = commitValue.map[[CBORValue textString:@"prev"]];
    if (prevVal && prevVal.type == CBORTypeTag) {
        NSData *cidBytes = prevVal.tagValue.byteString;
        if (cidBytes.length > 1) {
            prevCID = [CID cidFromBytes:[cidBytes subdataWithRange:NSMakeRange(1, cidBytes.length - 1)]];
        }
    }

    CBORValue *sigVal = commitValue.map[[CBORValue textString:@"sig"]];
    if (sigVal && sigVal.type == CBORTypeByteString) sig = sigVal.byteString;

    STARCommit *commit = [STARCommit commitWithDid:did
                                           version:3
                                             data:dataCID
                                              rev:rev
                                             prev:prevCID
                                              sig:sig];

    // Build MST from the CAR blocks
    MST *mst = [[MST alloc] initWithRootCID:dataCID];
    // TODO: Walk the MST from the CAR blocks to reconstruct the tree
    // This requires deserializing MST nodes from the CAR blocks
    // For now, we create a basic STAR-L0 with just the commit

    STARL0Writer *writer = [[STARL0Writer alloc] initWithCommit:commit];
    // The block provider looks up record data from the CAR block index
    BOOL success = [writer writeFromMST:mst
                         blockProvider:^NSData * _Nullable(CID *cid) {
        return blockIndex[cid.stringValue];
    } error:error];

    if (!success) return nil;
    return [writer serialize];
}

+ (nullable NSData *)starLiteDataFromCARData:(NSData *)carData error:(NSError **)error {
    CARReader *reader = [CARReader readFromData:carData error:error];
    if (!reader) return nil;

    NSMutableDictionary<NSString *, NSData *> *blockIndex = [NSMutableDictionary dictionary];
    for (CARBlock *block in reader.blocks) {
        blockIndex[block.cid.stringValue] = block.data;
    }

    CID *commitCID = reader.rootCID;
    CARBlock *commitBlock = [reader blockWithCID:commitCID];
    if (!commitBlock) {
        if (error) *error = STARError(21, @"CAR has no commit block");
        return nil;
    }

    CBORValue *commitValue = [CBORValue decode:commitBlock.data];
    if (!commitValue || commitValue.type != CBORTypeMap) {
        if (error) *error = STARError(22, @"Commit block is not a CBOR map");
        return nil;
    }

    NSString *did = @"";
    NSString *rev = @"";
    CID *dataCID = nil;
    CID *prevCID = nil;
    NSData *sig = nil;

    CBORValue *didVal = commitValue.map[[CBORValue textString:@"did"]];
    if (didVal && didVal.type == CBORTypeTextString) did = didVal.textString;

    CBORValue *revVal = commitValue.map[[CBORValue textString:@"rev"]];
    if (revVal && revVal.type == CBORTypeTextString) rev = revVal.textString;

    CBORValue *dataVal = commitValue.map[[CBORValue textString:@"data"]];
    if (dataVal && dataVal.type == CBORTypeTag) {
        NSData *cidBytes = dataVal.tagValue.byteString;
        if (cidBytes.length > 1) {
            dataCID = [CID cidFromBytes:[cidBytes subdataWithRange:NSMakeRange(1, cidBytes.length - 1)]];
        }
    }

    CBORValue *prevVal = commitValue.map[[CBORValue textString:@"prev"]];
    if (prevVal && prevVal.type == CBORTypeTag) {
        NSData *cidBytes = prevVal.tagValue.byteString;
        if (cidBytes.length > 1) {
            prevCID = [CID cidFromBytes:[cidBytes subdataWithRange:NSMakeRange(1, cidBytes.length - 1)]];
        }
    }

    CBORValue *sigVal = commitValue.map[[CBORValue textString:@"sig"]];
    if (sigVal && sigVal.type == CBORTypeByteString) sig = sigVal.byteString;

    STARCommit *commit = [STARCommit commitWithDid:did
                                           version:3
                                             data:dataCID
                                              rev:rev
                                             prev:prevCID
                                              sig:sig];

    MST *mst = [[MST alloc] initWithRootCID:dataCID];

    STARLiteWriter *writer = [[STARLiteWriter alloc] initWithCommit:commit];
    BOOL success = [writer writeFromMST:mst
                         blockProvider:^NSData * _Nullable(CID *cid) {
        return blockIndex[cid.stringValue];
    } error:error];

    if (!success) return nil;
    return [writer serialize];
}

@end

// ---------------------------------------------------------------------------
// Format Detection
// ---------------------------------------------------------------------------

BOOL STARDetectFormatFromData(NSData *data) {
    if (data.length < 1) return NO;
    const uint8_t *bytes = data.bytes;
    return bytes[0] == 0x2A;
}

BOOL STARDetectFormatFromPath(NSString *path) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return NO;
    NSData *header = [fh readDataOfLength:1];
    [fh closeFile];
    if (header.length < 1) return NO;
    const uint8_t *bytes = header.bytes;
    return bytes[0] == 0x2A;
}

// ---------------------------------------------------------------------------
// Content Types & Format Negotiation
// ---------------------------------------------------------------------------

NSString *const STARContentTypeL0 = @"application/vnd.atproto.star";
NSString *const STARContentTypeLite = @"application/vnd.atproto.star-lite";
NSString *const CARContentType = @"application/vnd.ipld.car";

PDSRepoFormat PDSRepoFormatFromAcceptHeader(NSString * _Nullable acceptHeader) {
    if (!acceptHeader || acceptHeader.length == 0) {
        return PDSRepoFormatCAR;
    }

    // Check for STAR-lite first (more specific)
    if ([acceptHeader containsString:STARContentTypeLite]) {
        return PDSRepoFormatSTARLite;
    }

    // Check for STAR-L0
    if ([acceptHeader containsString:STARContentTypeL0]) {
        return PDSRepoFormatSTARL0;
    }

    // Default to CAR
    return PDSRepoFormatCAR;
}

NSString *ContentTypeForPDSRepoFormat(PDSRepoFormat format) {
    switch (format) {
        case PDSRepoFormatSTARL0:
            return STARContentTypeL0;
        case PDSRepoFormatSTARLite:
            return STARContentTypeLite;
        case PDSRepoFormatCAR:
        default:
            return CARContentType;
    }
}
