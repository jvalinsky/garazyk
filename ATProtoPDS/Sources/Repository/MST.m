#import "Repository/MST.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"
#import <CommonCrypto/CommonDigest.h>
#import "Compat/Endian.h"
#import <objc/runtime.h>

#pragma mark - Internal Classes

@interface MSTNodeEntry ()
@property (nonatomic, strong, readwrite, nullable) MSTNode *internalTree;
@property (nonatomic, copy, readwrite) NSString *fullKey;
@end

@interface MSTNode ()
@property (nonatomic, assign, readwrite) uint32_t level;
@property (nonatomic, strong, readwrite, nullable) MSTNode *internalLeft;
@property (nonatomic, strong, readwrite) NSMutableArray<MSTNodeEntry *> *internalEntries;
- (instancetype)initWithLevel:(uint32_t)level;
- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache;
- (void)split:(NSString *)key left:(MSTNode **)leftOut right:(MSTNode **)rightOut;
- (MSTNode *)trim;
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

    uint16_t keyLen = OSSwapHostToBigInt16((uint16_t)[self keyLength]);
    [data appendBytes:&keyLen length:2];

    NSData *keyData = [self keyBytes];
    [data appendData:keyData];

    NSData *cidBytes = [self.valueCID bytes];
    uint16_t cidLen = OSSwapHostToBigInt16((uint16_t)cidBytes.length);
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

    uint16_t kLen = OSSwapHostToBigInt16((uint16_t)self.keySuffix.length);
    [data appendBytes:&kLen length:2];
    [data appendData:self.keySuffix];

    NSData *vBytes = [self.value bytes];
    uint16_t vLen = OSSwapHostToBigInt16((uint16_t)vBytes.length);
    [data appendBytes:&vLen length:2];
    [data appendData:vBytes];

    CID *tCID = self.tree;
    uint16_t tLen = tCID ? OSSwapHostToBigInt16((uint16_t)[tCID bytes].length) : 0;
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

- (CID *)left {
    return [self.internalLeft getCID:[NSMapTable strongToStrongObjectsMapTable]];
}

- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache {
    if (!self) return nil;
    CID *cached = [cache objectForKey:self];
    if (cached) return cached;
    
    NSData *cbor = [self serializeToCBOR:cache];
    CID *cid = [CID cidWithMultihash:[CID sha256Digest:cbor] codec:0x71];
    [cache setObject:cid forKey:self];
    return cid;
}

- (NSData *)serializeToCBOR:(NSMapTable<MSTNode *, CID *> *)cache {
    NSMutableArray<CBORValue *> *entriesCBOR = [NSMutableArray array];
    NSString *prevKey = @"";
    
    for (MSTNodeEntry *entry in self.internalEntries) {
        NSUInteger p = 0;
        NSUInteger minLen = MIN(prevKey.length, entry.fullKey.length);
        
        for (NSUInteger i = 0; i < minLen; i++) {
            if ([prevKey characterAtIndex:i] == [entry.fullKey characterAtIndex:i]) {
                p++;
            } else {
                break;
            }
        }
        
        NSData *fullKeyData = [entry.fullKey dataUsingEncoding:NSUTF8StringEncoding];
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
        } else {
            dict[[CBORValue textString:@"t"]] = [CBORValue nilValue];
        }
        
        NSMutableData *vData = [NSMutableData dataWithBytes:"\x00" length:1];
        [vData appendData:entry.value.bytes];
        dict[[CBORValue textString:@"v"]] = [CBORValue tag:42 value:[CBORValue byteString:vData]];
        
        [entriesCBOR addObject:[CBORValue map:dict]];
        prevKey = entry.fullKey;
    }
    
    // NodeData spec order: e, l
    NSMutableDictionary<CBORValue *, CBORValue *> *nodeDict = [NSMutableDictionary dictionary];
    nodeDict[[CBORValue textString:@"e"]] = [CBORValue array:entriesCBOR];
    if (self.internalLeft) {
        CID *lCID = [self.internalLeft getCID:cache];
        NSMutableData *lData = [NSMutableData dataWithBytes:"\x00" length:1];
        [lData appendData:lCID.bytes];
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue tag:42 value:[CBORValue byteString:lData]];
    } else {
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue nilValue];
    }
    
    return [[CBORValue map:nodeDict] encode];
}

