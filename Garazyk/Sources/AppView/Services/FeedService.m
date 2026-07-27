// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppView/Services/FeedService.h"
#import "Database/PDSDatabase.h"
#import "AppView/Services/ActorService.h"
#import "Core/TID.h"
#import <CommonCrypto/CommonDigest.h>
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATURI.h"
#import "Database/Schema.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "AppView/Services/VideoUriBuilder.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
@interface FeedService ()
@property (nonatomic, strong) id<PDSQueryDatabase> database;
@property (nonatomic, strong) ActorService *actorService;
@end

static NSString *GZFeedStringValue(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSDictionary *GZFeedDictionaryValue(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSArray *GZFeedArrayValue(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static NSDictionary *GZFeedRecordFromJSONString(NSString *value) {
    if (value.length == 0) {
        return nil;
    }

    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return nil;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return GZFeedDictionaryValue(json);
}

static NSString *GZFeedDIDFromPostURI(NSString *uri) {
    NSArray<NSString *> *components = [GZFeedStringValue(uri) componentsSeparatedByString:@"/"];
    return components.count > 2 ? components[2] : @"";
}

@implementation FeedService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
        _actorService = [[ActorService alloc] initWithDatabase:database];
    }
    return self;
}

- (nullable NSDictionary *)getRecordBodyFromCID:(NSString *)cidStr did:(NSString *)did error:(NSError **)error {
    NSString *cidString = GZFeedStringValue(cidStr);
    NSString *repoDID = GZFeedStringValue(did);
    if (cidString.length == 0 || repoDID.length == 0) return nil;

    CID *cid = [CID cidFromString:cidString];
    if (!cid) return nil;

    NSData *blockData = nil;
    PDSDatabaseBlock *block = [self.database getBlockWithCid:cid.bytes repoDid:repoDID error:error];
    if (block.blockData) {
        blockData = block.blockData;
    }

    if (!blockData) {
        NSArray *rows = [self.database executeParameterizedQuery:@"SELECT block_data FROM blocks WHERE cid = ? LIMIT 1"
                                                          params:@[cid.bytes]
                                                           error:error];
        if (rows.count > 0) {
            id value = rows.firstObject[@"block_data"];
            if ([value isKindOfClass:[NSData class]]) {
                blockData = value;
            }
        }
    }

    if (!blockData) return nil;
    return GZFeedDictionaryValue([ATProtoCBORSerialization JSONObjectWithData:blockData error:error]);
}

// Batches the same lookup -getRecordBodyFromCID:did:error: performs, keyed by
// CID string. blocks.cid is the table's sole unique key on every backend this
// service runs against, and -getRecordBodyFromCID:did:error: already falls
// through to an unscoped-by-repo lookup on a repo_did miss — so, exactly as
// in the per-row method, the returned content depends only on the CID, not
// which did asked for it. That lets every call site below batch by CID alone
// regardless of whether its rows share one did or span many.
- (NSDictionary<NSString *, NSDictionary *> *)getRecordBodiesForCIDStrings:(NSArray<NSString *> *)cidStrings
                                                                       error:(NSError **)error {
    if (cidStrings.count == 0) return @{};

    NSMutableDictionary<NSData *, NSString *> *cidStringByBytes = [NSMutableDictionary dictionary];
    NSMutableArray<NSData *> *cidBytesList = [NSMutableArray array];
    for (NSString *cidStr in cidStrings) {
        NSString *cidString = GZFeedStringValue(cidStr);
        if (cidString.length == 0) continue;
        CID *cid = [CID cidFromString:cidString];
        NSData *bytes = cid.bytes;
        if (!bytes || cidStringByBytes[bytes]) continue;
        cidStringByBytes[bytes] = cidString;
        [cidBytesList addObject:bytes];
    }
    if (cidBytesList.count == 0) return @{};

    NSMutableDictionary<NSString *, NSDictionary *> *result = [NSMutableDictionary dictionaryWithCapacity:cidBytesList.count];
    const NSUInteger batchSize = 900;
    for (NSUInteger offset = 0; offset < cidBytesList.count; offset += batchSize) {
        NSArray<NSData *> *batch = [cidBytesList subarrayWithRange:NSMakeRange(offset, MIN(batchSize, cidBytesList.count - offset))];
        NSString *sql = [NSString stringWithFormat:@"SELECT cid, block_data FROM blocks WHERE cid IN (%@)", ATProtoDBPlaceholders(batch.count)];
        NSArray *rows = [self.database executeParameterizedQuery:sql params:batch error:error];
        if (!rows) return nil;
        for (NSDictionary *row in rows) {
            NSData *cidBytes = row[@"cid"];
            NSData *blockData = row[@"block_data"];
            if (![cidBytes isKindOfClass:[NSData class]] || ![blockData isKindOfClass:[NSData class]]) continue;
            NSString *cidStr = cidStringByBytes[cidBytes];
            if (!cidStr) continue;
            NSDictionary *decoded = GZFeedDictionaryValue([ATProtoCBORSerialization JSONObjectWithData:blockData error:error]);
            if (decoded) result[cidStr] = decoded;
        }
    }
    return [result copy];
}

- (nullable NSDictionary *)getTimelineForActor:(NSString *)actorDID
                                          limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                          error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"FeedService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return nil;
    }

    limit = MIN(limit > 0 ? limit : 30, 100);

    NSMutableArray *feedItems = [NSMutableArray array];

    NSArray *followedDIDs = [self getFollowedDIDsForActor:actorDID error:error];
    if (!followedDIDs) {
        followedDIDs = @[];
    }

    NSMutableArray *allPostDIDs = [NSMutableArray arrayWithArray:followedDIDs];
    [allPostDIDs addObject:actorDID];

    NSArray *posts = [self getPostsFromAuthors:allPostDIDs limit:limit cursor:cursor error:error];
    if (posts) {
        for (NSDictionary *post in posts) {
            NSDictionary *feedItem = [self formatFeedItem:post];
            if (feedItem) {
                [feedItems addObject:feedItem];
            }
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"feed"] = feedItems;
    result[@"cursor"] = [NSNull null];

    return [result copy];
}

