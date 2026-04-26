/*!
 @file GraphService.m

 @abstract Social graph service implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Services/GraphService.h"
#import "AppView/Services/ActorService.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/NSDateFormatter+ATProto.h"

@interface GraphService ()
@property (nonatomic, strong) id<PDSQueryDatabase> database;
@property (nonatomic, strong) ActorService *actorService;
@end

@implementation GraphService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {

    self = [super init];
    if (self) {
        _database = database;
        _actorService = [[ActorService alloc] initWithDatabase:database];
    }
    return self;
}

#pragma mark - Internal Helpers

- (nullable NSDictionary *)getRecordBodyFromCID:(NSString *)cidStr did:(NSString *)did error:(NSError **)error {
    CID *cid = [CID cidFromString:cidStr];
    if (!cid) return nil;
    PDSDatabaseBlock *block = [self.database getBlockWithCid:cid.bytes repoDid:did error:error];
    if (!block || !block.blockData) return nil;
    return [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:error];
}

#pragma mark - Follows

- (nullable NSDictionary *)getFollowsForActor:(NSString *)actorDID
                                         limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
    if (cursor) {
        query = [query stringByAppendingString:@" AND rkey < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithObjects:actorDID, @"app.bsky.graph.follow", nil];
    if (cursor) {
        [args addObject:cursor];
    }
    [args addObject:@(limit + 1)]; // Fetch one extra for cursor

    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];
    if (!rows) {
        return @{@"subject": [self.actorService getProfileForActor:actorDID error:nil] ?: @{@"did": actorDID}, @"follows": @[]};
    }

    NSMutableArray *follows = [NSMutableArray array];
    NSString *nextCursor = nil;

    for (NSUInteger i = 0; i < rows.count && (NSInteger)i < limit; i++) {
        NSDictionary *row = rows[i];
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:actorDID error:nil];
        if (record && record[@"subject"]) {
            NSString *subjectDID = record[@"subject"];
            NSDictionary *profile = [self.actorService getProfileForActor:subjectDID error:nil];
            if (profile) {
                [follows addObject:profile];
            } else {
                [follows addObject:@{@"did": subjectDID, @"handle": @"handle.invalid"}];
            }
        }
        if (i == (NSUInteger)(limit - 1) && rows.count > (NSUInteger)limit) {
            nextCursor = row[@"rkey"];
        }
    }

    NSDictionary *subject = [self.actorService getProfileForActor:actorDID error:nil] ?: @{@"did": actorDID};

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"subject"] = subject;
    result[@"follows"] = follows;
    if (nextCursor) {
        result[@"cursor"] = nextCursor;
    }

    return [result copy];
}

- (nullable NSDictionary *)getFollowersForActor:(NSString *)actorDID
                                           limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    // For followers we need to scan all users' follow records where subject == actorDID.
    // Query all follow records across all repos, then filter by subject.
    NSString *query = @"SELECT did, rkey, cid FROM records WHERE collection = ? ORDER BY rkey DESC";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[@"app.bsky.graph.follow"] error:error];
    if (!rows) {
        return @{@"subject": [self.actorService getProfileForActor:actorDID error:nil] ?: @{@"did": actorDID}, @"followers": @[]};
    }

    NSMutableArray *followers = [NSMutableArray array];
    BOOL pastCursor = (cursor == nil);

    for (NSDictionary *row in rows) {
        NSString *followerDID = row[@"did"];
        NSString *rkey = row[@"rkey"];

        if (!pastCursor) {
            if ([rkey isEqualToString:cursor]) {
                pastCursor = YES;
            }
            continue;
        }

        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:followerDID error:nil];
        if (record && [record[@"subject"] isEqualToString:actorDID]) {
            NSDictionary *profile = [self.actorService getProfileForActor:followerDID error:nil];
            if (profile) {
                [followers addObject:profile];
            } else {
                [followers addObject:@{@"did": followerDID, @"handle": @"handle.invalid"}];
            }
        }

        if ((NSInteger)followers.count >= limit) {
            break;
        }
    }

    NSDictionary *subject = [self.actorService getProfileForActor:actorDID error:nil] ?: @{@"did": actorDID};

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"subject"] = subject;
    result[@"followers"] = followers;

    // Set cursor if we have more results
    if ((NSInteger)followers.count >= limit && rows.count > 0) {
        NSDictionary *lastRow = rows[MIN(rows.count - 1, (NSUInteger)(followers.count))];
        result[@"cursor"] = lastRow[@"rkey"];
    }

    return [result copy];
}

#pragma mark - Blocks

- (nullable NSDictionary *)getBlocksForActor:(NSString *)actorDID
                                        limit:(NSInteger)limit
                                       cursor:(nullable NSString *)cursor
                                        error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
    if (cursor) {
        query = [query stringByAppendingString:@" AND rkey < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithObjects:actorDID, @"app.bsky.graph.block", nil];
    if (cursor) {
        [args addObject:cursor];
    }
    [args addObject:@(limit + 1)];

    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];
    if (!rows) {
        return @{@"blocks": @[]};
    }

    NSMutableArray *blocks = [NSMutableArray array];
    NSString *nextCursor = nil;

    for (NSUInteger i = 0; i < rows.count && (NSInteger)i < limit; i++) {
        NSDictionary *row = rows[i];
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:actorDID error:nil];
        if (record && record[@"subject"]) {
            NSString *subjectDID = record[@"subject"];
            NSDictionary *profile = [self.actorService getProfileForActor:subjectDID error:nil];
            if (profile) {
                [blocks addObject:profile];
            } else {
                [blocks addObject:@{@"did": subjectDID, @"handle": @"handle.invalid"}];
            }
        }
        if (i == (NSUInteger)(limit - 1) && rows.count > (NSUInteger)limit) {
            nextCursor = row[@"rkey"];
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"blocks"] = blocks;
    if (nextCursor) {
        result[@"cursor"] = nextCursor;
    }

    return [result copy];
}

#pragma mark - Mutes

- (BOOL)muteActor:(NSString *)targetDID forActor:(NSString *)actorDID error:(NSError **)error {
    NSString *sql = @"INSERT OR IGNORE INTO actor_mutes (did, muted_did, created_at) VALUES (?, ?, ?)";
    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];

    return [self.database executeParameterizedUpdate:sql params:@[actorDID, targetDID, now] error:error];
}

- (BOOL)unmuteActor:(NSString *)targetDID forActor:(NSString *)actorDID error:(NSError **)error {
    NSString *sql = @"DELETE FROM actor_mutes WHERE did = ? AND muted_did = ?";
    return [self.database executeParameterizedUpdate:sql params:@[actorDID, targetDID] error:error];
}

- (nullable NSDictionary *)getMutesForActor:(NSString *)actorDID
                                       limit:(NSInteger)limit
                                      cursor:(nullable NSString *)cursor
                                       error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    NSString *query = @"SELECT id, muted_did FROM actor_mutes WHERE did = ?";
    if (cursor) {
        query = [query stringByAppendingString:@" AND id < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY id DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithObject:actorDID];
    if (cursor) {
        [args addObject:cursor];
    }
    [args addObject:@(limit + 1)];

    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];
    if (!rows) {
        return @{@"mutes": @[]};
    }

    NSMutableArray *mutes = [NSMutableArray array];
    NSString *nextCursor = nil;

    for (NSUInteger i = 0; i < rows.count && (NSInteger)i < limit; i++) {
        NSDictionary *row = rows[i];
        NSString *mutedDID = row[@"muted_did"];
        NSDictionary *profile = [self.actorService getProfileForActor:mutedDID error:nil];
        if (profile) {
            [mutes addObject:profile];
        } else {
            [mutes addObject:@{@"did": mutedDID, @"handle": @"handle.invalid"}];
        }
        if (i == (NSUInteger)(limit - 1) && rows.count > (NSUInteger)limit) {
            nextCursor = [row[@"id"] description];
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"mutes"] = mutes;
    if (nextCursor) {
        result[@"cursor"] = nextCursor;
    }

    return [result copy];
}

#pragma mark - Relationships

- (nullable NSDictionary *)getRelationship:(NSString *)viewerDID
                                  withActor:(NSString *)targetDID
                                      error:(NSError **)error {
    NSMutableDictionary *relationship = [NSMutableDictionary dictionary];
    relationship[@"did"] = targetDID;

    // Check if viewer follows target
    NSString *followQuery = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
    NSArray *followRows = [self.database executeParameterizedQuery:followQuery params:@[viewerDID, @"app.bsky.graph.follow"] error:nil];
    for (NSDictionary *row in followRows) {
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:viewerDID error:nil];
        if (record && [record[@"subject"] isEqualToString:targetDID]) {
            relationship[@"following"] = [NSString stringWithFormat:@"at://%@/app.bsky.graph.follow/%@", viewerDID, row[@"rkey"]];
            break;
        }
    }

    // Check if target follows viewer
    NSArray *followedByRows = [self.database executeParameterizedQuery:followQuery params:@[targetDID, @"app.bsky.graph.follow"] error:nil];
    for (NSDictionary *row in followedByRows) {
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:targetDID error:nil];
        if (record && [record[@"subject"] isEqualToString:viewerDID]) {
            relationship[@"followedBy"] = [NSString stringWithFormat:@"at://%@/app.bsky.graph.follow/%@", targetDID, row[@"rkey"]];
            break;
        }
    }

    // Check if viewer blocks target
    NSString *blockQuery = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
    NSArray *blockRows = [self.database executeParameterizedQuery:blockQuery params:@[viewerDID, @"app.bsky.graph.block"] error:nil];
    for (NSDictionary *row in blockRows) {
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:viewerDID error:nil];
        if (record && [record[@"subject"] isEqualToString:targetDID]) {
            relationship[@"blocking"] = [NSString stringWithFormat:@"at://%@/app.bsky.graph.block/%@", viewerDID, row[@"rkey"]];
            break;
        }
    }

    // Check if viewer mutes target
    NSString *muteQuery = @"SELECT id FROM actor_mutes WHERE did = ? AND muted_did = ? LIMIT 1";
    NSArray *muteRows = [self.database executeParameterizedQuery:muteQuery params:@[viewerDID, targetDID] error:nil];
    if (muteRows.count > 0) {
        relationship[@"muting"] = @YES;
    }

    // Check if target blocks viewer
    NSArray *blockedByRows = [self.database executeParameterizedQuery:blockQuery params:@[targetDID, @"app.bsky.graph.block"] error:nil];
    for (NSDictionary *row in blockedByRows) {
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:targetDID error:nil];
        if (record && [record[@"subject"] isEqualToString:viewerDID]) {
            relationship[@"blockedBy"] = @YES;
            break;
        }
    }

    return [relationship copy];
}

#pragma mark - Likes

- (nullable NSDictionary *)getLikesForURI:(NSString *)uri
                                     limit:(NSInteger)limit
                                    cursor:(nullable NSString *)cursor
                                     error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    // Scan all like records across all repos to find likes targeting this URI
    NSString *query = @"SELECT did, rkey, cid FROM records WHERE collection = ? ORDER BY rkey DESC";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[@"app.bsky.feed.like"] error:error];

    NSMutableArray *likes = [NSMutableArray array];
    BOOL pastCursor = (cursor == nil);

    for (NSDictionary *row in rows) {
        NSString *likerDID = row[@"did"];
        NSString *rkey = row[@"rkey"];

        if (!pastCursor) {
            if ([rkey isEqualToString:cursor]) {
                pastCursor = YES;
            }
            continue;
        }

        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:likerDID error:nil];
        if (record) {
            NSDictionary *subject = record[@"subject"];
            NSString *subjectURI = [subject isKindOfClass:[NSDictionary class]] ? subject[@"uri"] : nil;
            if ([subjectURI isEqualToString:uri]) {
                NSString *createdAt = record[@"createdAt"] ?: @"";
                NSDictionary *profile = [self.actorService getProfileForActor:likerDID error:nil];
                NSDictionary *like = @{
                    @"indexedAt": createdAt,
                    @"createdAt": createdAt,
                    @"actor": profile ?: @{@"did": likerDID, @"handle": @"handle.invalid"}
                };
                [likes addObject:like];
            }
        }

        if ((NSInteger)likes.count >= limit) {
            break;
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"uri"] = uri;
    result[@"likes"] = likes;

    if ((NSInteger)likes.count >= limit) {
        result[@"cursor"] = [[likes lastObject] valueForKeyPath:@"actor.did"] ?: @"";
    }

    return [result copy];
}

#pragma mark - Reposts

- (nullable NSDictionary *)getRepostedByForURI:(NSString *)uri
                                          limit:(NSInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    NSString *query = @"SELECT did, rkey, cid FROM records WHERE collection = ? ORDER BY rkey DESC";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[@"app.bsky.feed.repost"] error:error];

    NSMutableArray *repostedBy = [NSMutableArray array];
    BOOL pastCursor = (cursor == nil);

    for (NSDictionary *row in rows) {
        NSString *reposterDID = row[@"did"];
        NSString *rkey = row[@"rkey"];

        if (!pastCursor) {
            if ([rkey isEqualToString:cursor]) {
                pastCursor = YES;
            }
            continue;
        }

        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:reposterDID error:nil];
        if (record) {
            NSDictionary *subject = record[@"subject"];
            NSString *subjectURI = [subject isKindOfClass:[NSDictionary class]] ? subject[@"uri"] : nil;
            if ([subjectURI isEqualToString:uri]) {
                NSDictionary *profile = [self.actorService getProfileForActor:reposterDID error:nil];
                [repostedBy addObject:profile ?: @{@"did": reposterDID, @"handle": @"handle.invalid"}];
            }
        }

        if ((NSInteger)repostedBy.count >= limit) {
            break;
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"uri"] = uri;
    result[@"repostedBy"] = repostedBy;

    if ((NSInteger)repostedBy.count >= limit) {
        result[@"cursor"] = [[repostedBy lastObject] valueForKey:@"did"] ?: @"";
    }

    return [result copy];
}

#pragma mark - Starter Packs

- (nullable NSDictionary *)getStarterPack:(NSString *)starterPackURI error:(NSError **)error {
    NSArray *parts = [starterPackURI componentsSeparatedByString:@"/"];
    if (parts.count < 5) return nil;
    NSString *did = parts[2];
    NSString *rkey = parts[4];

    NSString *query = @"SELECT cid, name, created_at FROM starter_packs WHERE did = ? AND rkey = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[did, rkey] error:error];
    if (!rows || rows.count == 0) return nil;

    NSDictionary *row = rows.firstObject;
    NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:did error:nil];
    if (!record) return nil;

    NSMutableDictionary *view = [NSMutableDictionary dictionary];
    view[@"uri"] = starterPackURI;
    view[@"cid"] = row[@"cid"];
    view[@"record"] = record;
    view[@"creator"] = [self.actorService getProfileForActor:did error:nil] ?: @{@"did": did};
    view[@"indexedAt"] = row[@"created_at"] ?: @"";

    return [view copy];
}

- (nullable NSDictionary *)getStarterPacksForActor:(NSString *)actorDID
                                             limit:(NSInteger)limit
                                            cursor:(nullable NSString *)cursor
                                             error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    NSString *query = @"SELECT rkey, cid, name, created_at FROM starter_packs WHERE did = ?";
    if (cursor) {
        query = [query stringByAppendingString:@" AND rkey < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithObject:actorDID];
    if (cursor) {
        [args addObject:cursor];
    }
    [args addObject:@(limit)];

    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];
    if (!rows) return nil;

    NSMutableArray *starterPacks = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.starterpack/%@", actorDID, row[@"rkey"]];
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:actorDID error:nil];
        if (record) {
            [starterPacks addObject:@{
                @"uri": uri,
                @"cid": row[@"cid"],
                @"record": record,
                @"creator": [self.actorService getProfileForActor:actorDID error:nil] ?: @{@"did": actorDID},
                @"indexedAt": row[@"created_at"] ?: @""
            }];
        }
    }

    NSString *nextCursor = nil;
    if (starterPacks.count > 0 && starterPacks.count == limit) {
        nextCursor = [[rows lastObject] objectForKey:@"rkey"];
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"starterPacks"] = starterPacks;
    if (nextCursor) {
        result[@"cursor"] = nextCursor;
    }

    return [result copy];
}

- (nullable NSDictionary *)searchStarterPacks:(NSString *)searchQuery
                                        limit:(NSInteger)limit
                                       cursor:(nullable NSString *)cursor
                                        error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    NSString *sql = @"SELECT did, rkey, cid, name, created_at FROM starter_packs WHERE name LIKE ? ORDER BY created_at DESC LIMIT ?";
    NSString *likeQuery = [NSString stringWithFormat:@"%%%@%%", searchQuery];
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[likeQuery, @(limit)] error:error];
    if (!rows) return nil;

    NSMutableArray *starterPacks = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSString *did = row[@"did"];
        NSString *rkey = row[@"rkey"];
        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.starterpack/%@", did, rkey];
        NSDictionary *record = [self getRecordBodyFromCID:row[@"cid"] did:did error:nil];
        if (record) {
            [starterPacks addObject:@{
                @"uri": uri,
                @"cid": row[@"cid"],
                @"record": record,
                @"creator": [self.actorService getProfileForActor:did error:nil] ?: @{@"did": did},
                @"indexedAt": row[@"created_at"] ?: @""
            }];
        }
    }

    return @{@"starterPacks": starterPacks};
}

- (BOOL)indexStarterPack:(NSDictionary *)record
                     did:(NSString *)did
                    rkey:(NSString *)rkey
                     cid:(NSString *)cid
                   error:(NSError **)error {
    NSString *name = record[@"name"] ?: @"";
    NSString *createdAt = record[@"createdAt"] ?: @"";

    NSString *sql = @"INSERT OR REPLACE INTO starter_packs (did, rkey, cid, name, created_at) VALUES (?, ?, ?, ?, ?)";
    return [self.database executeParameterizedUpdate:sql params:@[did, rkey, cid, name, createdAt] error:error];
}

- (BOOL)unindexStarterPackWithRKey:(NSString *)rkey
                               did:(NSString *)did
                             error:(NSError **)error {
    NSString *sql = @"DELETE FROM starter_packs WHERE did = ? AND rkey = ?";
    return [self.database executeParameterizedUpdate:sql params:@[did, rkey] error:error];
}

#pragma mark - Indexing

- (BOOL)indexList:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error {
    NSString *name = record[@"name"];
    NSString *purpose = record[@"purpose"];
    NSString *description = record[@"description"];
    NSString *avatar = record[@"avatar"]; // CID
    
    NSString *sql = @"INSERT OR REPLACE INTO bsky_graph_lists (uri, did, name, purpose, description, avatar_blob_cid, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    return [self.database executeParameterizedUpdate:sql params:@[uri, did, name ?: @"", purpose ?: @"", description ?: @"", avatar ?: [NSNull null], @((long long)now)] error:error];
}

- (BOOL)unindexListWithURI:(NSString *)uri error:(NSError **)error {
    NSString *sql = @"DELETE FROM bsky_graph_lists WHERE uri = ?";
    return [self.database executeParameterizedUpdate:sql params:@[uri] error:error];
}

- (BOOL)indexListitem:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error {
    NSString *listUri = record[@"list"];
    NSString *subjectDid = record[@"subject"];
    
    NSString *sql = @"INSERT OR REPLACE INTO bsky_graph_listitems (uri, list_uri, subject_did, created_at) VALUES (?, ?, ?, ?)";
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    return [self.database executeParameterizedUpdate:sql params:@[uri, listUri ?: @"", subjectDid ?: @"", @((long long)now)] error:error];
}

- (BOOL)unindexListitemWithURI:(NSString *)uri error:(NSError **)error {
    NSString *sql = @"DELETE FROM bsky_graph_listitems WHERE uri = ?";
    return [self.database executeParameterizedUpdate:sql params:@[uri] error:error];
}

@end
