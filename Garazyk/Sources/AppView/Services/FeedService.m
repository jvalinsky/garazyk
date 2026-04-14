#import "AppView/FeedService.h"
#import "Database/PDSDatabase.h"
#import "AppView/ActorService.h"
#import "Core/TID.h"
#import <CommonCrypto/CommonDigest.h>
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Database/Schema.h"
@interface FeedService ()
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) ActorService *actorService;
@end

@implementation FeedService

static NSDateFormatter *FeedServiceISO8601Formatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    });
    return formatter;
}

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
        _actorService = [[ActorService alloc] initWithDatabase:database];
    }
    return self;
}

- (nullable NSDictionary *)getRecordBodyFromCID:(NSString *)cidStr did:(NSString *)did error:(NSError **)error {
    CID *cid = [CID cidFromString:cidStr];
    if (!cid) return nil;
    PDSDatabaseBlock *block = [self.database getBlockWithCid:cid.bytes repoDid:did error:error];
    if (!block || !block.blockData) return nil;
    return [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:error];
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

    NSArray *components = [uri componentsSeparatedByString:@"/"];
    NSString *repo = components.count > 2 ? components[2] : nil;
    NSString *rkey = components.count > 4 ? components[4] : nil;

    NSDictionary *threadPost = @{
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
    };

    NSMutableDictionary *thread = [NSMutableDictionary dictionary];
    thread[@"post"] = threadPost;

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

    NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
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
    for (NSDictionary *row in rows) {
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:actorDID error:nil];
        if (record && record[@"subject"]) {
            NSDictionary *subjectURI = record[@"subject"];
            NSString *subject = subjectURI[@"uri"];

            NSDictionary *likedPost = [self getPostByURI:subject error:error];
            if (likedPost) {
                NSString *rkey = row[@"rkey"] ?: [self generateRkey];
                NSDictionary *feedItem = @{
                    @"post": [self formatPostRecord:subject ?: @"" cid:[self generateCIDForRecord:likedPost] record:likedPost],
                    @"like": @{
                        @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.like/%@", actorDID, rkey],
                        @"cid": row[@"cid"],
                        @"actor": [self.actorService getProfileForActor:actorDID error:error] ?: @{@"did": actorDID}
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

- (nullable NSArray<NSString *> *)getFollowedDIDsForActor:(NSString *)actorDID error:(NSError **)error {
    NSMutableArray *followedDIDs = [NSMutableArray array];

    NSString *query = @"SELECT cid FROM records WHERE did = ? AND collection = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[actorDID, @"app.bsky.graph.follow"] error:error];
    for (NSDictionary *row in rows) {
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:actorDID error:nil];
        if (record && record[@"subject"]) {
            [followedDIDs addObject:record[@"subject"]];
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
    for (NSUInteger i = 0; i < authors.count; i++) {
        [placeholders addObject:@"?"];
    }

    NSMutableString *query = [NSMutableString stringWithFormat:@"SELECT did, rkey, cid FROM records WHERE did IN (%@) AND collection = ?",
                             [placeholders componentsJoinedByString:@","]];
    if (cursor) {
        [query appendString:@" AND rkey < ?"];
    }
    [query appendString:@" ORDER BY rkey DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithArray:authors];
    [args addObject:@"app.bsky.feed.post"];
    if (cursor) {
        [args addObject:cursor];
    }
    [args addObject:@(limit)];
    
    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];
    for (NSDictionary *row in rows) {
        NSString *repo = row[@"did"];
        NSString *rkey = row[@"rkey"];
        NSString *cid = row[@"cid"];
        NSString *value = row[@"value"];
        
        // Try to get record from blocks table first
        NSDictionary *record = [self getRecordBodyFromCID:cid did:repo error:nil];
        if (!record && value && value.length > 0) {
            // Fall back to value column
            record = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", repo, rkey];

        [posts addObject:@{
            @"uri": uri,
            @"cid": cid,
            @"repo": repo,
            @"rkey": rkey,
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

- (nullable NSDictionary *)getPostByURI:(NSString *)uri error:(NSError **)error {
    NSArray *components = [uri componentsSeparatedByString:@"/"];
    if (components.count < 5) {
        return nil;
    }

    NSString *repo = components[2];
    NSString *rkey = components[4];

    NSString *query = @"SELECT cid, value FROM records WHERE did = ? AND collection = ? AND rkey = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[repo, @"app.bsky.feed.post", rkey] error:error];

    if (rows && rows.count > 0) {
        NSDictionary *row = rows.firstObject;
        NSString *cid = row[@"cid"];
        
        // Try to get record from blocks table first
        NSDictionary *record = [self getRecordBodyFromCID:cid did:repo error:nil];
        if (record) {
            return record;
        }
        
        // Fall back to value column if block not found
        NSString *value = row[@"value"];
        if (value && value.length > 0) {
            return [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:error];
        }
    }

    return nil;
}

- (NSArray<NSString *> *)getReplyURIsForParentURI:(NSString *)parentURI error:(NSError **)error {
    NSMutableArray *replyURIs = [NSMutableArray array];

    NSString *query = @"SELECT did, rkey, cid, value FROM records WHERE collection = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[@"app.bsky.feed.post"] error:error];
    for (NSDictionary *row in rows) {
        NSString *cid = row[@"cid"];
        NSString *repo = row[@"did"];
        NSString *value = row[@"value"];
        
        // Try to get record from blocks table first
        NSDictionary *record = [self getRecordBodyFromCID:cid did:repo error:nil];
        if (!record && value && value.length > 0) {
            // Fall back to value column
            record = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        }
        
        if (record) {
            // Check if this record is a reply to the parent URI
            NSString *parent = record[@"reply"][@"parent"][@"uri"];
            if (parent && [parent isEqualToString:parentURI]) {
                NSString *rkey = row[@"rkey"];
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
    
    NSArray<NSString *> *parts = [uri componentsSeparatedByString:@"/"];
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
            return rows.firstObject[@"created_at"];
        }
    }
    return nil;
}

- (nullable NSDictionary *)getAuthorInfoForDID:(NSString *)did error:(NSError **)error {
    return [self.actorService getProfileForActor:did error:error];
}

- (nullable NSDictionary *)formatFeedItem:(NSDictionary *)post {
    NSString *uri = post[@"uri"] ?: @"";
    NSString *cid = post[@"cid"] ?: @"";
    NSDictionary *record = post[@"record"] ?: @{};

    NSDictionary *author = [self getAuthorInfoForDID:post[@"repo"] error:nil] ?: @{@"did": post[@"repo"] ?: @""};

    return @{
        @"uri": uri,
        @"cid": cid,
        @"author": author,
        @"record": record,
        @"replyCount": @([self getReplyCountForURI:uri]),
        @"repostCount": @([self getRepostCountForURI:uri]),
        @"likeCount": @([self getLikeCountForURI:uri]),
        @"indexedAt": [self getIndexedAtForURI:uri] ?: [FeedServiceISO8601Formatter() stringFromDate:[NSDate date]],
        @"viewer": @{},
        @"labels": @[]
    };
}

- (nullable NSDictionary *)formatPostRecord:(NSString *)uri cid:(NSString *)cid record:(NSDictionary *)record {
    NSArray *components = [uri componentsSeparatedByString:@"/"];
    NSString *repo = components.count > 2 ? components[2] : @"";

    return @{
        @"uri": uri,
        @"cid": cid,
        @"author": [self getAuthorInfoForDID:repo error:nil] ?: @{@"did": repo},
        @"record": record,
        @"replyCount": @([self getReplyCountForURI:uri]),
        @"repostCount": @([self getRepostCountForURI:uri]),
        @"likeCount": @([self getLikeCountForURI:uri]),
        @"indexedAt": [self getIndexedAtForURI:uri] ?: @"",
        @"viewer": @{},
        @"labels": @[]
    };
}

- (nullable NSArray *)getFeedGeneratorItems:(NSString *)feedGeneratorURI limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    NSMutableArray *items = [NSMutableArray array];

    NSString *query = @"SELECT cid, did FROM records WHERE collection = ? ORDER BY rkey DESC LIMIT ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[@"app.bsky.feed.generator", @(limit)] error:error];

    for (NSDictionary *row in rows) {
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:row[@"did"] error:nil];
        if (record && record[@"items"]) {
            NSArray *feedItems = record[@"items"];
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

@end