- (nullable NSDictionary *)getAuthorFeedForActor:(NSString *)actorDID
                                            limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                         filter:(nullable NSString *)filter
                                          error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"FeedService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return nil;
    }

    limit = MIN(limit > 0 ? limit : 30, 100);

    NSMutableArray *feedItems = [NSMutableArray array];

    NSArray *posts = [self getPostsFromAuthors:@[actorDID] limit:limit cursor:cursor error:error];
    if (posts) {
        [feedItems addObjectsFromArray:[self formatFeedItems:posts]];
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"feed"] = feedItems;
    result[@"cursor"] = [NSNull null];

    return [result copy];
}

- (nullable NSDictionary *)getPostThread:(NSString *)uri depth:(NSInteger)depth error:(NSError **)error {
    if (!uri || uri.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"FeedService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing post URI"}];
        }
        return nil;
    }

    depth = MIN(depth > 0 ? depth : 6, 100);

    NSDictionary *postRecord = [self getPostByURI:uri error:error];
    if (!postRecord) {
        return nil;
    }

    ATURI *parsedURI = [ATURI uriWithString:uri error:nil];
    NSString *repo = parsedURI.did;
    NSString *rkey = parsedURI.rkey;

    NSMutableDictionary *threadPost = [@{
        @"uri": uri,
        @"cid": [self generateCIDForRecord:postRecord],
        @"author": [self getAuthorInfoForDID:repo error:error] ?: @{@"did": repo ?: @""},
        @"record": postRecord,
        @"replyCount": @([self getReplyCountForURI:uri]),
        @"repostCount": @([self getRepostCountForURI:uri]),
        @"likeCount": @([self getLikeCountForURI:uri]),
        @"indexedAt": [self getIndexedAtForURI:uri] ?: @"",
        @"viewer": @{},
        @"labels": @[]
    } mutableCopy];
    NSDictionary *threadEmbed = [self appViewEmbedForRecord:postRecord did:repo];
    if (threadEmbed) {
        threadPost[@"embed"] = threadEmbed;
    }

    NSMutableDictionary *thread = [NSMutableDictionary dictionary];
    thread[@"post"] = [threadPost copy];

    if (depth > 0) {
        NSMutableArray *replies = [NSMutableArray array];
        NSArray *replyURIs = [self getReplyURIsForParentURI:uri error:error];
        for (NSString *replyURI in replyURIs) {
            NSDictionary *replyThread = [self getPostThread:replyURI depth:depth - 1 error:error];
            if (replyThread) {
                [replies addObject:replyThread];
            }
        }
        if (replies.count > 0) {
            thread[@"replies"] = replies;
        }
    }

    return [thread copy];
}

- (nullable NSDictionary *)getFeed:(NSString *)feedGeneratorURI
                              limit:(NSInteger)limit
                            cursor:(nullable NSString *)cursor
                              error:(NSError **)error {
    if (!feedGeneratorURI || feedGeneratorURI.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"FeedService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing feed generator URI"}];
        }
        return nil;
    }

    limit = MIN(limit > 0 ? limit : 30, 100);

    NSArray *feedItems = [self getFeedGeneratorItems:feedGeneratorURI limit:limit cursor:cursor error:error];

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"feed"] = feedItems ?: @[];
    result[@"cursor"] = [NSNull null];

    return [result copy];
}

