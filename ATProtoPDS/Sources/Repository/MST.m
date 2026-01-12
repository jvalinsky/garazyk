#import "Repository/MST.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"
#import <CommonCrypto/CommonDigest.h>
#import <arpa/inet.h>
#import <objc/runtime.h>

#pragma mark - Internal Classes

@interface MSTInternalNode : NSObject <NSCopying>
@property (nonatomic, assign) uint32_t level;
@property (nonatomic, strong, nullable) MSTInternalNode *left;
@property (nonatomic, strong) NSMutableArray<MSTNodeEntry *> *entries;
- (instancetype)initWithLevel:(uint32_t)level;
- (CID *)getCID:(NSMutableDictionary<MSTInternalNode *, CID *> *)cache;
- (void)split:(NSString *)key left:(MSTInternalNode * _Nullable * _Nonnull)leftOut right:(MSTInternalNode * _Nullable * _Nonnull)rightOut;
- (MSTInternalNode *)trim;
@end

@interface MSTNodeEntry (Internal)
@property (nonatomic, copy, nullable) NSString *fullKey;
@property (nonatomic, strong, nullable) MSTInternalNode *internalTree;
@end

@implementation MSTNodeEntry (Internal)
static char const * const kMSTNodeEntryFullKey = "fullKey";
static char const * const kMSTNodeEntryInternalTree = "internalTree";

