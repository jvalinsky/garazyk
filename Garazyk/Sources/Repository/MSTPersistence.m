// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Repository/MSTPersistence.h"
#import "Repository/MST.h"
#import "Core/CBOR.h"
#import "Core/CID.h"
#import "Database/PDSDatabase.h"

static NSString *const MSTPersistenceErrorDomain = @"com.atproto.MSTPersistence";

typedef NS_ENUM(NSInteger, MSTPersistenceErrorCode) {
    MSTPersistenceErrorCodeInvalidCID = 1,
    MSTPersistenceErrorCodeBlockNotFound,
    MSTPersistenceErrorCodeCBORFormat,
    MSTPersistenceErrorCodeSerializationFailed,
};

@interface ATProtoMSTNode (MSTPersistenceAccess)
- (instancetype)initWithLevel:(uint32_t)level left:(nullable ATProtoMSTNode *)left entries:(NSArray<ATProtoMSTNodeEntry *> *)entries;
@end

@interface ATProtoMSTNodeEntry (MSTPersistenceAccess)
- (instancetype)initWithKey:(NSString *)key value:(ATProtoCID *)value tree:(nullable ATProtoMSTNode *)tree;
@end

@interface ATProtoMSTPersistence ()
- (nullable ATProtoMSTNode *)loadNodeWithCID:(ATProtoCID *)cid
                               repoDid:(NSString *)repoDid
                             database:(PDSDatabase *)database
                            nodeCache:(NSMutableDictionary<NSString *, ATProtoMSTNode *> *)nodeCache
                           levelCache:(NSMutableDictionary<NSString *, NSNumber *> *)levelCache
                       computedLevel:(uint32_t *)computedLevel
                                 error:(NSError **)error;
- (nullable ATProtoCID *)cidFromTaggedValue:(ATProtoCBORValue *)value allowNil:(BOOL)allowNil error:(NSError **)error;
@end

@implementation ATProtoMSTPersistence

+ (instancetype)shared {
    static ATProtoMSTPersistence *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _database = nil;
    }
    return self;
}

- (PDSDatabase *)getDatabase {
    return _database;
}

- (nullable ATProtoMST *)loadMSTForDid:(NSString *)did error:(NSError **)error {
    PDSDatabase *db = [self getDatabase];
    if (![db openWithError:error]) return nil;

    NSError *fetchError = nil;
    PDSDatabaseRepo *repoInfo = [db getRepoForDid:did error:&fetchError];
    if (fetchError) {
        if (error) *error = fetchError;
        return nil;
    }

    if (!repoInfo || repoInfo.rootCid.length == 0) {
        return [[ATProtoMST alloc] init];
    }

    ATProtoCID *rootCID = [ATProtoCID cidFromBytes:repoInfo.rootCid];
    if (!rootCID) {
        if (error) {
            *error = [NSError errorWithDomain:MSTPersistenceErrorDomain
                                         code:MSTPersistenceErrorCodeInvalidCID
                                     userInfo:@{NSLocalizedDescriptionKey: @"Repository root CID is invalid"}];
        }
        return nil;
    }

    NSMutableDictionary<NSString *, ATProtoMSTNode *> *nodeCache = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *levelCache = [NSMutableDictionary dictionary];
    ATProtoMSTNode *rootNode = [self loadNodeWithCID:rootCID
                                       repoDid:did
                                     database:db
                                    nodeCache:nodeCache
                                   levelCache:levelCache
                               computedLevel:NULL
                                         error:error];
    if (!rootNode) {
        return nil;
    }

    return [[ATProtoMST alloc] initWithRootNode:rootNode];
}

- (BOOL)saveMST:(ATProtoMST *)mst forDid:(NSString *)did error:(NSError **)error {
    PDSDatabase *db = [self getDatabase];
    if (![db openWithError:error]) return NO;

    NSData *rootData = mst.rootCID ? [mst.rootCID bytes] : [NSData data];
    NSError *fetchError = nil;
    PDSDatabaseRepo *repo = [db getRepoForDid:did error:&fetchError];
    if (fetchError) {
        if (error) *error = fetchError;
        return NO;
    }

    if (!repo) {
        repo = [[PDSDatabaseRepo alloc] init];
        repo.ownerDid = did;
        repo.rootCid = rootData;
        repo.createdAt = [NSDate date];
        repo.updatedAt = repo.createdAt;
        return [db createRepo:repo error:error];
    }

    return [db updateRepoRoot:did rootCid:rootData error:error];
}