- (nullable NSDictionary *)getActorLikes:(NSString *)actorDID
                                    limit:(NSInteger)limit
                                  cursor:(nullable NSString *)cursor
                                    error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"FeedService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return nil;
    }

    limit = MIN(limit > 0 ? limit : 30, 100);

    NSMutableArray *feedItems = [NSMutableArray array];

    NSString *query = @"SELECT rkey, cid, value FROM records WHERE did = ? AND collection = ?";
    if (cursor) {
        query = [query stringByAppendingString:@" AND rkey < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithObjects:actorDID, @"app.bsky.feed.like", nil];
    if (cursor) {
        [args addObject:cursor];
    }
    [args addObject:@(limit)];

    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];

    NSMutableArray<NSString *> *cids = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSString *cid = GZFeedStringValue(row[@"cid"]);
        if (cid.length > 0) [cids addObject:cid];
    }
    NSDictionary<NSString *, NSDictionary *> *recordsByCID = cids.count > 0
        ? ([self getRecordBodiesForCIDStrings:cids error:nil] ?: @{})
        : @{};
    // Every like in this loop belongs to actorDID (the query filters on it),
    // so the actor profile is fetched once and reused.
    NSDictionary *actorProfile = [self.actorService getProfileForActor:actorDID error:error] ?: @{@"did": actorDID};

    for (NSDictionary *row in rows) {
        NSString *cid = GZFeedStringValue(row[@"cid"]);
        NSString *value = GZFeedStringValue(row[@"value"]);
        NSDictionary *record = recordsByCID[cid] ?: GZFeedRecordFromJSONString(value);
        NSDictionary *subjectURI = GZFeedDictionaryValue(record[@"subject"]);
        NSString *subject = GZFeedStringValue(subjectURI[@"uri"]);

        if (subject.length > 0) {
            NSDictionary *likedPost = [self getPostByURI:subject error:error];
            if (likedPost) {
                NSString *rkey = GZFeedStringValue(row[@"rkey"]) ?: [self generateRkey];
                NSDictionary *feedItem = @{
                    @"post": [self formatPostRecord:subject ?: @"" cid:[self generateCIDForRecord:likedPost] record:likedPost],
                    @"like": @{
                        @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.like/%@", actorDID, rkey],
                        @"cid": cid ?: @"",
                        @"actor": actorProfile
                    }
                };
                [feedItems addObject:feedItem];
            }
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"feed"] = feedItems;
    result[@"cursor"] = [NSNull null];

    return [result copy];
}

- (nullable NSDictionary *)getListFeed:(NSString *)listURI
                                 limit:(NSInteger)limit
                                cursor:(nullable NSString *)cursor
                                 error:(NSError **)error {
    if (!listURI || listURI.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"FeedService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing list URI"}];
        }
        return nil;
    }

    limit = MIN(limit > 0 ? limit : 30, 100);

    // Look up list members from the bsky_graph_listitems table
    NSString *memberQuery = @"SELECT subject_did FROM bsky_graph_listitems WHERE list_uri = ?";
    NSArray *memberRows = [self.database executeParameterizedQuery:memberQuery params:@[listURI] error:error];
    if (!memberRows) {
        return @{@"feed": @[], @"cursor": [NSNull null]};
    }

    NSMutableArray *memberDIDs = [NSMutableArray arrayWithCapacity:memberRows.count];
    for (NSDictionary *row in memberRows) {
        NSString *did = GZFeedStringValue(row[@"subject_did"]);
        if (did.length > 0) {
            [memberDIDs addObject:did];
        }
    }

    if (memberDIDs.count == 0) {
        return @{@"feed": @[], @"cursor": [NSNull null]};
    }

    // Get posts from list members
    NSArray *posts = [self getPostsFromAuthors:memberDIDs limit:limit cursor:cursor error:error];
    NSMutableArray *feedItems = [NSMutableArray array];
    if (posts) {
        for (NSDictionary *post in posts) {
            NSDictionary *feedItem = [self formatFeedItem:post];
            if (feedItem) {
                [feedItems addObject:feedItem];
            }
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"feed"] = feedItems;
    result[@"cursor"] = [NSNull null];

    return [result copy];
}

- (nullable NSArray<NSString *> *)getFollowedDIDsForActor:(NSString *)actorDID error:(NSError **)error {
    NSMutableArray *followedDIDs = [NSMutableArray array];

    NSString *query = @"SELECT subject_did, cid, value FROM records WHERE did = ? AND collection = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[actorDID, @"app.bsky.graph.follow"] error:error];

    NSMutableArray<NSString *> *fallbackCIDs = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        if (GZFeedStringValue(row[@"subject_did"]).length > 0) continue;
        NSString *cid = GZFeedStringValue(row[@"cid"]);
        if (cid.length > 0) [fallbackCIDs addObject:cid];
    }
    NSDictionary<NSString *, NSDictionary *> *recordsByCID = fallbackCIDs.count > 0
        ? ([self getRecordBodiesForCIDStrings:fallbackCIDs error:nil] ?: @{})
        : @{};

    for (NSDictionary *row in rows) {
        NSString *subject = GZFeedStringValue(row[@"subject_did"]);
        if (subject.length > 0) {
            [followedDIDs addObject:subject];
            continue;
        }

        NSString *cid = GZFeedStringValue(row[@"cid"]);
        NSString *value = GZFeedStringValue(row[@"value"]);
        NSDictionary *record = recordsByCID[cid] ?: GZFeedRecordFromJSONString(value);
        subject = GZFeedStringValue(record[@"subject"]);
        if (subject.length > 0) {
            [followedDIDs addObject:subject];
        }
    }

    return [followedDIDs copy];
}

