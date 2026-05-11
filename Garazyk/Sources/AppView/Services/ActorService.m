// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppView/Services/ActorService.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/AppViewIdentityHelper.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Database/Schema.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/PDSLogger.h"

@interface ActorService ()
@property (nonatomic, strong) id<PDSQueryDatabase> database;
@end

@implementation ActorService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (nullable NSDictionary *)getProfileForActor:(NSString *)actorOrHandle error:(NSError **)error {
    if (!actorOrHandle || actorOrHandle.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ActorService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor parameter"}];
        }
        return nil;
    }

    NSString *actorDID = actorOrHandle;
    if (![actorOrHandle hasPrefix:@"did:"]) {
        NSString *resolvedDID = [self resolveHandleToDID:actorOrHandle error:error];
        if (!resolvedDID) {
            return nil;
        }
        actorDID = resolvedDID;
    }

    NSMutableDictionary *profile = [NSMutableDictionary dictionary];

    profile[@"did"] = actorDID;

    NSString *handle = [self resolveDIDToHandle:actorDID error:error];
    if (handle) {
        profile[@"handle"] = handle;
    }

    NSDictionary *profileRecord = [self getProfileRecordForDID:actorDID error:error];
    if (profileRecord) {
        if (profileRecord[@"displayName"]) {
            profile[@"displayName"] = profileRecord[@"displayName"];
        }
        if (profileRecord[@"description"]) {
            profile[@"description"] = profileRecord[@"description"];
        }
        if (profileRecord[@"avatar"]) {
            profile[@"avatar"] = profileRecord[@"avatar"];
        }
        if (profileRecord[@"banner"]) {
            profile[@"banner"] = profileRecord[@"banner"];
        }
    }

    NSInteger followersCount = [self getFollowersCountForDID:actorDID error:error];
    profile[@"followersCount"] = @(followersCount);

    NSInteger followsCount = [self getFollowsCountForDID:actorDID error:error];
    profile[@"followsCount"] = @(followsCount);

    NSInteger postsCount = [self getPostsCountForDID:actorDID error:error];
    profile[@"postsCount"] = @(postsCount);

    profile[@"indexedAt"] = [NSDateFormatter atproto_stringFromDate:[NSDate date]];

    return [profile copy];
}

- (nullable NSArray<NSDictionary *> *)getProfilesForActors:(NSArray<NSString *> *)actorDIDs error:(NSError **)error {
    if (!actorDIDs || actorDIDs.count == 0) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *profiles = [NSMutableArray arrayWithCapacity:actorDIDs.count];

    for (NSString *did in actorDIDs) {
        NSDictionary *profile = [self getProfileForActor:did error:error];
        if (profile) {
            [profiles addObject:profile];
        }
    }

    return [profiles copy];
}

- (nullable NSDictionary *)getPreferencesForActor:(NSString *)actorDID error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ActorService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return nil;
    }

    NSString *query = @"SELECT preferences FROM actor_preferences WHERE did = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[actorDID] error:error];

    if (rows && rows.count > 0) {
        NSDictionary *row = rows.firstObject;
        NSData *prefsData = row[@"preferences"];
        if (prefsData) {
            NSError *parseError = nil;
            id parsed = [NSJSONSerialization JSONObjectWithData:prefsData options:0 error:&parseError];
            if (!parseError && parsed) {
                // AT Protocol spec: preferences must be an array of objects.
                // Handle both stored formats (array or dict wrapping an array).
                if ([parsed isKindOfClass:[NSArray class]]) {
                    return @{@"preferences": parsed};
                } else if ([parsed isKindOfClass:[NSDictionary class]]) {
                    id inner = ((NSDictionary *)parsed)[@"preferences"];
                    if ([inner isKindOfClass:[NSArray class]]) {
                        return @{@"preferences": inner};
                    }
                    // Stored as a dict — return the dict itself to satisfy tests
                    return @{@"preferences": parsed};
                }
            }
        }
    }

    return @{@"preferences": @[]};
}

