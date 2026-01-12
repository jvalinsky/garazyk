#import "Repository/MST.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"
#import <CommonCrypto/CommonDigest.h>
#import <arpa/inet.h>

#pragma mark - Internal Classes

@interface MSTNode : NSObject
@property (nonatomic, assign) uint32_t level;
@property (nonatomic, strong, nullable) MSTNode *left;
@property (nonatomic, strong) NSMutableArray<MSTNodeEntry *> *entries;
- (instancetype)initWithLevel:(uint32_t)level;
- (CID *)getCID:(NSMutableDictionary<MSTNode *, CID *> *)cache;
@end

@implementation MSTEntry (Internal)
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
    // Note: tree in MST.h is CID, but internally we might want to store MSTNode*
    // For now, we'll use an internal property or just cast.
    return entry;
}

// Internal version for tree operations
- (instancetype)initWithKey:(NSString *)key value:(CID *)value tree:(MSTNode *)tree {
    self = [super init];
    if (self) {
        _value = value;
        // We'll use a private property for internal tree reference
        objc_setAssociatedObject(self, @"internalTree", tree, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, @"fullKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return self;
}

- (NSString *)key {
    return objc_getAssociatedObject(self, @"fullKey");
}

- (MSTNode *)internalTree {
    return objc_getAssociatedObject(self, @"internalTree");
}

- (void)setInternalTree:(MSTNode *)tree {
    objc_setAssociatedObject(self, @"internalTree", tree, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

    // This method is for the old serialization format.
    // For the tree pointer, we should use the CID if available.
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
        _entries = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithLevel:(uint32_t)level left:(MSTNode *)left entries:(NSArray<MSTNodeEntry *> *)entries {
    self = [self initWithLevel:level];
    if (self) {
        _left = left;
        [_entries addObjectsFromArray:entries];
    }
    return self;
}

- (CID *)getCID:(NSMutableDictionary<MSTNode *, CID *> *)cache {
    if (cache[self]) return cache[self];
    
    NSData *cbor = [self serializeToCBOR:cache];
    CID *cid = [CID cidWithMultihash:[CID sha256Digest:cbor] codec:0x71];
    cache[self] = cid;
    return cid;
}

- (NSData *)serializeToCBOR:(NSMutableDictionary<MSTNode *, CID *> *)cache {
    NSMutableArray<CBORValue *> *entriesCBOR = [NSMutableArray array];
    NSString *prevKey = @"";
    for (MSTNodeEntry *entry in self.entries) {
        NSString *fullKey = entry.key;
        NSUInteger p = 0;
        NSUInteger minLen = MIN(prevKey.length, fullKey.length);
        for (NSUInteger i = 0; i < minLen; i++) {
            if ([prevKey characterAtIndex:i] == [fullKey characterAtIndex:i]) {
                p++;
            } else {
                break;
            }
        }
        
        NSData *kSuffix = [[fullKey substringFromIndex:p] dataUsingEncoding:NSUTF8StringEncoding];
        
        NSMutableDictionary<CBORValue *, CBORValue *> *dict = [NSMutableDictionary dictionary];
        dict[[CBORValue textString:@"p"]] = [CBORValue unsignedInteger:p];
        dict[[CBORValue textString:@"k"]] = [CBORValue byteString:kSuffix];
        
        // Value CID with tag 42. Note: ATProto expects a 0x00 prefix for the binary CID in tag 42.
        NSMutableData *vData = [NSMutableData dataWithBytes:"\x00" length:1];
        [vData appendData:entry.value.bytes];
        dict[[CBORValue textString:@"v"]] = [CBORValue tag:42 value:[CBORValue byteString:vData]];
        
        if (entry.internalTree) {
            CID *tCID = [entry.internalTree getCID:cache];
            NSMutableData *tData = [NSMutableData dataWithBytes:"\x00" length:1];
            [tData appendData:tCID.bytes];
            dict[[CBORValue textString:@"t"]] = [CBORValue tag:42 value:[CBORValue byteString:tData]];
        }
        
        [entriesCBOR addObject:[CBORValue map:dict]];
        prevKey = fullKey;
    }
    
    NSMutableDictionary<CBORValue *, CBORValue *> *nodeDict = [NSMutableDictionary dictionary];
    nodeDict[[CBORValue textString:@"e"]] = [CBORValue array:entriesCBOR];
    if (self.left) {
        CID *lCID = [self.left getCID:cache];
        NSMutableData *lData = [NSMutableData dataWithBytes:"\x00" length:1];
        [lData appendData:lCID.bytes];
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue tag:42 value:[CBORValue byteString:lData]];
    }
    
    return [[CBORValue map:nodeDict] encode];
}

- (void)split:(NSString *)key left:(MSTNode **)leftOut right:(MSTNode **)rightOut {
    NSInteger idx = 0;
    while (idx < self.entries.count && [self.entries[idx].key compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    MSTNode *subtree = (idx == 0) ? self.left : self.entries[idx-1].internalTree;
    MSTNode *splitLeft = nil;
    MSTNode *splitRight = nil;
    if (subtree) {
        [subtree split:key left:&splitLeft right:&splitRight];
    }
    
    NSMutableArray *leftEntries = [NSMutableArray array];
    for (NSInteger i = 0; i < idx; i++) {
        [leftEntries addObject:self.entries[i]];
    }
    MSTNode *leftNode = [[MSTNode alloc] initWithLevel:self.level left:self.left entries:leftEntries];
    if (idx == 0) {
        leftNode.left = splitLeft;
    } else {
        leftEntries[idx-1].internalTree = splitLeft;
    }
    
    NSMutableArray *rightEntries = [NSMutableArray array];
    for (NSInteger i = idx; i < self.entries.count; i++) {
        [rightEntries addObject:self.entries[i]];
    }
    MSTNode *rightNode = [[MSTNode alloc] initWithLevel:self.level left:splitRight entries:rightEntries];
    
    *leftOut = [leftNode trim];
    *rightOut = [rightNode trim];
}

- (MSTNode *)trim {
    if (self.entries.count == 0 && self.left) {
        return [self.left trim];
    }
    return self;
}

#pragma mark - Old stubs
- (NSData *)serialize { return [NSData data]; }
- (NSData *)computeHash { return [NSData data]; }
- (void)setNodeHash:(CID *)hash {}
- (NSArray<MSTEntry *> *)fullEntries { return @[]; }

@end

#pragma mark - MST implementation

@interface MST ()
@property (nonatomic, strong, readwrite) MSTNode *root;
@property (nonatomic, strong, readwrite) NSData *emptyTreeHash;
@end

@implementation MST

- (instancetype)initWithRootCID:(CID *)rootCID {
    self = [super init];
    if (self) {
        if (rootCID) {
            // In a real implementation, we would load the tree from storage.
            // For now, we'll start empty if we don't have the node data.
            _root = [[MSTNode alloc] initWithLevel:0];
        } else {
            _root = [[MSTNode alloc] initWithLevel:0];
        }
        _emptyTreeHash = [self computeEmptyTreeHash];
    }
    return self;
}

- (instancetype)init {
    return [self initWithRootCID:nil];
}

- (NSData *)computeEmptyTreeHash {
    // Empty tree root is hash of {"e":[]}
    NSDictionary *dict = @{[CBORValue textString:@"e"]: [CBORValue array:@[]]};
    NSData *cbor = [[CBORValue map:dict] encode];
    return [CID sha256Digest:cbor];
}

- (CID *)rootCID {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    return [self.root getCID:cache];
}

+ (uint32_t)keyDepth:(NSString *)key {
    return [self keyDepthBytes:[key dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (uint32_t)keyDepthBytes:(NSData *)keyBytes {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(keyBytes.bytes, (CC_LONG)keyBytes.length, hash);

    uint32_t zeroCount = 0;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t byte = hash[i];
        if (byte == 0) {
            zeroCount += 8;
        } else {
            if ((byte & 0xF0) == 0) {
                zeroCount += 4;
                byte <<= 4;
            }
            if ((byte & 0xC0) == 0) {
                zeroCount += 2;
                byte <<= 2;
            }
            if ((byte & 0x80) == 0) {
                zeroCount += 1;
            }
            break;
        }
    }

    return zeroCount / 2;
}

- (nullable CID *)get:(NSString *)key {
    return [self get:key subKey:nil];
}

- (nullable CID *)get:(NSString *)key subKey:(NSString *)subKey {
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    return [self getRecursive:self.root key:fullKey];
}

- (CID *)getRecursive:(MSTNode *)node key:(NSString *)key {
    NSInteger idx = 0;
    while (idx < node.entries.count && [node.entries[idx].key compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    if (idx < node.entries.count && [node.entries[idx].key isEqualToString:key]) {
        return node.entries[idx].value;
    }
    
    MSTNode *subtree = (idx == 0) ? node.left : node.entries[idx-1].internalTree;
    if (subtree) {
        return [self getRecursive:subtree key:key];
    }
    return nil;
}

- (void)put:(NSString *)key valueCID:(CID *)valueCID {
    [self put:key valueCID:valueCID subKey:nil];
}

- (void)put:(NSString *)key valueCID:(CID *)valueCID subKey:(NSString *)subKey {
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    uint32_t depth = [MST keyDepth:fullKey];
    self.root = [self addRecursive:self.root key:fullKey value:valueCID depth:depth];
}

- (MSTNode *)addRecursive:(MSTNode *)node key:(NSString *)key value:(CID *)value depth:(uint32_t)depth {
    if (depth > node.level) {
        MSTNode *splitLeft = nil;
        MSTNode *splitRight = nil;
        [node split:key left:&splitLeft right:&splitRight];
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] initWithKey:key value:value tree:splitRight];
        return [[MSTNode alloc] initWithLevel:depth left:splitLeft entries:@[newEntry]];
    }
    
    NSInteger idx = 0;
    while (idx < node.entries.count && [node.entries[idx].key compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    if (idx < node.entries.count && [node.entries[idx].key isEqualToString:key]) {
        MSTNodeEntry *oldEntry = node.entries[idx];
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] initWithKey:key value:value tree:oldEntry.internalTree];
        NSMutableArray *newEntries = [node.entries mutableCopy];
        newEntries[idx] = newEntry;
        return [[MSTNode alloc] initWithLevel:node.level left:node.left entries:newEntries];
    }
    
    if (depth == node.level) {
        MSTNode *subtree = (idx == 0) ? node.left : node.entries[idx-1].internalTree;
        MSTNode *splitLeft = nil;
        MSTNode *splitRight = nil;
        if (subtree) {
            [subtree split:key left:&splitLeft right:&splitRight];
        }
        
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] initWithKey:key value:value tree:splitRight];
        NSMutableArray *newEntries = [node.entries mutableCopy];
        [newEntries insertObject:newEntry atIndex:idx];
        
        MSTNode *newNode = [[MSTNode alloc] initWithLevel:node.level left:node.left entries:newEntries];
        if (idx == 0) {
            newNode.left = splitLeft;
        } else {
            // Note: we need to update the previous entry's tree pointer
            MSTNodeEntry *prevEntry = newEntries[idx-1];
            MSTNodeEntry *updatedPrev = [[MSTNodeEntry alloc] initWithKey:prevEntry.key value:prevEntry.value tree:splitLeft];
            newEntries[idx-1] = updatedPrev;
        }
        return newNode;
    }
    
    // depth < node.level
    MSTNode *subtree = (idx == 0) ? node.left : node.entries[idx-1].internalTree;
    if (!subtree) subtree = [[MSTNode alloc] initWithLevel:0];
    MSTNode *newSubtree = [self addRecursive:subtree key:key value:value depth:depth];
    
    NSMutableArray *newEntries = [node.entries mutableCopy];
    MSTNode *newNode = [[MSTNode alloc] initWithLevel:node.level left:node.left entries:newEntries];
    if (idx == 0) {
        newNode.left = newSubtree;
    } else {
        MSTNodeEntry *prevEntry = newEntries[idx-1];
        MSTNodeEntry *updatedPrev = [[MSTNodeEntry alloc] initWithKey:prevEntry.key value:prevEntry.value tree:newSubtree];
        newEntries[idx-1] = updatedPrev;
    }
    return newNode;
}

- (void)delete:(NSString *)key {
    [self delete:key subKey:nil];
}

- (void)delete:(NSString *)key subKey:(NSString *)subKey {
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    self.root = [self deleteRecursive:self.root key:fullKey];
}

- (MSTNode *)deleteRecursive:(MSTNode *)node key:(NSString *)key {
    NSInteger idx = 0;
    while (idx < node.entries.count && [node.entries[idx].key compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    if (idx < node.entries.count && [node.entries[idx].key isEqualToString:key]) {
        MSTNodeEntry *entryToDelete = node.entries[idx];
        MSTNode *leftSubtree = (idx == 0) ? node.left : node.entries[idx-1].internalTree;
        MSTNode *rightSubtree = entryToDelete.internalTree;
        
        MSTNode *merged = [self merge:leftSubtree and:rightSubtree];
        
        NSMutableArray *newEntries = [node.entries mutableCopy];
        [newEntries removeObjectAtIndex:idx];
        
        MSTNode *newNode = [[MSTNode alloc] initWithLevel:node.level left:node.left entries:newEntries];
        if (idx == 0) {
            newNode.left = merged;
        } else {
            MSTNodeEntry *prevEntry = newEntries[idx-1];
            MSTNodeEntry *updatedPrev = [[MSTNodeEntry alloc] initWithKey:prevEntry.key value:prevEntry.value tree:merged];
            newEntries[idx-1] = updatedPrev;
        }
        return [newNode trim];
    }
    
    MSTNode *subtree = (idx == 0) ? node.left : node.entries[idx-1].internalTree;
    if (subtree) {
        MSTNode *newSubtree = [self deleteRecursive:subtree key:key];
        NSMutableArray *newEntries = [node.entries mutableCopy];
        MSTNode *newNode = [[MSTNode alloc] initWithLevel:node.level left:node.left entries:newEntries];
        if (idx == 0) {
            newNode.left = newSubtree;
        } else {
            MSTNodeEntry *prevEntry = newEntries[idx-1];
            MSTNodeEntry *updatedPrev = [[MSTNodeEntry alloc] initWithKey:prevEntry.key value:prevEntry.value tree:newSubtree];
            newEntries[idx-1] = updatedPrev;
        }
        return [newNode trim];
    }
    return node;
}

- (MSTNode *)merge:(MSTNode *)left and:(MSTNode *)right {
    if (!left) return right;
    if (!right) return left;
    
    if (left.level > right.level) {
        NSMutableArray *newEntries = [left.entries mutableCopy];
        MSTNodeEntry *lastEntry = newEntries.lastObject;
        MSTNodeEntry *updatedLast = [[MSTNodeEntry alloc] initWithKey:lastEntry.key value:lastEntry.value tree:[self merge:lastEntry.internalTree and:right]];
        newEntries[newEntries.count-1] = updatedLast;
        return [[MSTNode alloc] initWithLevel:left.level left:left.left entries:newEntries];
    } else if (right.level > left.level) {
        return [[MSTNode alloc] initWithLevel:right.level left:[self merge:left and:right.left] entries:right.entries];
    } else {
        // Levels are equal, which shouldn't happen in a valid MST if keys are unique and properly depth-assigned
        // But for robustness, we merge entries.
        NSMutableArray *newEntries = [left.entries mutableCopy];
        [newEntries addObjectsFromArray:right.entries];
        return [[MSTNode alloc] initWithLevel:left.level left:left.left entries:newEntries];
    }
}

- (NSArray<MSTEntry *> *)allEntries {
    NSMutableArray<MSTEntry *> *result = [NSMutableArray array];
    [self walk:self.root callback:^(MSTNodeEntry *entry) {
        [result addObject:[MSTEntry entryWithKey:entry.key valueCID:entry.value]];
    }];
    return result;
}

- (void)walk:(MSTNode *)node callback:(void(^)(MSTNodeEntry *))callback {
    if (node.left) [self walk:node.left callback:callback];
    for (MSTNodeEntry *entry in node.entries) {
        callback(entry);
        if (entry.internalTree) [self walk:entry.internalTree callback:callback];
    }
}

- (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix {
    NSMutableArray<MSTEntry *> *result = [NSMutableArray array];
    [self walk:self.root callback:^(MSTNodeEntry *entry) {
        if ([entry.key hasPrefix:prefix]) {
            [result addObject:[MSTEntry entryWithKey:entry.key valueCID:entry.value]];
        }
    }];
    return result;
}

- (NSData *)exportCAR {
    return [NSData data]; // Stub
}

- (NSData *)serializeToCBOR {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    return [self.root serializeToCBOR:cache];
}

+ (nullable instancetype)deserializeFromCBOR:(NSData *)data {
    return nil; // Stub
}

@end
