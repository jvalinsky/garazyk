#import "AppView/ActorService.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Database/Schema.h"

@interface ActorService ()
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation ActorService

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (nullable NSDictionary *)getProfileForActor:(NSString *)actorDID error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ActorService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return nil;
    }

    NSMutableDictionary *profile = [NSMutableDictionary dictionary];

    profile[@"did"] = actorDID;

    NSString *handle = [self resolveHandleForDID:actorDID error:error];
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

    NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
    isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    isoFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    profile[@"indexedAt"] = [isoFormatter stringFromDate:[NSDate date]];

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
            NSDictionary *preferences = [NSJSONSerialization JSONObjectWithData:prefsData options:0 error:&parseError];
            if (!parseError) {
                return @{@"preferences": preferences};
            }
        }
    }

    return @{@"preferences": @{}};
}

- (BOOL)putPreferencesForActor:(NSString *)actorDID preferences:(NSDictionary *)preferences error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ActorService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return NO;
    }

    NSError *jsonError = nil;
    NSData *prefsData = [NSJSONSerialization dataWithJSONObject:preferences options:0 error:&jsonError];
    if (jsonError) {
        if (error) {
            *error = [NSError errorWithDomain:@"ActorService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid preferences JSON"}];
        }
        return NO;
    }

    NSString *checkQuery = @"SELECT id FROM actor_preferences WHERE did = ?";
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

- (nullable NSString *)resolveHandleForDID:(NSString *)did error:(NSError **)error {
    NSString *query = @"SELECT handle FROM accounts WHERE did = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[did] error:error];

    if (rows && rows.count > 0) {
        return rows.firstObject[@"handle"];
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
    // Note: 'record' column doesn't exist in records table. efficiently counting followers requires an index which PDS doesn't have.
    // Returning 0 for now as stub.
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

@end