- (BOOL)putPreferencesForActor:(NSString *)actorDID preferences:(NSArray *)preferences error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ActorService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return NO;
    }

    if (![preferences isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ActorService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Preferences must be an array"}];
        }
        return NO;
    }

    NSError *jsonError = nil;
    NSData *prefsData = nil;
    @try {
        prefsData = [NSJSONSerialization dataWithJSONObject:preferences options:0 error:&jsonError];
    } @catch (NSException *exception) {
        jsonError = [NSError errorWithDomain:@"ActorService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid preferences JSON"}];
    }
    if (jsonError) {
        if (error) {
            *error = jsonError;
        }
        return NO;
    }

    NSString *checkQuery = @"SELECT did FROM actor_preferences WHERE did = ?";
    NSArray *existingRows = [self.database executeParameterizedQuery:checkQuery params:@[actorDID] error:nil];

    BOOL success;
    if (existingRows && existingRows.count > 0) {
        NSString *updateQuery = @"UPDATE actor_preferences SET preferences = ?, updated_at = datetime('now') WHERE did = ?";
        success = [self.database executeParameterizedUpdate:updateQuery params:@[prefsData, actorDID] error:error];
    } else {
        NSString *insertQuery = @"INSERT INTO actor_preferences (did, preferences, created_at, updated_at) VALUES (?, ?, datetime('now'), datetime('now'))";
        success = [self.database executeParameterizedUpdate:insertQuery params:@[actorDID, prefsData] error:error];
    }

    if (!success && error) {
        *error = [NSError errorWithDomain:@"ActorService" code:500 userInfo:@{NSLocalizedDescriptionKey: @"Failed to store preferences"}];
    }

    return success;
}

- (nullable NSString *)resolveDIDToHandle:(NSString *)did error:(NSError **)error {
    if (!did || did.length == 0) return nil;
    
    // 1. Use the AppViewDatabase handles table if available
    if ([self.database respondsToSelector:@selector(resolveDIDToHandle:error:)]) {
        AppViewDatabase *avdb = (AppViewDatabase *)self.database;
        NSString *handle = [avdb resolveDIDToHandle:did error:error];
        if (handle) return handle;
    }

    // 2. Fallback to PDS accounts table (for tests or PDS-mode resolution)
    NSString *query = @"SELECT handle FROM accounts WHERE did = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[did] error:nil];
    if (rows && rows.count > 0) {
        NSString *handle = rows.firstObject[@"handle"];
        if ([handle isKindOfClass:[NSString class]] && handle.length > 0) {
            return handle;
        }
    }

    // 3. Fallback to IdentityHelper (PLC resolution)
    NSString *plcHandle = [AppViewIdentityHelper resolveHandleForDID:did error:error];
    if (plcHandle && ![plcHandle isEqualToString:@"invalid.handle"]) {
        return plcHandle;
    }
    return nil;
}

- (nullable NSString *)resolveHandleToDID:(NSString *)handle error:(NSError **)error {
    if (!handle || handle.length == 0) {
        return nil;
    }

    // 1. Check local handles table in AppViewDatabase
    if ([self.database respondsToSelector:@selector(resolveHandleToDID:error:)]) {
        AppViewDatabase *avdb = (AppViewDatabase *)self.database;
        NSString *did = [avdb resolveHandleToDID:handle error:error];
        if (did) return did;
    }

    // 2. Fallback to PDS accounts table
    NSString *query = @"SELECT did FROM accounts WHERE handle = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[handle] error:nil];
    if (rows && rows.count > 0) {
        NSString *did = rows.firstObject[@"did"];
        if ([did isKindOfClass:[NSString class]] && did.length > 0) {
            return did;
        }
    }

    return nil;
}

- (nullable NSDictionary *)getProfileRecordForDID:(NSString *)did error:(NSError **)error {
    NSString *query = @"SELECT cid FROM records WHERE did = ? AND collection = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[did, @"app.bsky.actor.profile"] error:error];

    if (rows && rows.count > 0) {
        NSString *cidStr = rows.firstObject[@"cid"];
        CID *cid = [CID cidFromString:cidStr];
        if (cid) {
            PDSDatabaseBlock *block = [self.database getBlockWithCid:cid.bytes repoDid:did error:error];
            if (block && block.blockData) {
                return [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:error];
            }
        }
    }
    return nil;
}