- (nullable NSArray<NSDictionary *> *)getPostsFromAuthors:(NSArray<NSString *> *)authors
                                                    limit:(NSInteger)limit
                                                  cursor:(nullable NSString *)cursor
                                                    error:(NSError **)error {
    NSMutableArray *posts = [NSMutableArray array];

    if (authors.count == 0) {
        return [posts copy];
    }

    NSMutableArray *placeholders = [NSMutableArray array];
    NSMutableArray *validatedDIDs = [NSMutableArray array];
    for (id authorValue in authors) {
        NSString *author = GZFeedStringValue(authorValue);
        if ([author hasPrefix:@"did:"] && author.length >= 10 && author.length <= 200) {
            [placeholders addObject:@"?"];
            [validatedDIDs addObject:author];
        }
    }

    if (validatedDIDs.count == 0) {
        return [posts copy];
    }

    NSMutableString *query = [NSMutableString stringWithFormat:@"SELECT did, rkey, cid, value, created_at FROM records WHERE did IN (%@) AND collection = ?",
                             [placeholders componentsJoinedByString:@","]];
    if (cursor) {
        [query appendString:@" AND rkey < ?"];
    }
    [query appendString:@" ORDER BY rkey DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithArray:validatedDIDs];
    [args addObject:@"app.bsky.feed.post"];
    if (cursor) {
        [args addObject:cursor];
    }
    [args addObject:@(limit)];
    
    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];

    NSMutableArray<NSString *> *rowCIDs = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSString *cid = GZFeedStringValue(row[@"cid"]);
        if (cid.length > 0) [rowCIDs addObject:cid];
    }
    NSDictionary<NSString *, NSDictionary *> *recordsByCID = rowCIDs.count > 0
        ? ([self getRecordBodiesForCIDStrings:rowCIDs error:nil] ?: @{})
        : @{};

    for (NSDictionary *row in rows) {
        NSString *repo = GZFeedStringValue(row[@"did"]);
        NSString *rkey = GZFeedStringValue(row[@"rkey"]);
        NSString *cid = GZFeedStringValue(row[@"cid"]);
        NSString *value = GZFeedStringValue(row[@"value"]);
        if (repo.length == 0 || rkey.length == 0) {
            continue;
        }

        NSDictionary *record = recordsByCID[cid];
        if (!record) {
            record = GZFeedRecordFromJSONString(value);
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", repo, rkey];

        [posts addObject:@{
            @"uri": uri,
            @"cid": cid ?: @"",
            @"repo": repo,
            @"rkey": rkey,
            @"indexedAt": GZFeedStringValue(row[@"created_at"]) ?: @"",
            @"record": record ?: @{}
        }];
    }
    return [posts copy];
}

- (nullable NSDictionary *)getPosts:(NSArray<NSString *> *)uris error:(NSError **)error {
    if (!uris || uris.count == 0) {
        return @{@"posts": @[]};
    }
    
    NSMutableArray *posts = [NSMutableArray array];
    for (NSString *uri in uris) {
        NSDictionary *post = [self getPostByURI:uri error:error];
        if (post) {
            // formatPostRecord returns the feed-ready post view
            NSDictionary *formatted = [self formatPostRecord:uri cid:[self generateCIDForRecord:post] record:post];
            if (formatted) {
                [posts addObject:formatted];
            }
        }
    }
    
    return @{@"posts": posts};
}

- (nullable NSDictionary *)getFeedGenerators:(NSArray<NSString *> *)uris error:(NSError **)error {
    if (!uris || uris.count == 0) {
        return @{@"feeds": @[]};
    }

    NSMutableArray *generators = [NSMutableArray array];
    for (NSString *uri in uris) {
        // Parse the URI to get did and rkey
        NSArray *components = [uri componentsSeparatedByString:@"/"];
        if (components.count < 5) {
            continue;
        }
        NSString *did = components[2];
        NSString *rkey = components[4];

        // Look up the feed generator record
        NSString *query = @"SELECT cid, value FROM records WHERE did = ? AND collection = ? AND rkey = ?";
        NSArray *rows = [self.database executeParameterizedQuery:query params:@[did, @"app.bsky.feed.generator", rkey] error:error];

        if (rows && rows.count > 0) {
            NSDictionary *row = rows.firstObject;
            NSString *cid = GZFeedStringValue(row[@"cid"]);
            NSString *value = GZFeedStringValue(row[@"value"]);

            NSDictionary *record = GZFeedRecordFromJSONString(value);

            if (record) {
                NSDictionary *generator = @{
                    @"uri": uri,
                    @"cid": cid ?: @"",
                    @"did": did,
                    @"creator": [self.actorService getProfileForActor:did error:nil] ?: @{@"did": did},
                    @"displayName": GZFeedStringValue(record[@"displayName"]) ?: @"",
                    @"description": GZFeedStringValue(record[@"description"]) ?: @"",
                    @"avatar": record[@"avatar"] ?: [NSNull null],
                    @"likeCount": @(0),
                    @"onboarding": @(NO)
                };
                [generators addObject:generator];
            }
        }
    }

    return @{@"feeds": generators};
}