- (BOOL)saveMSTNode:(ATProtoMSTNode *)node withCID:(ATProtoCID *)cid forDid:(NSString *)did error:(NSError **)error {
    if (!node || !cid) {
        if (error) {
            *error = [NSError errorWithDomain:MSTPersistenceErrorDomain
                                         code:MSTPersistenceErrorCodeSerializationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Node or CID cannot be nil"}];
        }
        return NO;
    }

    PDSDatabase *db = [self getDatabase];
    if (![db openWithError:error]) return NO;

    ATProtoMST *serializer = [[ATProtoMST alloc] init];
    NSData *nodeData = [serializer serializeNode:node];
    if (!nodeData) {
        if (error) {
            *error = [NSError errorWithDomain:MSTPersistenceErrorDomain
                                         code:MSTPersistenceErrorCodeSerializationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize MST node"}];
        }
        return NO;
    }

    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = [cid bytes];
    block.repoDid = did;
    block.blockData = nodeData;
    block.contentType = @"application/car";
    block.size = nodeData.length;
    block.createdAt = [NSDate date];

    return [db saveBlock:block error:error];
}

- (nullable ATProtoMSTNode *)loadMSTNodeWithCID:(ATProtoCID *)cid forDid:(NSString *)did error:(NSError **)error {
    if (!cid) {
        if (error) {
            *error = [NSError errorWithDomain:MSTPersistenceErrorDomain
                                         code:MSTPersistenceErrorCodeInvalidCID
                                     userInfo:@{NSLocalizedDescriptionKey: @"CID cannot be nil"}];
        }
        return nil;
    }

    PDSDatabase *db = [self getDatabase];
    if (![db openWithError:error]) return nil;

    NSMutableDictionary<NSString *, ATProtoMSTNode *> *nodeCache = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *levelCache = [NSMutableDictionary dictionary];

    return [self loadNodeWithCID:cid
                         repoDid:did
                       database:db
                      nodeCache:nodeCache
                     levelCache:levelCache
                 computedLevel:NULL
                           error:error];
}

- (BOOL)deleteMSTForDid:(NSString *)did error:(NSError **)error {
    PDSDatabase *db = [self getDatabase];
    if (![db openWithError:error]) return NO;

    BOOL cleared = [db executeParameterizedUpdate:@"DELETE FROM blocks WHERE repo_did = ?" params:@[did] error:error];
    if (!cleared) return NO;

    return [db updateRepoRoot:did rootCid:[NSData data] error:error];
}

#pragma mark - Helpers

- (nullable ATProtoCID *)cidFromTaggedValue:(ATProtoCBORValue *)value allowNil:(BOOL)allowNil error:(NSError **)error {
    if (!value) {
        if (allowNil) return nil;
        if (error) {
            *error = [NSError errorWithDomain:MSTPersistenceErrorDomain
                                         code:MSTPersistenceErrorCodeCBORFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Expected CBOR tagged value for CID"}];
        }
        return nil;
    }

    if (value.type == CBORTypeSimpleOrFloat && value.simpleValue && value.simpleValue.unsignedIntegerValue == 22) {
        return nil;
    }

    if (value.type != CBORTypeTag || [value.tag unsignedIntegerValue] != 42 || !value.tagValue || value.tagValue.type != CBORTypeByteString) {
        if (allowNil) return nil;
        if (error) {
            *error = [NSError errorWithDomain:MSTPersistenceErrorDomain
                                         code:MSTPersistenceErrorCodeCBORFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"CID tagged value is malformed or missing tag 42"}];
        }
        return nil;
    }

    NSData *bytes = value.tagValue.byteString;
    if (!bytes || bytes.length <= 1) {
        if (allowNil) return nil;
        if (error) {
            *error = [NSError errorWithDomain:MSTPersistenceErrorDomain
                                         code:MSTPersistenceErrorCodeCBORFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"CID byte string is empty"}];
        }
        return nil;
    }

    NSData *cidBytes = [bytes subdataWithRange:NSMakeRange(1, bytes.length - 1)];
    ATProtoCID *cid = [ATProtoCID cidFromBytes:cidBytes];
    if (!cid && !allowNil && error) {
        *error = [NSError errorWithDomain:MSTPersistenceErrorDomain
                                     code:MSTPersistenceErrorCodeInvalidCID
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse CID"}];
    }
    return cid;
}

- (nullable ATProtoMSTNode *)loadNodeWithCID:(ATProtoCID *)cid
                               repoDid:(NSString *)repoDid
                             database:(PDSDatabase *)database
                            nodeCache:(NSMutableDictionary<NSString *, ATProtoMSTNode *> *)nodeCache
                           levelCache:(NSMutableDictionary<NSString *, NSNumber *> *)levelCache
                       computedLevel:(uint32_t *)computedLevel
                                 error:(NSError **)error {
    NSString *cacheKey = cid.stringValue;
    ATProtoMSTNode *cachedNode = nodeCache[cacheKey];
    if (cachedNode) {
        if (computedLevel) {
            NSNumber *cachedLevel = levelCache[cacheKey];
            *computedLevel = cachedLevel ? cachedLevel.unsignedIntegerValue : 0;
        }
        return cachedNode;
    }

    PDSDatabaseBlock *block = [database getBlockWithCid:cid.bytes repoDid:repoDid error:error];
    if (!block) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:MSTPersistenceErrorDomain
                                         code:MSTPersistenceErrorCodeBlockNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"MST block missing from database"}];
        }
        return nil;
    }

    ATProtoCBORValue *nodeValue = [ATProtoCBORValue decode:block.blockData];
    if (!nodeValue || nodeValue.type != CBORTypeMap) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:MSTPersistenceErrorDomain
                                         code:MSTPersistenceErrorCodeCBORFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid MST node CBOR"}];
        }
        return nil;
    }

    ATProtoCBORValue *entriesValue = nodeValue.map[[ATProtoCBORValue textString:@"e"]];
    NSArray<ATProtoCBORValue *> *entriesArray = (entriesValue && entriesValue.type == CBORTypeArray)
        ? entriesValue.array
        : @[];

    NSMutableArray<ATProtoMSTNodeEntry *> *entries = [NSMutableArray array];
    NSString *prevKey = @"";
    uint32_t nodeLevel = 0;

    for (ATProtoCBORValue *entryMap in entriesArray) {
        if (entryMap.type != CBORTypeMap) continue;

        NSData *suffixData = entryMap.map[[ATProtoCBORValue textString:@"k"]].byteString ?: [NSData data];
        ATProtoCBORValue *prefixValue = entryMap.map[[ATProtoCBORValue textString:@"p"]];
        NSUInteger prefixLen = prefixValue.unsignedInteger.unsignedIntegerValue;
        NSUInteger safeLen = MIN(prefixLen, prevKey.length);
        NSString *prefix = [prevKey substringToIndex:safeLen];
        NSString *suffix = [[NSString alloc] initWithData:suffixData encoding:NSUTF8StringEncoding] ?: @"";
        NSString *fullKey = [prefix stringByAppendingString:suffix];
        prevKey = fullKey;

        ATProtoCBORValue *valueTag = entryMap.map[[ATProtoCBORValue textString:@"v"]];
        ATProtoCID *valueCID = [self cidFromTaggedValue:valueTag allowNil:NO error:error];
        if (!valueCID) return nil;

        ATProtoCBORValue *treeTag = entryMap.map[[ATProtoCBORValue textString:@"t"]];
        ATProtoCID *treeCID = [self cidFromTaggedValue:treeTag allowNil:YES error:error];
        ATProtoMSTNode *treeNode = nil;
        uint32_t treeLevel = 0;
        if (treeCID) {
            treeNode = [self loadNodeWithCID:treeCID
                                     repoDid:repoDid
                                   database:database
                                  nodeCache:nodeCache
                                 levelCache:levelCache
                             computedLevel:&treeLevel
                                       error:error];
            if (!treeNode) return nil;
            nodeLevel = MAX(nodeLevel, treeLevel + 1);
        }

        ATProtoMSTNodeEntry *entry = [[ATProtoMSTNodeEntry alloc] initWithKey:fullKey value:valueCID tree:treeNode];
        [entries addObject:entry];
    }

    ATProtoCBORValue *leftTag = nodeValue.map[[ATProtoCBORValue textString:@"l"]];
    ATProtoCID *leftCID = [self cidFromTaggedValue:leftTag allowNil:YES error:error];
    ATProtoMSTNode *leftNode = nil;
    uint32_t leftLevel = 0;
    if (leftCID) {
        leftNode = [self loadNodeWithCID:leftCID
                                 repoDid:repoDid
                               database:database
                              nodeCache:nodeCache
                             levelCache:levelCache
                         computedLevel:&leftLevel
                                   error:error];
        if (!leftNode) return nil;
        nodeLevel = MAX(nodeLevel, leftLevel + 1);
    }

    ATProtoMSTNode *node = [[ATProtoMSTNode alloc] initWithLevel:nodeLevel left:leftNode entries:entries];
    nodeCache[cacheKey] = node;
    levelCache[cacheKey] = @(nodeLevel);
    if (computedLevel) *computedLevel = nodeLevel;
    return node;
}

@end