- (void)split:(NSString *)key left:(MSTNode **)leftOut right:(MSTNode **)rightOut {
    NSInteger idx = 0;
    while (idx < self.internalEntries.count && [self.internalEntries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    NSArray *leftData = [self.internalEntries subarrayWithRange:NSMakeRange(0, idx)];
    NSArray *rightData = [self.internalEntries subarrayWithRange:NSMakeRange(idx, self.internalEntries.count - idx)];
    
    MSTNode *leftNode = [[MSTNode alloc] initWithLevel:self.level left:self.internalLeft entries:leftData];
    MSTNode *rightNode = [[MSTNode alloc] initWithLevel:self.level left:nil entries:rightData];
    
    if (leftData.count > 0) {
        MSTNodeEntry *lastInLeft = leftData.lastObject;
        if (lastInLeft.internalTree) {
            NSMutableArray *nLeftEntries = [leftData mutableCopy];
            [nLeftEntries removeLastObject];
            leftNode.internalEntries = nLeftEntries;
            
            MSTNode *subL = nil;
            MSTNode *subR = nil;
            [lastInLeft.internalTree split:key left:&subL right:&subR];
            
            if (subL) {
                MSTNodeEntry *newLast = [[MSTNodeEntry alloc] initWithKey:lastInLeft.fullKey value:lastInLeft.value tree:subL];
                [nLeftEntries addObject:newLast];
            }
            if (subR) {
                rightNode.internalLeft = subR;
            }
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

#pragma mark - Stubs & Compatibility
- (NSData *)serialize { return [NSData data]; }
- (NSData *)computeHash { return [NSData data]; }
- (void)setNodeHash:(CID *)hash {}
- (NSArray<MSTEntry *> *)fullEntries { return @[]; }
- (instancetype)initWithKind:(MSTNodeKind)kind entries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left { return [self init]; }
+ (instancetype)leafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries { return [[self alloc] initWithLevel:0 left:nil entries:entries]; }
+ (instancetype)nonLeafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left {
    return [[self alloc] initWithLevel:1];
}

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
        _root = [[MSTNode alloc] initWithLevel:0];
        _emptyTreeHash = [self computeEmptyTreeHash];
    }
    return self;
}

- (instancetype)init {
    return [self initWithRootCID:nil];
}

- (NSData *)computeEmptyTreeHash {
    NSDictionary *dict = @{
        [CBORValue textString:@"e"]: [CBORValue array:@[]],
        [CBORValue textString:@"l"]: [CBORValue nilValue]
    };
    NSData *cbor = [[CBORValue map:dict] encode];
    
    // DEBUG: Print CBOR bytes
    const uint8_t *bytes = cbor.bytes;
    fprintf(stderr, "DEBUG: Empty MST CBOR (%lu bytes): ", (unsigned long)cbor.length);
    for (NSUInteger i = 0; i < cbor.length; i++) {
        fprintf(stderr, "%02X ", bytes[i]);
    }
    fprintf(stderr, "\n");
    
    return [CID sha256Digest:cbor];
}

- (CID *)rootCID {
    return [self.root getCID:[NSMapTable strongToStrongObjectsMapTable]];
}

+ (uint32_t)keyDepth:(NSString *)key {
    const char *utf8 = [key UTF8String];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(utf8, (CC_LONG)strlen(utf8), hash);

    uint32_t zeroCount = 0;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t byte = hash[i];
        if (byte == 0) {
            zeroCount += 4;
            continue;
        }
        if ((byte & 0xC0) != 0) {
            break;
        }
        if ((byte & 0xFC) == 0) {
            zeroCount += 3;
        } else if ((byte & 0xF0) == 0) {
            zeroCount += 2;
        } else {
            zeroCount += 1;
        }
        break;
    }

    return zeroCount;
}

+ (NSUInteger)keyDepthString:(NSString *)key {
    return [self keyDepthBytes:[key dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (NSUInteger)keyDepthBytes:(NSData *)keyBytes {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(keyBytes.bytes, (CC_LONG)keyBytes.length, hash);

    uint32_t zeroCount = 0;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t byte = hash[i];
        if (byte == 0) {
            zeroCount += 4;
            continue;
        }
        if ((byte & 0xC0) != 0) {
            break;
        }
        if ((byte & 0xFC) == 0) {
            zeroCount += 3;
        } else if ((byte & 0xF0) == 0) {
            zeroCount += 2;
        } else {
            zeroCount += 1;
        }
        break;
    }

    return zeroCount;
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
    NSInteger idx = 0;
    while (idx < node.internalEntries.count && [node.internalEntries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    if (idx < node.internalEntries.count && [node.internalEntries[idx].fullKey isEqualToString:key]) {
        return node.internalEntries[idx].value;
    }
    
    MSTNode *subtree = (idx == 0) ? node.internalLeft : node.internalEntries[idx-1].internalTree;
    return [self getRecursive:subtree key:key];
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
    
    NSInteger idx = 0;
    while (idx < node.internalEntries.count && [node.internalEntries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    if (idx < node.internalEntries.count && [node.internalEntries[idx].fullKey isEqualToString:key]) {
        MSTNodeEntry *oldEntry = node.internalEntries[idx];
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] initWithKey:key value:value tree:oldEntry.internalTree];
        NSMutableArray *newEntries = [node.internalEntries mutableCopy];
        newEntries[idx] = newEntry;
        return [[MSTNode alloc] initWithLevel:node.level left:node.internalLeft entries:newEntries];
    }
    
    if (depth == node.level) {
        MSTNode *subtree = (idx == 0) ? node.internalLeft : node.internalEntries[idx-1].internalTree;
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
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    self.root = [self deleteRecursive:self.root key:fullKey];
    if (!self.root) self.root = [[MSTNode alloc] initWithLevel:0];
}

- (MSTNode *)deleteRecursive:(MSTNode *)node key:(NSString *)key {
    if (!node) return nil;
    NSInteger idx = 0;
    while (idx < node.internalEntries.count && [node.internalEntries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    if (idx < node.internalEntries.count && [node.internalEntries[idx].fullKey isEqualToString:key]) {
        MSTNodeEntry *entryToDelete = node.internalEntries[idx];
        MSTNode *leftSubtree = (idx == 0) ? node.internalLeft : node.internalEntries[idx-1].internalTree;
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
    
    MSTNode *subtree = (idx == 0) ? node.internalLeft : node.internalEntries[idx-1].internalTree;
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
    if (left.level != right.level) return nil;
    
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
        if (right.internalLeft) {
            if (lastInLeft) {
                MSTNodeEntry *updatedLast = [[MSTNodeEntry alloc] initWithKey:lastInLeft.fullKey value:lastInLeft.value tree:right.internalLeft];
                newEntries[newEntries.count-1] = updatedLast;
            } else {
                left.internalLeft = [self merge:left.internalLeft and:right.internalLeft];
            }
        }
        [newEntries addObjectsFromArray:right.internalEntries];
        return [[MSTNode alloc] initWithLevel:left.level left:left.internalLeft entries:newEntries];
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

- (NSData *)exportCAR { return [NSData data]; }
- (NSData *)serializeToCBOR {
    return [self.root serializeToCBOR:[NSMapTable strongToStrongObjectsMapTable]];
}
+ (nullable instancetype)deserializeFromCBOR:(NSData *)data { return nil; }

@end