- (nullable NSDictionary *)getPostByURI:(NSString *)uri error:(NSError **)error {
    NSString *uriString = GZFeedStringValue(uri);
    if (uriString.length == 0) {
        return nil;
    }

    ATURI *parsedURI = [ATURI uriWithString:uriString error:nil];
    if (!parsedURI) {
        return nil;
    }

    NSString *repo = parsedURI.did;
    NSString *rkey = parsedURI.rkey;

    NSString *query = @"SELECT cid, value FROM records WHERE did = ? AND collection = ? AND rkey = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[repo, @"app.bsky.feed.post", rkey] error:error];

    if (rows && rows.count > 0) {
        NSDictionary *row = rows.firstObject;
        NSString *cid = GZFeedStringValue(row[@"cid"]);
        
        NSDictionary *record = [self getRecordBodyFromCID:cid did:repo error:nil];
        if (record) {
            return record;
        }
        
        return GZFeedRecordFromJSONString(GZFeedStringValue(row[@"value"]));
    }

    return nil;
}

- (NSArray<NSString *> *)getReplyURIsForParentURI:(NSString *)parentURI error:(NSError **)error {
    NSMutableArray *replyURIs = [NSMutableArray array];

    NSString *query = @"SELECT did, rkey, cid, value FROM records WHERE collection = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[@"app.bsky.feed.post"] error:error];

    NSMutableArray<NSString *> *rowCIDs = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSString *cid = GZFeedStringValue(row[@"cid"]);
        if (cid.length > 0) [rowCIDs addObject:cid];
    }
    NSDictionary<NSString *, NSDictionary *> *recordsByCID = rowCIDs.count > 0
        ? ([self getRecordBodiesForCIDStrings:rowCIDs error:nil] ?: @{})
        : @{};

    for (NSDictionary *row in rows) {
        NSString *cid = GZFeedStringValue(row[@"cid"]);
        NSString *repo = GZFeedStringValue(row[@"did"]);
        NSString *value = GZFeedStringValue(row[@"value"]);
        NSString *rkey = GZFeedStringValue(row[@"rkey"]);
        if (repo.length == 0 || rkey.length == 0) {
            continue;
        }

        NSDictionary *record = recordsByCID[cid];
        if (!record) {
            record = GZFeedRecordFromJSONString(value);
        }
        
        if (record) {
            NSDictionary *reply = GZFeedDictionaryValue(record[@"reply"]);
            NSDictionary *parentRef = GZFeedDictionaryValue(reply[@"parent"]);
            NSString *parent = GZFeedStringValue(parentRef[@"uri"]);
            if (parent && [parent isEqualToString:parentURI]) {
                [replyURIs addObject:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", repo, rkey]];
            }
        }
    }

    return [replyURIs copy];
}

- (NSInteger)getReplyCountForURI:(NSString *)uri {
    NSString *collection = @"app.bsky.feed.post";
    NSString *repo = nil;
    NSString *rkey = nil;
    
    NSArray<NSString *> *parts = [GZFeedStringValue(uri) componentsSeparatedByString:@"/"];
    if (parts.count >= 4) {
        repo = [parts[2] stringByReplacingOccurrencesOfString:@"at://" withString:@""];
        rkey = parts[3];
    }
    
    if (!repo || !rkey) {
        return 0;
    }
    
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE collection = ? AND value LIKE ?";
    NSString *likePattern = [NSString stringWithFormat:@"%%\"reply\"%%\"uri\"%%\"at://%@/%@\"%%", repo, rkey];
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[collection, likePattern] error:nil];
    
    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }
    return 0;
}

- (NSInteger)getRepostCountForURI:(NSString *)uri {
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE collection = 'app.bsky.feed.repost' AND value LIKE ?";
    NSString *likePattern = [NSString stringWithFormat:@"%%\"subject\"%%\"uri\"%%\"%@\"%%", uri];
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[likePattern] error:nil];
    
    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }
    return 0;
}

- (NSInteger)getLikeCountForURI:(NSString *)uri {
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE collection = 'app.bsky.feed.like' AND value LIKE ?";
    NSString *likePattern = [NSString stringWithFormat:@"%%\"subject\"%%\"uri\"%%\"%@\"%%", uri];
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[likePattern] error:nil];
    
    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }
    return 0;
}