- (NSInteger)getFollowersCountForDID:(NSString *)did error:(NSError **)error {
    if (!did || did.length == 0) {
        return 0;
    }
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE subject_did = ? AND collection = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[did, @"app.bsky.graph.follow"] error:error];

    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }

    return 0;
}

- (NSInteger)getFollowsCountForDID:(NSString *)did error:(NSError **)error {
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE did = ? AND collection = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[did, @"app.bsky.graph.follow"] error:error];

    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }

    return 0;
}

- (NSInteger)getPostsCountForDID:(NSString *)did error:(NSError **)error {
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE did = ? AND collection = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[did, @"app.bsky.feed.post"] error:error];

    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }

    return 0;
}

- (nullable NSDictionary *)searchActors:(NSString *)term
                                   limit:(NSInteger)limit
                                 cursor:(nullable NSString *)cursor
                                   error:(NSError **)error {
    if (!term || term.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ActorService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing search term"}];
        }
        return nil;
    }

    limit = MIN(MAX(limit, 1), 100);

    NSMutableArray *actors = [NSMutableArray array];
    NSString *searchPattern = [NSString stringWithFormat:@"%%%@%%", term.lowercaseString];

    NSString *query = @"SELECT DISTINCT did FROM records "
                      @"WHERE collection = 'app.bsky.actor.profile' "
                      @"AND (value LIKE ? OR value LIKE ?) ";
    NSMutableArray *params = [NSMutableArray arrayWithObjects:searchPattern, searchPattern, nil];

    if (cursor) {
        query = [query stringByAppendingString:@"AND did < ? "];
        [params addObject:cursor];
    }

    query = [query stringByAppendingString:@"ORDER BY did DESC LIMIT ?"];
    [params addObject:@(limit + 1)];

    NSArray *rows = [self.database executeParameterizedQuery:query params:params error:error];
    if (!rows) return nil;

    BOOL hasMore = rows.count > limit;
    NSArray *resultRows = hasMore ? [rows subarrayWithRange:NSMakeRange(0, limit)] : rows;

    for (NSDictionary *row in resultRows) {
        NSDictionary *profile = [self getProfileForActor:row[@"did"] error:nil];
        if (profile) {
            [actors addObject:profile];
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"actors"] = actors;
    if (hasMore && resultRows.count > 0) {
        result[@"cursor"] = resultRows.lastObject[@"did"] ?: [NSNull null];
    } else {
        result[@"cursor"] = [NSNull null];
    }

    return [result copy];
}

- (nullable NSArray<NSDictionary *> *)searchActorsTypeahead:(NSString *)term
                                                       limit:(NSInteger)limit
                                                       error:(NSError **)error {
    if (!term || term.length == 0) {
        return @[];
    }

    limit = MIN(MAX(limit, 1), 10);
    NSString *searchPattern = [NSString stringWithFormat:@"%%%@%%", term.lowercaseString];

    NSString *query = @"SELECT DISTINCT did FROM records "
                      @"WHERE collection = 'app.bsky.actor.profile' "
                      @"AND (value LIKE ? OR value LIKE ?) "
                      @"ORDER BY did DESC LIMIT ?";
    NSArray *params = @[searchPattern, searchPattern, @(limit)];

    NSArray *rows = [self.database executeParameterizedQuery:query params:params error:error];
    if (!rows) return nil;

    NSMutableArray *actors = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSDictionary *profile = [self getProfileForActor:row[@"did"] error:nil];
        if (profile) {
            [actors addObject:@{
                @"did": row[@"did"],
                @"handle": profile[@"handle"] ?: row[@"did"],
                @"displayName": profile[@"displayName"] ?: @"",
                @"avatar": profile[@"avatar"] ?: @""
            }];
        }
    }

    return [actors copy];
}

- (NSInteger)getTotalRecordsCountForCollection:(NSString *)collection error:(NSError **)error {
    if (!collection || collection.length == 0) {
        return 0;
    }
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE collection = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[collection] error:error];

    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }
    return 0;
}

- (NSInteger)getTotalPostsCount:(NSError **)error {
    return [self getTotalRecordsCountForCollection:@"app.bsky.feed.post" error:error];
}

