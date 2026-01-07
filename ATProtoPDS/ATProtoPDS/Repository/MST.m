#import "MST.h"
#import "CBOR.h"
#import "../CID.h"
#import <CommonCrypto/CommonDigest.h>

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

    uint16_t keyLen = (uint16_t)[self keyLength];
    [data appendBytes:&keyLen length:2];

    NSData *keyData = [self keyBytes];
    [data appendData:keyData];

    NSData *cidBytes = [self.valueCID bytes];
    uint16_t cidLen = (uint16_t)cidBytes.length;
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

- (NSData *)serialize {
    NSMutableData *data = [NSMutableData data];

    uint8_t p = (uint8_t)self.prefixLen;
    [data appendBytes:&p length:1];

    uint16_t kLen = (uint16_t)self.keySuffix.length;
    [data appendBytes:&kLen length:2];
    [data appendData:self.keySuffix];

    NSData *vBytes = [self.value bytes];
    uint16_t vLen = (uint16_t)vBytes.length;
    [data appendBytes:&vLen length:2];
    [data appendData:vBytes];

    if (self.tree) {
        NSData *tBytes = [self.tree bytes];
        uint16_t tLen = (uint16_t)tBytes.length;
        [data appendBytes:&tLen length:2];
        [data appendData:tBytes];
    } else {
        uint16_t zero = 0;
        [data appendBytes:&zero length:2];
    }

    return data;
}

@end

#pragma mark - MSTNode

@interface MSTNode ()

@property (nonatomic, assign, readwrite) MSTNodeKind kind;
@property (nonatomic, strong, readwrite, nullable) CID *nodeHash;
@property (nonatomic, copy, readwrite) NSArray<MSTNodeEntry *> *entries;
@property (nonatomic, strong, readwrite, nullable) CID *left;

@end

@implementation MSTNode

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

- (NSData *)serialize {
    NSMutableData *data = [NSMutableData data];

    if (self.left) {
        NSData *leftBytes = [self.left bytes];
        uint16_t leftLen = (uint16_t)leftBytes.length;
        [data appendBytes:&leftLen length:2];
        [data appendData:leftBytes];
    } else {
        uint16_t zero = 0;
        [data appendBytes:&zero length:2];
    }

    uint16_t entryCount = (uint16_t)self.entries.count;
    [data appendBytes:&entryCount length:2];

    for (MSTNodeEntry *entry in self.entries) {
        [data appendData:[entry serialize]];
    }

    return data;
}

- (NSData *)computeHash {
    NSData *serialized = [self serialize];
    return [CID sha256Digest:serialized];
}

- (void)setNodeHash:(CID *)hash {
    _nodeHash = hash;
}

- (NSArray<MSTEntry *> *)fullEntries {
    return @[];
}

@end

#pragma mark - MST

@interface MST ()

@property (nonatomic, strong, readwrite, nullable) CID *rootCID;
@property (nonatomic, strong, readwrite) NSData *emptyTreeHash;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CID *> *storage;

@end

@implementation MST

- (instancetype)initWithRootCID:(CID *)rootCID {
    self = [super init];
    if (self) {
        _rootCID = rootCID;
        _storage = [NSMutableDictionary dictionary];
        _emptyTreeHash = [self computeEmptyTreeHash];
    }
    return self;
}

- (instancetype)init {
    return [self initWithRootCID:nil];
}

- (NSData *)computeEmptyTreeHash {
    return [CID sha256Digest:[NSData data]];
}

+ (NSUInteger)keyDepth:(NSData *)keyBytes {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(keyBytes.bytes, (CC_LONG)keyBytes.length, hash);

    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    const uint8_t *hashBytes = hashData.bytes;

    NSUInteger zeroCount = 0;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t byte = hashBytes[i];
        if (byte == 0) {
            zeroCount += 8;
        } else if (byte & 0x80) {
            break;
        } else if (byte & 0x40) {
            zeroCount += 7;
            break;
        } else if (byte & 0x20) {
            zeroCount += 6;
            break;
        } else if (byte & 0x10) {
            zeroCount += 5;
            break;
        } else if (byte & 0x08) {
            zeroCount += 4;
            break;
        } else if (byte & 0x04) {
            zeroCount += 3;
            break;
        } else if (byte & 0x02) {
            zeroCount += 2;
            break;
        } else if (byte & 0x01) {
            zeroCount += 1;
            break;
        }
    }

    return zeroCount / 2;
}

- (CID *)get:(NSString *)key {
    return [self get:key subKey:nil];
}

- (CID *)get:(NSString *)key subKey:(NSString *)subKey {
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    return self.storage[fullKey];
}

- (void)put:(NSString *)key valueCID:(CID *)valueCID {
    [self put:key valueCID:valueCID subKey:nil];
}

- (void)put:(NSString *)key valueCID:(CID *)valueCID subKey:(NSString *)subKey {
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    self.storage[fullKey] = valueCID;
}

- (void)delete:(NSString *)key {
    [self delete:key subKey:nil];
}

- (void)delete:(NSString *)key subKey:(NSString *)subKey {
    NSString *fullKey = subKey ? [NSString stringWithFormat:@"%@/%@", key, subKey] : key;
    [self.storage removeObjectForKey:fullKey];
}