- (nullable NSString *)getIndexedAtForURI:(NSString *)uri {
    NSArray *components = [uri componentsSeparatedByString:@"/"];
    if (components.count >= 5) {
        NSString *repo = components[2];
        NSString *rkey = components[4];

        NSString *query = @"SELECT created_at FROM records WHERE did = ? AND collection = ? AND rkey = ?";
        NSArray *rows = [self.database executeParameterizedQuery:query params:@[repo, @"app.bsky.feed.post", rkey] error:nil];

        if (rows && rows.count > 0) {
            return GZFeedStringValue(rows.firstObject[@"created_at"]);
        }
    }
    return nil;
}

- (nullable NSDictionary *)getAuthorInfoForDID:(NSString *)did error:(NSError **)error {
    return [self.actorService getProfileForActor:did error:error];
}

- (NSDictionary<NSString *, NSDictionary *> *)getInteractionCountsForPosts:(NSArray<NSDictionary *> *)posts {
    if (posts.count == 0) return @{};

    NSMutableString *query = [NSMutableString stringWithString:@"SELECT "];
    NSMutableArray *params = [NSMutableArray arrayWithCapacity:posts.count * 6];
    for (NSUInteger index = 0; index < posts.count; index++) {
        NSString *uri = GZFeedStringValue(posts[index][@"uri"]) ?: @"";
        NSArray<NSString *> *parts = [uri componentsSeparatedByString:@"/"];
        NSString *replyURI = parts.count >= 4
            ? [NSString stringWithFormat:@"at://%@/%@", parts[2], parts[3]]
            : @"";
        NSString *replyPattern = [NSString stringWithFormat:@"%%\"reply\"%%\"uri\"%%\"%@\"%%", replyURI];
        NSString *subjectPattern = [NSString stringWithFormat:@"%%\"subject\"%%\"uri\"%%\"%@\"%%", uri];
        if (index > 0) [query appendString:@", "];
        [query appendFormat:@"SUM(CASE WHEN collection = ? AND value LIKE ? THEN 1 ELSE 0 END) AS reply%lu, ", (unsigned long)index];
        [query appendFormat:@"SUM(CASE WHEN collection = ? AND value LIKE ? THEN 1 ELSE 0 END) AS repost%lu, ", (unsigned long)index];
        [query appendFormat:@"SUM(CASE WHEN collection = ? AND value LIKE ? THEN 1 ELSE 0 END) AS like%lu", (unsigned long)index];
        [params addObjectsFromArray:@[@"app.bsky.feed.post", replyPattern,
                                      @"app.bsky.feed.repost", subjectPattern,
                                      @"app.bsky.feed.like", subjectPattern]];
    }
    [query appendString:@" FROM records WHERE collection IN (?, ?, ?)"];
    [params addObjectsFromArray:@[@"app.bsky.feed.post",
                                  @"app.bsky.feed.repost",
                                  @"app.bsky.feed.like"]];

    NSArray *rows = [self.database executeParameterizedQuery:query params:params error:nil];
    NSDictionary *row = rows.firstObject ?: @{};
    NSMutableDictionary<NSString *, NSDictionary *> *counts = [NSMutableDictionary dictionaryWithCapacity:posts.count];
    for (NSUInteger index = 0; index < posts.count; index++) {
        NSString *uri = GZFeedStringValue(posts[index][@"uri"]) ?: @"";
        counts[uri] = @{
            @"replyCount": @([row[[NSString stringWithFormat:@"reply%lu", (unsigned long)index]] integerValue]),
            @"repostCount": @([row[[NSString stringWithFormat:@"repost%lu", (unsigned long)index]] integerValue]),
            @"likeCount": @([row[[NSString stringWithFormat:@"like%lu", (unsigned long)index]] integerValue]),
        };
    }
    return [counts copy];
}

- (NSArray<NSDictionary *> *)formatFeedItems:(NSArray<NSDictionary *> *)posts {
    if (posts.count == 0) return @[];

    NSMutableArray<NSString *> *repos = [NSMutableArray arrayWithCapacity:posts.count];
    for (NSDictionary *post in posts) {
        NSString *repo = GZFeedStringValue(post[@"repo"]);
        if (repo.length > 0) [repos addObject:repo];
    }
    NSDictionary<NSString *, NSDictionary *> *authors = [self.actorService getProfilesByDIDForActors:repos error:nil] ?: @{};
    NSDictionary<NSString *, NSDictionary *> *counts = [self getInteractionCountsForPosts:posts];
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray arrayWithCapacity:posts.count];
    for (NSDictionary *post in posts) {
        NSString *uri = GZFeedStringValue(post[@"uri"]) ?: @"";
        NSString *cid = GZFeedStringValue(post[@"cid"]) ?: @"";
        NSString *repo = GZFeedStringValue(post[@"repo"]) ?: @"";
        NSDictionary *record = GZFeedDictionaryValue(post[@"record"]) ?: @{};
        NSDictionary *postCounts = counts[uri] ?: @{};
        NSMutableDictionary *view = [@{
            @"uri": uri,
            @"cid": cid,
            @"author": authors[repo] ?: @{ @"did": repo },
            @"record": record,
            @"replyCount": postCounts[@"replyCount"] ?: @0,
            @"repostCount": postCounts[@"repostCount"] ?: @0,
            @"likeCount": postCounts[@"likeCount"] ?: @0,
            @"indexedAt": GZFeedStringValue(post[@"indexedAt"]) ?: now,
            @"viewer": @{},
            @"labels": @[]
        } mutableCopy];
        NSDictionary *embedView = [self appViewEmbedForRecord:record did:repo];
        if (embedView) view[@"embed"] = embedView;
        [items addObject:[view copy]];
    }
    return [items copy];
}