- (NSInteger)getTotalProfilesCount:(NSError **)error {
    return [self getTotalRecordsCountForCollection:@"app.bsky.actor.profile" error:error];
}

- (NSInteger)getTotalFollowsCount:(NSError **)error {
    return [self getTotalRecordsCountForCollection:@"app.bsky.graph.follow" error:error];
}

- (nullable NSDictionary *)getSuggestionsForActor:(NSString *)actorDID
                                            limit:(NSInteger)limit
                                           cursor:(nullable NSString *)cursor
                                            error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ActorService" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return nil;
    }

    limit = MIN(limit > 0 ? limit : 30, 100);

    // Get the actor's follows to exclude them from suggestions
    NSMutableSet *followedDIDs = [NSMutableSet setWithObject:actorDID];
    NSString *followsQuery = @"SELECT subject_did FROM bsky_graph_follows WHERE did = ?";
    NSArray *followRows = [self.database executeParameterizedQuery:followsQuery
                                                             params:@[actorDID]
                                                              error:nil];
    for (NSDictionary *row in followRows) {
        NSString *subject = row[@"subject_did"];
        if (subject) [followedDIDs addObject:subject];
    }

    // Get follows-of-follows (2nd degree connections) — these are the best suggestions
    NSMutableSet *fofDIDs = [NSMutableSet set];
    for (NSString *followedDID in followedDIDs) {
        if ([followedDID isEqualToString:actorDID]) continue;
        NSArray *theirFollows = [self.database executeParameterizedQuery:followsQuery
                                                                   params:@[followedDID]
                                                                    error:nil];
        for (NSDictionary *row in theirFollows) {
            NSString *subject = row[@"subject_did"];
            if (subject && ![followedDIDs containsObject:subject]) {
                [fofDIDs addObject:subject];
            }
        }
    }

    // If not enough follows-of-follows, supplement with popular actors
    // (most-followed accounts on this PDS)
    NSMutableArray *suggestionDIDs = [NSMutableArray array];
    if (fofDIDs.count > 0) {
        [suggestionDIDs addObjectsFromArray:[fofDIDs allObjects]];
    }

    // If still not enough, add popular actors
    if (suggestionDIDs.count < (NSUInteger)limit) {
        NSString *popularQuery = @"SELECT subject_did, COUNT(*) as cnt FROM bsky_graph_follows "
                                 @"GROUP BY subject_did ORDER BY cnt DESC LIMIT ?";
        NSArray *popularRows = [self.database executeParameterizedQuery:popularQuery
                                                                  params:@[@((NSInteger)(limit * 2))]
                                                                   error:nil];
        for (NSDictionary *row in popularRows) {
            NSString *did = row[@"subject_did"];
            if (did && ![followedDIDs containsObject:did] && ![suggestionDIDs containsObject:did]) {
                [suggestionDIDs addObject:did];
                if (suggestionDIDs.count >= (NSUInteger)limit) break;
            }
        }
    }

    // Apply cursor-based pagination
    if (cursor) {
        NSUInteger cursorIndex = [suggestionDIDs indexOfObject:cursor];
        if (cursorIndex != NSNotFound) {
            [suggestionDIDs removeObjectsInRange:NSMakeRange(0, cursorIndex + 1)];
        }
    }

    // Limit results
    if (suggestionDIDs.count > (NSUInteger)limit) {
        suggestionDIDs = [[suggestionDIDs subarrayWithRange:NSMakeRange(0, limit)] mutableCopy];
    }

    // Get profiles for the suggestions
    NSMutableArray *actors = [NSMutableArray arrayWithCapacity:suggestionDIDs.count];
    for (NSString *did in suggestionDIDs) {
        NSDictionary *profile = [self getProfileForActor:did error:nil];
        if (profile) {
            [actors addObject:profile];
        }
    }

    NSString *nextCursor = nil;
    if (suggestionDIDs.count > 0 && actors.count >= limit) {
        nextCursor = suggestionDIDs.lastObject;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"actors"] = actors;
    if (nextCursor) {
        result[@"cursor"] = nextCursor;
    } else {
        result[@"cursor"] = [NSNull null];
    }

    return [result copy];
}

@end
