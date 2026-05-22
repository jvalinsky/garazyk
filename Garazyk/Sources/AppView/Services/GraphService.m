// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
#import "Core/ATProtoDagCBOR.h"
#import "Core/ATURI.h"
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

- (nullable NSDictionary *)recordBodyFromRow:(NSDictionary *)row did:(NSString *)did error:(NSError **)error {
    NSString *cid = row[@"cid"] != [NSNull null] ? row[@"cid"] : nil;
    NSDictionary *record = cid.length > 0 ? [self getRecordBodyFromCID:cid did:did error:error] : nil;
    if (record) return record;

    NSString *value = row[@"value"] != [NSNull null] ? row[@"value"] : nil;
    if (value.length == 0) return nil;

    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (NSDictionary *)listViewForURI:(NSString *)uri
                              did:(NSString *)did
                           record:(nullable NSDictionary *)record
                       indexedAt:(nullable id)indexedAt
                              cid:(nullable NSString *)cid {
    NSMutableDictionary *listView = [NSMutableDictionary dictionary];
    listView[@"uri"] = uri ?: @"";
    if (cid.length > 0) listView[@"cid"] = cid;
    listView[@"name"] = record[@"name"] ?: @"";
    listView[@"purpose"] = record[@"purpose"] ?: @"";
    listView[@"description"] = record[@"description"] ?: @"";
    listView[@"creator"] = [self.actorService getProfileForActor:did error:nil] ?: @{@"did": did ?: @""};
    listView[@"indexedAt"] = record[@"createdAt"] ?: indexedAt ?: @"";
    return listView;
}

- (BOOL)parseListURI:(NSString *)listURI did:(NSString **)didOut rkey:(NSString **)rkeyOut {
    NSArray<NSString *> *components = [listURI componentsSeparatedByString:@"/"];
    if (components.count < 5) return NO;
    NSString *did = components[2];
    NSString *collection = components[3];
    NSString *rkey = components[4];
    if (![collection isEqualToString:@"app.bsky.graph.list"] || did.length == 0 || rkey.length == 0) {
        return NO;
    }
    if (didOut) *didOut = did;
    if (rkeyOut) *rkeyOut = rkey;
    return YES;
}

- (nullable NSDictionary *)getRecordBodyFromCID:(NSString *)cidStr did:(NSString *)did error:(NSError **)error {
    CID *cid = [CID cidFromString:cidStr];
    if (!cid) return nil;
    PDSDatabaseBlock *block = [self.database getBlockWithCid:cid.bytes repoDid:did error:error];
    if (!block || !block.blockData) return nil;
    id decoded = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:error];
    if (!decoded) {
        decoded = [ATProtoDagCBOR decodeData:block.blockData error:error];
    }
    return [decoded isKindOfClass:[NSDictionary class]] ? decoded : nil;
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
    ATURI *parsedURI = [ATURI uriWithString:starterPackURI error:nil];
    if (!parsedURI) return nil;
    NSString *did = parsedURI.did;
    NSString *rkey = parsedURI.rkey;

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

- (nullable NSArray<NSDictionary *> *)getStarterPacks:(NSArray<NSString *> *)uris error:(NSError **)error {
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:uris.count];
    for (NSString *uri in uris) {
        NSDictionary *view = [self getStarterPack:uri error:nil];
        if (view) {
            [results addObject:view];
        }
    }
    return [results copy];
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
    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.starterpack/%@", did, rkey];

    NSString *sql = @"INSERT OR REPLACE INTO starter_packs (uri, did, rkey, cid, name, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    return [self.database executeParameterizedUpdate:sql params:@[uri, did, rkey, cid, name, createdAt] error:error];
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
    
    NSString *sql = @"INSERT OR REPLACE INTO bsky_graph_lists (uri, did, name, purpose, description, avatar_cid, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";
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

#pragma mark - Query Lists

- (nullable NSDictionary *)getListsForActor:(NSString *)actorDID
                                      limit:(NSInteger)limit
                                     cursor:(nullable NSString *)cursor
                                      error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    NSString *query = @"SELECT uri, did, name, purpose, description, avatar_cid, created_at FROM bsky_graph_lists WHERE did = ?";
    if (cursor) {
        query = [query stringByAppendingString:@" AND created_at < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY created_at DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithObject:actorDID];
    if (cursor) {
        [args addObject:cursor];
    }
    [args addObject:@(limit + 1)];

    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];
    if (!rows) {
        return @{@"lists": @[]};
    }

    NSMutableArray *lists = [NSMutableArray array];
    NSString *nextCursor = nil;

    NSMutableSet *seenURIs = [NSMutableSet set];

    for (NSUInteger i = 0; i < rows.count && (NSInteger)i < limit; i++) {
        NSDictionary *row = rows[i];
        NSString *did = row[@"did"];
        NSString *uri = row[@"uri"];
        if (uri.length > 0) [seenURIs addObject:uri];

        NSDictionary *record = @{
            @"name": row[@"name"] ?: @"",
            @"purpose": row[@"purpose"] ?: @"",
            @"description": row[@"description"] ?: @""
        };
        NSDictionary *listView = [self listViewForURI:uri did:did record:record indexedAt:row[@"created_at"] cid:nil];

        [lists addObject:listView];

        if (i == (NSUInteger)(limit - 1) && rows.count > (NSUInteger)limit) {
            nextCursor = row[@"created_at"];
        }
    }

    if ((NSInteger)lists.count < limit) {
        NSString *recordQuery = @"SELECT uri, did, rkey, cid, value, indexed_at FROM records WHERE did = ? AND collection = ?";
        if (cursor) {
            recordQuery = [recordQuery stringByAppendingString:@" AND rkey < ?"];
        }
        recordQuery = [recordQuery stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];

        NSMutableArray *recordArgs = [NSMutableArray arrayWithObjects:actorDID, @"app.bsky.graph.list", nil];
        if (cursor) [recordArgs addObject:cursor];
        [recordArgs addObject:@(limit + 1)];

        NSArray *recordRows = [self.database executeParameterizedQuery:recordQuery params:recordArgs error:error];
        for (NSUInteger i = 0; i < recordRows.count && (NSInteger)lists.count < limit; i++) {
            NSDictionary *row = recordRows[i];
            NSString *uri = row[@"uri"];
            if (uri.length == 0 || [seenURIs containsObject:uri]) continue;

            NSDictionary *record = [self recordBodyFromRow:row did:actorDID error:nil];
            if (!record) continue;

            NSString *cid = row[@"cid"] != [NSNull null] ? row[@"cid"] : nil;
            NSDictionary *listView = [self listViewForURI:uri
                                                       did:actorDID
                                                    record:record
                                                 indexedAt:row[@"indexed_at"]
                                                       cid:cid];
            [lists addObject:listView];
            [seenURIs addObject:uri];

            if ((NSInteger)lists.count == limit && recordRows.count > i + 1) {
                nextCursor = row[@"rkey"];
            }
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"lists"] = lists;
    if (nextCursor) {
        result[@"cursor"] = nextCursor;
    }

    return [result copy];
}

- (nullable NSDictionary *)getList:(NSString *)listURI
                             limit:(NSInteger)limit
                            cursor:(nullable NSString *)cursor
                             error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    // Get list metadata
    NSString *listQuery = @"SELECT uri, did, name, purpose, description, avatar_cid, created_at FROM bsky_graph_lists WHERE uri = ?";
    NSArray *listRows = [self.database executeParameterizedQuery:listQuery params:@[listURI] error:error];
    if (!listRows) {
        return nil;
    }

    NSDictionary *listRow = listRows.firstObject;
    NSString *creatorDID = listRow[@"did"];
    NSDictionary *listRecord = nil;

    if (!listRow) {
        NSString *rkey = nil;
        if (![self parseListURI:listURI did:&creatorDID rkey:&rkey]) {
            return nil;
        }
        NSString *recordQuery = @"SELECT uri, did, rkey, cid, value, indexed_at FROM records WHERE did = ? AND collection = ? AND rkey = ? LIMIT 1";
        NSArray *recordRows = [self.database executeParameterizedQuery:recordQuery
                                                                 params:@[creatorDID, @"app.bsky.graph.list", rkey]
                                                                  error:error];
        listRow = recordRows.firstObject;
        if (!listRow) return nil;
        listRecord = [self recordBodyFromRow:listRow did:creatorDID error:nil];
    } else {
        listRecord = @{
            @"name": listRow[@"name"] ?: @"",
            @"purpose": listRow[@"purpose"] ?: @"",
            @"description": listRow[@"description"] ?: @""
        };
    }

    NSString *cid = listRow[@"cid"] != [NSNull null] ? listRow[@"cid"] : nil;
    NSDictionary *listView = [self listViewForURI:listURI
                                              did:creatorDID
                                           record:listRecord
                                        indexedAt:listRow[@"created_at"] ?: listRow[@"indexed_at"]
                                              cid:cid];

    // Get items
    NSString *itemsQuery = @"SELECT uri, list_uri, subject_did, created_at FROM bsky_graph_listitems WHERE list_uri = ?";
    if (cursor) {
        itemsQuery = [itemsQuery stringByAppendingString:@" AND created_at < ?"];
    }
    itemsQuery = [itemsQuery stringByAppendingString:@" ORDER BY created_at DESC LIMIT ?"];

    NSMutableArray *itemArgs = [NSMutableArray arrayWithObject:listURI];
    if (cursor) {
        [itemArgs addObject:cursor];
    }
    [itemArgs addObject:@(limit + 1)];

    NSArray *itemRows = [self.database executeParameterizedQuery:itemsQuery params:itemArgs error:error];

    NSMutableArray *items = [NSMutableArray array];
    NSString *nextCursor = nil;

    for (NSUInteger i = 0; itemRows && (NSInteger)i < limit && i < itemRows.count; i++) {
        NSDictionary *row = itemRows[i];
        NSString *subjectDID = row[@"subject_did"];

        NSMutableDictionary *itemView = [NSMutableDictionary dictionary];
        itemView[@"uri"] = row[@"uri"];
        itemView[@"subject"] = [self.actorService getProfileForActor:subjectDID error:nil] ?: @{@"did": subjectDID};
        itemView[@"indexedAt"] = row[@"created_at"] ?: @"";

        [items addObject:itemView];

        if (i == (NSUInteger)(limit - 1) && itemRows.count > (NSUInteger)limit) {
            nextCursor = row[@"created_at"];
        }
    }

    if (items.count == 0 && creatorDID.length > 0) {
        NSString *recordItemQuery = @"SELECT uri, did, rkey, cid, value, indexed_at FROM records WHERE did = ? AND collection = ? ORDER BY rkey DESC LIMIT ?";
        NSArray *recordItemRows = [self.database executeParameterizedQuery:recordItemQuery
                                                                    params:@[creatorDID, @"app.bsky.graph.listitem", @(limit + 1)]
                                                                     error:error];
        for (NSUInteger i = 0; i < recordItemRows.count && (NSInteger)items.count < limit; i++) {
            NSDictionary *row = recordItemRows[i];
            NSDictionary *record = [self recordBodyFromRow:row did:creatorDID error:nil];
            if (![record[@"list"] isEqualToString:listURI]) continue;

            NSString *subjectDID = record[@"subject"];
            if (subjectDID.length == 0) continue;

            NSMutableDictionary *itemView = [NSMutableDictionary dictionary];
            itemView[@"uri"] = row[@"uri"] ?: [NSString stringWithFormat:@"at://%@/app.bsky.graph.listitem/%@", creatorDID, row[@"rkey"] ?: @""];
            itemView[@"subject"] = [self.actorService getProfileForActor:subjectDID error:nil] ?: @{@"did": subjectDID};
            itemView[@"indexedAt"] = record[@"createdAt"] ?: row[@"indexed_at"] ?: @"";
            [items addObject:itemView];

            if ((NSInteger)items.count == limit && recordItemRows.count > i + 1) {
                nextCursor = row[@"rkey"];
            }
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"list"] = listView;
    result[@"items"] = items;
    if (nextCursor) {
        result[@"cursor"] = nextCursor;
    }

    return [result copy];
}

@end