- (nullable NSDictionary *)formatFeedItem:(NSDictionary *)post {
    NSString *uri = GZFeedStringValue(post[@"uri"]) ?: @"";
    NSString *cid = GZFeedStringValue(post[@"cid"]) ?: @"";
    NSString *repo = GZFeedStringValue(post[@"repo"]) ?: @"";
    NSDictionary *record = GZFeedDictionaryValue(post[@"record"]) ?: @{};

    NSDictionary *author = [self getAuthorInfoForDID:repo error:nil] ?: @{@"did": repo};

    NSMutableDictionary *view = [@{
        @"uri": uri,
        @"cid": cid,
        @"author": author,
        @"record": record,
        @"replyCount": @([self getReplyCountForURI:uri]),
        @"repostCount": @([self getRepostCountForURI:uri]),
        @"likeCount": @([self getLikeCountForURI:uri]),
        @"indexedAt": [self getIndexedAtForURI:uri] ?: [NSDateFormatter atproto_stringFromDate:[NSDate date]],
        @"viewer": @{},
        @"labels": @[]
    } mutableCopy];
    NSDictionary *embedView = [self appViewEmbedForRecord:record did:repo];
    if (embedView) {
        view[@"embed"] = embedView;
    }
    return [view copy];
}

- (nullable NSDictionary *)formatPostRecord:(NSString *)uri cid:(NSString *)cid record:(NSDictionary *)record {
    NSString *uriString = GZFeedStringValue(uri) ?: @"";
    NSString *cidString = GZFeedStringValue(cid) ?: @"";
    NSString *repo = GZFeedDIDFromPostURI(uriString);

    NSMutableDictionary *view = [@{
        @"uri": uriString,
        @"cid": cidString,
        @"author": [self getAuthorInfoForDID:repo error:nil] ?: @{@"did": repo},
        @"record": GZFeedDictionaryValue(record) ?: @{},
        @"replyCount": @([self getReplyCountForURI:uriString]),
        @"repostCount": @([self getRepostCountForURI:uriString]),
        @"likeCount": @([self getLikeCountForURI:uriString]),
        @"indexedAt": [self getIndexedAtForURI:uriString] ?: @"",
        @"viewer": @{},
        @"labels": @[]
    } mutableCopy];
    NSDictionary *embedView = [self appViewEmbedForRecord:record did:repo];
    if (embedView) {
        view[@"embed"] = embedView;
    }
    return [view copy];
}

- (nullable NSDictionary *)appViewEmbedForRecord:(NSDictionary *)record did:(NSString *)did {
    NSDictionary *embed = GZFeedDictionaryValue(record[@"embed"]);
    if (!embed || did.length == 0 || !self.videoUriBuilder) {
        return nil;
    }

    NSDictionary *videoView = [self.videoUriBuilder videoViewFromEmbed:embed did:did];
    if (videoView) {
        return videoView;
    }

    if ([GZFeedStringValue(embed[@"$type"]) isEqualToString:@"app.bsky.embed.recordWithMedia"]) {
        NSDictionary *media = GZFeedDictionaryValue(embed[@"media"]);
        NSDictionary *mediaView = [self.videoUriBuilder videoViewFromEmbed:media did:did];
        if (mediaView) {
            NSMutableDictionary *recordWithMedia = [@{@"$type": @"app.bsky.embed.recordWithMedia#view",
                                                      @"media": mediaView} mutableCopy];
            NSDictionary *recordEmbed = GZFeedDictionaryValue(embed[@"record"]);
            if (recordEmbed) {
                recordWithMedia[@"record"] = recordEmbed;
            }
            return [recordWithMedia copy];
        }
    }

    return nil;
}

- (nullable NSArray *)getFeedGeneratorItems:(NSString *)feedGeneratorURI limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    NSMutableArray *items = [NSMutableArray array];

    NSString *query = @"SELECT cid, did FROM records WHERE collection = ? ORDER BY rkey DESC LIMIT ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[@"app.bsky.feed.generator", @(limit)] error:error];

    NSMutableArray<NSString *> *rowCIDs = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSString *cid = GZFeedStringValue(row[@"cid"]);
        if (cid.length > 0) [rowCIDs addObject:cid];
    }
    NSDictionary<NSString *, NSDictionary *> *recordsByCID = rowCIDs.count > 0
        ? ([self getRecordBodiesForCIDStrings:rowCIDs error:nil] ?: @{})
        : @{};

    for (NSDictionary *row in rows) {
        NSDictionary *record = recordsByCID[GZFeedStringValue(row[@"cid"])];
        NSArray *feedItems = GZFeedArrayValue(record[@"items"]);
        if (feedItems) {
            for (NSDictionary *item in feedItems) {
                [items addObject:item];
            }
        }
    }

    return [items copy];
}