- (void)setFullKey:(NSString *)fullKey {
    objc_setAssociatedObject(self, kMSTNodeEntryFullKey, fullKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
- (NSString *)fullKey {
    return objc_getAssociatedObject(self, kMSTNodeEntryFullKey);
}
- (void)setInternalTree:(MSTInternalNode *)internalTree {
    objc_setAssociatedObject(self, kMSTNodeEntryInternalTree, internalTree, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (MSTInternalNode *)internalTree {
    return objc_getAssociatedObject(self, kMSTNodeEntryInternalTree);
}
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
    [data appendData:[self keyBytes]];
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
    uint16_t tLen = self.tree ? htons((uint16_t)[self.tree bytes].length) : 0;
    [data appendBytes:&tLen length:2];
    if (self.tree) {
        [data appendData:[self.tree bytes]];
    }
    return data;
}

- (id)copyWithZone:(NSZone *)zone {
    MSTNodeEntry *copy = [[MSTNodeEntry allocWithZone:zone] init];
    copy.prefixLen = self.prefixLen;
    copy.keySuffix = [self.keySuffix copyWithZone:zone];
    copy.value = self.value;
    copy.tree = self.tree;
    copy.fullKey = self.fullKey;
    copy.internalTree = [self.internalTree copyWithZone:zone];
    return copy;
}

@end

@implementation MSTNode
@synthesize nodeHash = _nodeHash;
@synthesize entries = _entries;
@synthesize left = _left;
@synthesize kind = _kind;

+ (instancetype)leafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries {
    return [[self alloc] initWithKind:MSTNodeKindLeaf entries:entries left:nil];
}
+ (instancetype)nonLeafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries left:(CID *)left {
    return [[self alloc] initWithKind:MSTNodeKindNonLeaf entries:entries left:left];
}
- (instancetype)initWithKind:(MSTNodeKind)kind entries:(NSArray<MSTNodeEntry *> *)entries left:(CID *)left {
    self = [super init];
    if (self) {
        _kind = kind;
        _entries = [entries copy];
        _left = left;
    }
    return self;
}
- (NSData *)serialize { return [NSData data]; }
- (NSData *)computeHash { return [NSData data]; }
- (void)setNodeHash:(CID *)hash { _nodeHash = hash; }
- (NSArray<MSTEntry *> *)fullEntries { return @[]; }
@end

@implementation MSTInternalNode

- (instancetype)initWithLevel:(uint32_t)level {
    self = [super init];
    if (self) {
        _level = level;
        _entries = [NSMutableArray array];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    MSTInternalNode *copy = [[MSTInternalNode allocWithZone:zone] initWithLevel:self.level];
    copy.left = [self.left copyWithZone:zone];
    for (MSTNodeEntry *entry in self.entries) {
        [copy.entries addObject:[entry copyWithZone:zone]];
    }
    return copy;
}

- (CID *)getCID:(NSMutableDictionary<MSTInternalNode *, CID *> *)cache {
    if (cache[self]) return cache[self];
    NSData *cbor = [self serializeToCBOR:cache];
    CID *cid = [CID cidWithDigest:[CID sha256Digest:cbor] codec:0x71];
    cache[self] = cid;
    return cid;
}

- (NSData *)serializeToCBOR:(NSMutableDictionary<MSTInternalNode *, CID *> *)cache {
    NSMutableArray<CBORValue *> *entriesCBOR = [NSMutableArray array];
    NSString *prevKey = @"";
    for (MSTNodeEntry *entry in self.entries) {
        NSString *fullKey = entry.fullKey;
        NSUInteger p = 0;
        NSUInteger minLen = MIN(prevKey.length, fullKey.length);
        for (NSUInteger i = 0; i < minLen; i++) {
            if ([prevKey characterAtIndex:i] == [fullKey characterAtIndex:i]) p++;
            else break;
        }
        NSData *kSuffix = [[fullKey substringFromIndex:p] dataUsingEncoding:NSUTF8StringEncoding];
        
        NSMutableDictionary<CBORValue *, CBORValue *> *dict = [NSMutableDictionary dictionary];
        dict[[CBORValue textString:@"k"]] = [CBORValue byteString:kSuffix];
        dict[[CBORValue textString:@"p"]] = [CBORValue unsignedInteger:p];
        if (entry.internalTree) {
            CID *tCID = [entry.internalTree getCID:cache];
            dict[[CBORValue textString:@"t"]] = [CBORValue tag:42 value:[CBORValue byteString:tCID.bytes]];
        }
        dict[[CBORValue textString:@"v"]] = [CBORValue tag:42 value:[CBORValue byteString:entry.value.bytes]];
        [entriesCBOR addObject:[CBORValue map:dict]];
        prevKey = fullKey;
    }
    
    NSMutableDictionary<CBORValue *, CBORValue *> *nodeDict = [NSMutableDictionary dictionary];
    nodeDict[[CBORValue textString:@"e"]] = [CBORValue array:entriesCBOR];
    if (self.left) {
        CID *lCID = [self.left getCID:cache];
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue tag:42 value:[CBORValue byteString:lCID.bytes]];
    } else {
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue nilValue];
    }
    return [[CBORValue map:nodeDict] encode];
}

- (void)split:(NSString *)key left:(MSTInternalNode **)leftOut right:(MSTInternalNode **)rightOut {
    NSInteger idx = 0;
    while (idx < self.entries.count && [self.entries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    MSTInternalNode *subtree = (idx == 0) ? self.left : self.entries[idx-1].internalTree;
    MSTInternalNode *splitLeft = nil;
    MSTInternalNode *splitRight = nil;
    if (subtree) [subtree split:key left:&splitLeft right:&splitRight];
    
    MSTInternalNode *lNode = [[MSTInternalNode alloc] initWithLevel:self.level];
    lNode.left = self.left;
    for (NSInteger i = 0; i < idx; i++) [lNode.entries addObject:[self.entries[i] copy]];
    if (idx == 0) lNode.left = splitLeft;
    else lNode.entries[idx-1].internalTree = splitLeft;
    
    MSTInternalNode *rNode = [[MSTInternalNode alloc] initWithLevel:self.level];
    rNode.left = splitRight;
    for (NSInteger i = idx; i < self.entries.count; i++) [rNode.entries addObject:[self.entries[i] copy]];
    
    *leftOut = [lNode trim];
    *rightOut = [rNode trim];
}

- (MSTInternalNode *)trim {
    if (self.entries.count == 0 && self.left) return [self.left trim];
    return self;
}

@end

@interface MST ()
@property (nonatomic, strong, readwrite) MSTInternalNode *root;
@property (nonatomic, strong, readwrite) NSData *emptyTreeHash;
@end

@implementation MST

- (instancetype)initWithRootCID:(CID *)rootCID {
    self = [super init];
    if (self) {
        _root = [[MSTInternalNode alloc] initWithLevel:0];
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
    CID *cid = [CID cidWithDigest:[CID sha256Digest:cbor] codec:0x71];
    return cid.bytes;
}

- (CID *)rootCID {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    return [self.root getCID:cache];
}

+ (NSUInteger)keyDepthString:(NSString *)key {
    return [self keyDepthBytes:[key dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (NSUInteger)keyDepthBytes:(NSData *)keyBytes {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(keyBytes.bytes, (CC_LONG)keyBytes.length, hash);
    NSUInteger total = 0;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t b = hash[i];
        if ((b & 0xC0) != 0) break;
        if (b == 0x00) { total += 4; continue; }
        if ((b & 0xFC) == 0x00) total += 3;
        else if ((b & 0xF0) == 0x00) total += 2;
        else total += 1;
        break;
    }
    return total;
}

+ (NSUInteger)keyDepth:(NSData *)keyBytes {
    return [self keyDepthBytes:keyBytes];
}

- (nullable CID *)get:(NSString *)key {
    return [self getRecursive:self.root key:key];
}

- (nullable CID *)get:(NSString *)key subKey:(NSString *)subKey {
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    return [self getRecursive:self.root key:fullKey];
}

- (CID *)getRecursive:(MSTInternalNode *)node key:(NSString *)key {
    NSInteger idx = 0;
    while (idx < node.entries.count && [node.entries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    if (idx < node.entries.count && [node.entries[idx].fullKey isEqualToString:key]) {
        return node.entries[idx].value;
    }
    MSTInternalNode *subtree = (idx == 0) ? node.left : node.entries[idx-1].internalTree;
    if (subtree) return [self getRecursive:subtree key:key];
    return nil;
}

- (void)put:(NSString *)key valueCID:(CID *)valueCID {
    uint32_t depth = (uint32_t)[MST keyDepthString:key];
    self.root = [self addRecursive:self.root key:key value:valueCID depth:depth];
}

- (void)put:(NSString *)key valueCID:(CID *)valueCID subKey:(NSString *)subKey {
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    uint32_t depth = (uint32_t)[MST keyDepthString:fullKey];
    self.root = [self addRecursive:self.root key:fullKey value:valueCID depth:depth];
}

- (MSTInternalNode *)addRecursive:(MSTInternalNode *)node key:(NSString *)key value:(CID *)value depth:(uint32_t)depth {
    if (depth > node.level) {
        MSTInternalNode *splitLeft = nil;
        MSTInternalNode *splitRight = nil;
        [node split:key left:&splitLeft right:&splitRight];
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] init];
        newEntry.fullKey = key;
        newEntry.value = value;
        newEntry.internalTree = splitRight;
        MSTInternalNode *newNode = [[MSTInternalNode alloc] initWithLevel:depth];
        newNode.left = splitLeft;
        [newNode.entries addObject:newEntry];
        return newNode;
    }
    
    NSInteger idx = 0;
    while (idx < node.entries.count && [node.entries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    if (idx < node.entries.count && [node.entries[idx].fullKey isEqualToString:key]) {
        MSTNodeEntry *oldEntry = node.entries[idx];
        MSTNodeEntry *newEntry = [oldEntry copy];
        newEntry.value = value;
        MSTInternalNode *newNode = [node copy];
        newNode.entries[idx] = newEntry;
        return newNode;
    }
    
    if (depth == node.level) {
        MSTInternalNode *subtree = (idx == 0) ? node.left : node.entries[idx-1].internalTree;
        MSTInternalNode *splitLeft = nil;
        MSTInternalNode *splitRight = nil;
        if (subtree) [subtree split:key left:&splitLeft right:&splitRight];
        
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] init];
        newEntry.fullKey = key;
        newEntry.value = value;
        newEntry.internalTree = splitRight;
        
        MSTInternalNode *newNode = [node copy];
        [newNode.entries insertObject:newEntry atIndex:idx];
        if (idx == 0) newNode.left = splitLeft;
        else {
            MSTNodeEntry *prev = newNode.entries[idx-1];
            prev.internalTree = splitLeft;
        }
        return newNode;
    }
    
    // depth < node.level
    MSTInternalNode *subtree = (idx == 0) ? node.left : node.entries[idx-1].internalTree;
    if (!subtree) subtree = [[MSTInternalNode alloc] initWithLevel:node.level - 1];
    MSTInternalNode *newSubtree = [self addRecursive:subtree key:key value:value depth:depth];
    
    MSTInternalNode *newNode = [node copy];
    if (idx == 0) newNode.left = newSubtree;
    else {
        MSTNodeEntry *prev = newNode.entries[idx-1];
        MSTNodeEntry *updatedPrev = [prev copy];
        updatedPrev.internalTree = newSubtree;
        newNode.entries[idx-1] = updatedPrev;
    }
    return newNode;
}

- (void)delete:(NSString *)key {
    self.root = [self deleteRecursive:self.root key:key];
}

- (void)delete:(NSString *)key subKey:(NSString *)subKey {
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    self.root = [self deleteRecursive:self.root key:fullKey];
}

- (MSTInternalNode *)deleteRecursive:(MSTInternalNode *)node key:(NSString *)key {
    NSInteger idx = 0;
    while (idx < node.entries.count && [node.entries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    if (idx < node.entries.count && [node.entries[idx].fullKey isEqualToString:key]) {
        MSTNodeEntry *entryToDelete = node.entries[idx];
        MSTInternalNode *leftSubtree = (idx == 0) ? node.left : node.entries[idx-1].internalTree;
        MSTInternalNode *rightSubtree = entryToDelete.internalTree;
        MSTInternalNode *merged = [self merge:leftSubtree and:rightSubtree];
        
        MSTInternalNode *newNode = [node copy];
        [newNode.entries removeObjectAtIndex:idx];
        if (idx == 0) newNode.left = merged;
        else {
            MSTNodeEntry *prev = newNode.entries[idx-1];
            MSTNodeEntry *updatedPrev = [prev copy];
            updatedPrev.internalTree = merged;
            newNode.entries[idx-1] = updatedPrev;
        }
        return [newNode trim];
    }
    
    MSTInternalNode *subtree = (idx == 0) ? node.left : node.entries[idx-1].internalTree;
    if (subtree) {
        MSTInternalNode *newSubtree = [self deleteRecursive:subtree key:key];
        MSTInternalNode *newNode = [node copy];
        if (idx == 0) newNode.left = newSubtree;
        else {
            MSTNodeEntry *prev = newNode.entries[idx-1];
            MSTNodeEntry *updatedPrev = [prev copy];
            updatedPrev.internalTree = newSubtree;
            newNode.entries[idx-1] = updatedPrev;
        }
        return [newNode trim];
    }
    return node;
}

- (MSTInternalNode *)merge:(MSTInternalNode *)left and:(MSTInternalNode *)right {
    if (!left) return [right copy];
    if (!right) return [left copy];
    if (left.level > right.level) {
        MSTInternalNode *newNode = [left copy];
        MSTNodeEntry *lastEntry = newNode.entries.lastObject;
        lastEntry.internalTree = [self merge:lastEntry.internalTree and:right];
        return newNode;
    } else if (right.level > left.level) {
        MSTInternalNode *newNode = [right copy];
        newNode.left = [self merge:left and:right.left];
        return newNode;
    } else {
        MSTInternalNode *newNode = [left copy];
        MSTInternalNode *middle = [self merge:newNode.entries.lastObject.internalTree and:right.left];
        newNode.entries[newNode.entries.count-1].internalTree = middle;
        for (MSTNodeEntry *e in right.entries) [newNode.entries addObject:[e copy]];
        return newNode;
    }
}

- (NSArray<MSTEntry *> *)allEntries {
    NSMutableArray<MSTEntry *> *result = [NSMutableArray array];
    [self walk:self.root callback:^(MSTNodeEntry *entry) {
        [result addObject:[MSTEntry entryWithKey:entry.fullKey valueCID:entry.value]];
    }];
    return result;
}

- (void)walk:(MSTInternalNode *)node callback:(void(^)(MSTNodeEntry *))callback {
    if (node.left) [self walk:node.left callback:callback];
    for (MSTNodeEntry *entry in node.entries) {
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
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    return [self.root serializeToCBOR:cache];
}
+ (nullable instancetype)deserializeFromCBOR:(NSData *)data { return nil; }

@end
