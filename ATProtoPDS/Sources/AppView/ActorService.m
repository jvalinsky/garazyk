#import "AppView/ActorService.h"
#import "Database/PDSDatabase.h"
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
    NSArray *rows = [self.database executeQuery:query error:error];

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
    NSArray *existingRows = [self.database executeQuery:checkQuery error:nil];

    BOOL success;
    if (existingRows && existingRows.count > 0) {
        NSString *updateQuery = @"UPDATE actor_preferences SET preferences = ?, updated_at = datetime('now') WHERE did = ?";
        success = [self.database executeRawSQL:updateQuery error:error];
    } else {
        NSString *insertQuery = @"INSERT INTO actor_preferences (did, preferences, created_at, updated_at) VALUES (?, ?, datetime('now'), datetime('now'))";
        success = [self.database executeRawSQL:insertQuery error:error];
    }

    if (!success && error) {
        *error = [NSError errorWithDomain:@"ActorService" code:500 userInfo:@{NSLocalizedDescriptionKey: @"Failed to store preferences"}];
    }

    return success;
}

- (nullable NSString *)resolveHandleForDID:(NSString *)did error:(NSError **)error {
    NSString *query = @"SELECT handle FROM accounts WHERE did = ?";
    NSArray *rows = [self.database executeQuery:query error:error];

    if (rows && rows.count > 0) {
        return rows.firstObject[@"handle"];
    }

    return nil;
}

- (nullable NSDictionary *)getProfileRecordForDID:(NSString *)did error:(NSError **)error {
    NSString *query = @"SELECT record FROM records WHERE repo = ? AND collection = ?";
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

- (NSInteger)getFollowersCountForDID:(NSString *)did error:(NSError **)error {
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE collection = ? AND record LIKE ?";
    NSArray *rows = [self.database executeQuery:query error:error];

    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }

    return 0;
}

- (NSInteger)getFollowsCountForDID:(NSString *)did error:(NSError **)error {
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE repo = ? AND collection = ?";
    NSArray *rows = [self.database executeQuery:query error:error];

    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }

    return 0;
}

- (NSInteger)getPostsCountForDID:(NSString *)did error:(NSError **)error {
    NSString *query = @"SELECT COUNT(*) as count FROM records WHERE repo = ? AND collection = ?";
    NSArray *rows = [self.database executeQuery:query error:error];

    if (rows && rows.count > 0) {
        return [rows.firstObject[@"count"] integerValue];
    }

    return 0;
}

@end