- (NSString *)generateCIDForRecord:(NSDictionary *)record {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:record options:0 error:&error];
    if (jsonData) {
        const unsigned char *hashBuffer = CC_SHA256(jsonData.bytes, (CC_LONG)jsonData.length, nil);
        if (hashBuffer) {
            NSMutableString *hashString = [NSMutableString stringWithCapacity:64];
            for (int i = 0; i < 32; i++) {
                [hashString appendFormat:@"%02x", hashBuffer[i]];
            }
            return [NSString stringWithFormat:@"bafkrei%@", [hashString substringToIndex:52]];
        }
    }
    return @"bafkreihodrdxxdzm63zmxy3xcfxqxgqn5jd4m";
}

- (NSString *)generateRkey {
    const unsigned char *hashBuffer = CC_SHA256([[NSUUID UUID].UUIDString UTF8String], (CC_LONG)[[NSUUID UUID].UUIDString length], nil);
    if (hashBuffer) {
        NSMutableString *hashString = [NSMutableString stringWithCapacity:64];
        for (int i = 0; i < 16; i++) {
            [hashString appendFormat:@"%02x", hashBuffer[i]];
        }
        return hashString;
    }
    return [TID tid].stringValue;
}

#pragma mark - Indexing

- (BOOL)indexThreadgate:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error {
    NSString *postUri = record[@"post"];
    if (![postUri isKindOfClass:[NSString class]] || postUri.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"FeedService"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Threadgate record missing post URI"}];
        }
        return NO;
    }
    
    // Validate author (DID) matches post_uri author
    NSString *authorPrefix = [NSString stringWithFormat:@"at://%@/", did];
    if (![postUri hasPrefix:authorPrefix]) {
        if (error) {
            *error = [NSError errorWithDomain:@"FeedService"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Author mismatch: cannot create threadgate for post owned by another user (post: %@, actor: %@)", postUri, did]}];
        }
        return NO;
    }
    
    NSArray *allow = record[@"allow"];
    NSString *allowJson = nil;
    if (allow) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:allow options:0 error:nil];
        allowJson = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    
    NSString *sql = @"INSERT OR REPLACE INTO bsky_feed_threadgates (uri, post_uri, allow_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?)";
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    return [self.database executeParameterizedUpdate:sql params:@[uri ?: @"", postUri, allowJson ?: @"[]", @((long long)now), @((long long)now)] error:error];
}

- (BOOL)unindexThreadgateWithURI:(NSString *)uri error:(NSError **)error {
    NSString *sql = @"DELETE FROM bsky_feed_threadgates WHERE uri = ?";
    return [self.database executeParameterizedUpdate:sql params:@[uri] error:error];
}

- (BOOL)indexPostgate:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error {
    NSString *postUri = record[@"post"];
    NSArray *embeddingRules = record[@"embeddingRules"];
    NSArray *detachedEmbeddingUris = record[@"detachedEmbeddingUris"];
    
    NSString *rulesJson = @"[]";
    if (embeddingRules) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:embeddingRules options:0 error:nil];
        rulesJson = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    
    NSString *detachedJson = @"[]";
    if (detachedEmbeddingUris) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:detachedEmbeddingUris options:0 error:nil];
        detachedJson = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    
    NSString *sql = @"INSERT OR REPLACE INTO bsky_feed_postgates (uri, post_uri, embedding_rules_json, detached_embedding_uris_json, created_at) VALUES (?, ?, ?, ?, ?)";
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    return [self.database executeParameterizedUpdate:sql params:@[uri, postUri ?: @"", rulesJson, detachedJson, @((long long)now)] error:error];
}

- (BOOL)unindexPostgateWithURI:(NSString *)uri error:(NSError **)error {
    NSString *sql = @"DELETE FROM bsky_feed_postgates WHERE uri = ?";
    return [self.database executeParameterizedUpdate:sql params:@[uri] error:error];
}

- (BOOL)indexGenerator:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error {
    NSString *displayName = record[@"displayName"];
    NSString *description = record[@"description"];
    NSString *avatar = record[@"avatar"]; // CID
    
    NSString *sql = @"INSERT OR REPLACE INTO bsky_feed_generators (uri, did, display_name, description, avatar_blob_cid, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    return [self.database executeParameterizedUpdate:sql params:@[uri, did, displayName ?: @"", description ?: @"", avatar ?: [NSNull null], @((long long)now)] error:error];
}

- (BOOL)unindexGeneratorWithURI:(NSString *)uri error:(NSError **)error {
    NSString *sql = @"DELETE FROM bsky_feed_generators WHERE uri = ?";
    return [self.database executeParameterizedUpdate:sql params:@[uri] error:error];
}

@end
