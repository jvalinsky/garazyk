#import "AppView/FeedService.h"
#import "Database/PDSDatabase.h"
#import "AppView/ActorService.h"
#import <CommonCrypto/CommonDigest.h>

@interface FeedService ()
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) ActorService *actorService;
@end

@implementation FeedService

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
        _actorService = [[ActorService alloc] initWithDatabase:database];
    }
    return self;
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

    NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
    isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    isoFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];

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

    NSString *query = @"SELECT rkey, record FROM records WHERE repo = ? AND collection = ?";
    if (cursor) {
        query = [query stringByAppendingString:@" AND rkey < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithObjects:actorDID, @"app.bsky.feed.like", nil];
    if (cursor) {
        [args addObject:cursor];
    }
    [args addObject:@(limit)];

    NSArray *rows = [self.database executeQuery:query error:error];
    for (NSDictionary *row in rows) {
        NSData *recordData = row[@"record"];
        if (recordData) {
            NSError *parseError = nil;
            NSDictionary *record = [NSJSONSerialization JSONObjectWithData:recordData options:0 error:&parseError];
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
                            @"cid": [self generateCIDForRecord:record],
                            @"actor": [self.actorService getProfileForActor:actorDID error:error] ?: @{@"did": actorDID}
                        }
                    };
                    [feedItems addObject:feedItem];
                }
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

    NSString *query = @"SELECT record FROM records WHERE repo = ? AND collection = ?";
    NSArray *rows = [self.database executeQuery:query error:error];
    for (NSDictionary *row in rows) {
        NSData *recordData = row[@"record"];
        if (recordData) {
            NSError *parseError = nil;
            NSDictionary *record = [NSJSONSerialization JSONObjectWithData:recordData options:0 error:&parseError];
            if (record && record[@"subject"]) {
                [followedDIDs addObject:record[@"subject"]];
            }
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

    NSMutableString *query = [NSMutableString stringWithFormat:@"SELECT repo, rkey, record FROM records WHERE repo IN (%@) AND collection = ?",
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

    NSArray *rows = [self.database executeQuery:query error:error];
    for (NSDictionary *row in rows) {
        NSString *repo = row[@"repo"];
        NSString *rkey = row[@"rkey"];
        NSData *recordData = row[@"record"];
        NSError *parseError = nil;
        NSDictionary *record = [NSJSONSerialization JSONObjectWithData:recordData options:0 error:&parseError];

        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", repo, rkey];
        NSString *cid = [self generateCIDForRecord:record];

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

- (nullable NSDictionary *)getPostByURI:(NSString *)uri error:(NSError **)error {
    NSArray *components = [uri componentsSeparatedByString:@"/"];
    if (components.count < 5) {
        return nil;
    }

    NSString *repo = components[2];
    NSString *rkey = components[4];

    NSString *query = @"SELECT record FROM records WHERE repo = ? AND collection = ? AND rkey = ?";
    NSArray *rows = [self.database executeQuery:query error:error];

    if (rows && rows.count > 0) {
        NSData *recordData = rows.firstObject[@"record"];
        if (recordData) {
            NSError *parseError = nil;
            return [NSJSONSerialization JSONObjectWithData:recordData options:0 error:&parseError];
        }
    }

    return nil;
}

- (NSArray<NSString *> *)getReplyURIsForParentURI:(NSString *)parentURI error:(NSError **)error {
    NSMutableArray *replyURIs = [NSMutableArray array];

    NSString *query = @"SELECT repo, rkey FROM records WHERE collection = ?";
    NSArray *rows = [self.database executeQuery:query error:error];
    for (NSDictionary *row in rows) {
        NSData *recordData = row[@"record"];
        if (recordData) {
            NSError *parseError = nil;
            NSString *recordStr = [[NSString alloc] initWithData:recordData encoding:NSUTF8StringEncoding];
            if (recordStr && [recordStr containsString:parentURI]) {
                NSString *repo = row[@"repo"];
                NSString *rkey = row[@"rkey"];
                [replyURIs addObject:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", repo, rkey]];
            }
        }
    }

    return [replyURIs copy];
}

- (NSInteger)getReplyCountForURI:(NSString *)uri {
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE collection = ?";
    NSArray *rows = [self.database executeQuery:query error:nil];

    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }
    return 0;
}

- (NSInteger)getRepostCountForURI:(NSString *)uri {
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE collection = ?";
    NSArray *rows = [self.database executeQuery:query error:nil];

    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }
    return 0;
}

- (NSInteger)getLikeCountForURI:(NSString *)uri {
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE collection = ?";
    NSArray *rows = [self.database executeQuery:query error:nil];

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

        NSString *query = @"SELECT indexedAt FROM records WHERE repo = ? AND collection = ? AND rkey = ?";
        NSArray *rows = [self.database executeQuery:query error:nil];

        if (rows && rows.count > 0) {
            return rows.firstObject[@"indexedAt"];
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

    NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
    isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    isoFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];

    return @{
        @"uri": uri,
        @"cid": cid,
        @"author": author,
        @"record": record,
        @"replyCount": @([self getReplyCountForURI:uri]),
        @"repostCount": @([self getRepostCountForURI:uri]),
        @"likeCount": @([self getLikeCountForURI:uri]),
        @"indexedAt": [self getIndexedAtForURI:uri] ?: [isoFormatter stringFromDate:[NSDate date]],
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

    NSString *query = @"SELECT record FROM records WHERE collection = ? ORDER BY rkey DESC LIMIT ?";
    NSArray *rows = [self.database executeQuery:query error:error];

    for (NSDictionary *row in rows) {
        NSData *recordData = row[@"record"];
        if (recordData) {
            NSError *parseError = nil;
            NSDictionary *record = [NSJSONSerialization JSONObjectWithData:recordData options:0 error:&parseError];

            if (record && record[@"items"]) {
                NSArray *feedItems = record[@"items"];
                for (NSDictionary *item in feedItems) {
                    [items addObject:item];
                }
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
    return [[NSUUID UUID].UUIDString substringToIndex:16];
}

@end