- (NSArray<MSTEntry *> *)allEntries {
    NSMutableArray<MSTEntry *> *result = [NSMutableArray array];

    NSArray *sortedKeys = [[self.storage allKeys] sortedArrayUsingSelector:@selector(compare:)];

    for (NSString *fullKey in sortedKeys) {
        NSString *key = fullKey;
        NSString *subKey = nil;

        NSRange slashRange = [fullKey rangeOfString:@"/"];
        if (slashRange.location != NSNotFound) {
            key = [fullKey substringToIndex:slashRange.location];
            subKey = [fullKey substringFromIndex:slashRange.location + 1];
        }

        CID *valueCID = self.storage[fullKey];
        MSTEntry *entry = [MSTEntry entryWithKey:key valueCID:valueCID subKey:subKey];
        [result addObject:entry];
    }

    return [result copy];
}

- (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix {
    NSMutableArray<MSTEntry *> *result = [NSMutableArray array];

    NSArray *sortedKeys = [[self.storage allKeys] sortedArrayUsingSelector:@selector(compare:)];

    for (NSString *fullKey in sortedKeys) {
        if ([fullKey hasPrefix:prefix]) {
            NSString *key = fullKey;
            NSString *subKey = nil;

            NSRange slashRange = [fullKey rangeOfString:@"/"];
            if (slashRange.location != NSNotFound) {
                key = [fullKey substringToIndex:slashRange.location];
                subKey = [fullKey substringFromIndex:slashRange.location + 1];
            }

            CID *valueCID = self.storage[fullKey];
            MSTEntry *entry = [MSTEntry entryWithKey:key valueCID:valueCID subKey:subKey];
            [result addObject:entry];
        }
    }

    return [result copy];
}

- (NSData *)exportCAR {
    NSMutableData *carData = [NSMutableData data];

    uint8_t header[] = {
        0x00, 0x61, 0x70, 0x70, 0x6c, 0x69, 0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x2f, 0x63, 0x61, 0x72
    };
    uint8_t version[] = {0x01, 0x00};
    uint8_t rootCidLength = (uint8_t)(self.rootCID ? self.rootCID.bytes.length : 0);

    [carData appendBytes:header length:sizeof(header)];
    [carData appendBytes:version length:sizeof(version)];
    [carData appendBytes:&rootCidLength length:1];

    if (self.rootCID) {
        [carData appendData:[self.rootCID bytes]];
    }

    return [carData copy];
}

- (NSData *)serializeToCBOR {
    NSMutableArray<CBORValue *> *entries = [NSMutableArray array];

    NSArray *sortedKeys = [[self.storage allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *fullKey in sortedKeys) {
        NSString *key = fullKey;
        NSString *subKey = nil;

        NSRange slashRange = [fullKey rangeOfString:@"/"];
        if (slashRange.location != NSNotFound) {
            key = [fullKey substringToIndex:slashRange.location];
            subKey = [fullKey substringFromIndex:slashRange.location + 1];
        }

        CID *valueCID = self.storage[fullKey];
        NSData *cidBytes = [valueCID bytes];

        NSMutableDictionary<CBORValue *, CBORValue *> *entryDict = [NSMutableDictionary dictionary];
        entryDict[[CBORValue textString:@"k"]] = [CBORValue textString:key];
        entryDict[[CBORValue textString:@"v"]] = [CBORValue byteString:cidBytes];

        if (subKey) {
            entryDict[[CBORValue textString:@"sub"]] = [CBORValue textString:subKey];
        }

        [entries addObject:[CBORValue map:entryDict]];
    }

    NSDictionary<CBORValue *, CBORValue *> *treeDict = @{
        [CBORValue textString:@"l"]: [CBORValue array:entries]
    };

    CBORValue *treeValue = [CBORValue map:treeDict];
    return [treeValue encode];
}

+ (nullable instancetype)deserializeFromCBOR:(NSData *)data {
    CBORValue *cbor = [CBORValue decode:data];
    if (!cbor || cbor.type != CBORTypeMap) {
        return nil;
    }

    MST *mst = [[MST alloc] init];

    CBORValue *entriesArray = cbor.map[[CBORValue textString:@"l"]];
    if (entriesArray && entriesArray.type == CBORTypeArray) {
        for (CBORValue *entryCbor in entriesArray.array) {
            if (entryCbor.type != CBORTypeMap) {
                continue;
            }

            CBORValue *keyVal = entryCbor.map[[CBORValue textString:@"k"]];
            CBORValue *valVal = entryCbor.map[[CBORValue textString:@"v"]];
            CBORValue *subVal = entryCbor.map[[CBORValue textString:@"sub"]];

            if (!keyVal || !valVal || keyVal.type != CBORTypeTextString || valVal.type != CBORTypeByteString) {
                continue;
            }

            NSString *key = keyVal.textString;
            NSData *cidData = valVal.byteString;
            CID *cid = [CID cidWithMultihash:cidData codec:0x71];

            NSString *subKey = nil;
            if (subVal && subVal.type == CBORTypeTextString) {
                subKey = subVal.textString;
            }

            if (key && cid) {
                [mst put:key valueCID:cid subKey:subKey];
            }
        }
    }

    return mst;
}

@end
