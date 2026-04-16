#import "AppView/Services/NotificationService.h"
#import "AppView/Services/ActorService.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"

@interface NotificationService ()
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) ActorService *actorService;
@end

@implementation NotificationService

- (instancetype)initWithDatabase:(PDSDatabase *)database
                    actorService:(nullable ActorService *)actorService {
    self = [super init];
    if (self) {
        _database = database;
        _actorService = actorService;
        [self ensureTablesExist];
    }
    return self;
}

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    return [self initWithDatabase:database actorService:nil];
}

- (void)ensureTablesExist {
    NSString *createPushTableSQL = @"CREATE TABLE IF NOT EXISTS actor_push_tokens ("
                                   @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
                                   @"did TEXT NOT NULL, "
                                   @"device_token TEXT NOT NULL, "
                                   @"platform_token TEXT, "
                                   @"service_endpoint TEXT NOT NULL, "
                                   @"created_at TEXT DEFAULT (datetime('now')), "
                                   @"updated_at TEXT DEFAULT (datetime('now')), "
                                   @"UNIQUE(did, device_token))";

    [self.database executeRawSQL:createPushTableSQL error:nil];

    NSString *createNotificationsTableSQL = @"CREATE TABLE IF NOT EXISTS notifications ("
                                             @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
                                             @"did TEXT NOT NULL, "
                                             @"author_did TEXT NOT NULL DEFAULT '', "
                                             @"reason TEXT NOT NULL, "
                                             @"reason_subject TEXT, "
                                             @"subject_uri TEXT, "
                                             @"subject_cid TEXT, "
                                             @"is_read INTEGER DEFAULT 0, "
                                             @"indexed_at TEXT DEFAULT (datetime('now')))";

    [self.database executeRawSQL:createNotificationsTableSQL error:nil];

    // Migration: add author_did column if it doesn't exist
    [self.database executeRawSQL:@"ALTER TABLE notifications ADD COLUMN author_did TEXT NOT NULL DEFAULT ''" error:nil];

    NSString *createActivitySubscriptionsSQL = @"CREATE TABLE IF NOT EXISTS actor_activity_subscriptions ("
                                              @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
                                              @"owner_did TEXT NOT NULL, "
                                              @"subject_did TEXT NOT NULL, "
                                              @"post_enabled INTEGER DEFAULT 1, "
                                              @"reply_enabled INTEGER DEFAULT 1, "
                                              @"created_at TEXT DEFAULT (datetime('now')), "
                                              @"updated_at TEXT DEFAULT (datetime('now')), "
                                              @"UNIQUE(owner_did, subject_did))";
    [self.database executeRawSQL:createActivitySubscriptionsSQL error:nil];
}

- (BOOL)registerPushForActor:(NSString *)actorDID
                 deviceToken:(NSString *)deviceToken
               platformToken:(nullable NSString *)platformToken
               serviceEndpoint:(NSString *)serviceEndpoint
                       error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"NotificationService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return NO;
    }

    if (!deviceToken || deviceToken.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"NotificationService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing device token"}];
        }
        return NO;
    }

    NSString *checkQuery = @"SELECT id FROM actor_push_tokens WHERE did = ? AND device_token = ?";
    NSArray *existingRows = [self.database executeParameterizedQuery:checkQuery params:@[actorDID, deviceToken] error:nil];

    NSString *query;
    if (existingRows && existingRows.count > 0) {
        query = @"UPDATE actor_push_tokens SET platform_token = ?, service_endpoint = ?, updated_at = datetime('now') WHERE did = ? AND device_token = ?";
        BOOL success = [self.database executeParameterizedUpdate:query params:@[platformToken ?: [NSNull null], serviceEndpoint, actorDID, deviceToken] error:error];
        return success;
    } else {
        query = @"INSERT INTO actor_push_tokens (did, device_token, platform_token, service_endpoint) VALUES (?, ?, ?, ?)";
        BOOL success = [self.database executeParameterizedUpdate:query params:@[actorDID, deviceToken, platformToken ?: [NSNull null], serviceEndpoint] error:error];
        return success;
    }
}

- (BOOL)unregisterPushForActor:(NSString *)actorDID error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"NotificationService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return NO;
    }

    NSString *query = @"DELETE FROM actor_push_tokens WHERE did = ?";
    BOOL success = [self.database executeParameterizedUpdate:query params:@[actorDID] error:error];

    if (!success && error) {
        *error = [NSError errorWithDomain:@"NotificationService" code:500 userInfo:@{NSLocalizedDescriptionKey: @"Failed to unregister push tokens"}];
    }

    return success;
}

- (nullable NSArray<NSDictionary *> *)getNotificationsForActor:(NSString *)actorDID
                                                          limit:(NSInteger)limit
                                                        cursor:(nullable NSString *)cursor
                                                          error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"NotificationService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return nil;
    }

    limit = MIN(limit > 0 ? limit : 30, 100);

    NSMutableArray *notifications = [NSMutableArray array];

    NSMutableString *query = [NSMutableString stringWithString:@"SELECT * FROM notifications WHERE did = ?"];
    if (cursor) {
        [query appendString:@" AND id < ?"];
    }
    [query appendString:@" ORDER BY id DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithObjects:actorDID, nil];
    if (cursor) {
        [args addObject:@( [cursor integerValue] )];
    }
    [args addObject:@(limit)];

    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];
    for (NSDictionary *row in rows) {
        NSString *reason = row[@"reason"] ?: @"";
        NSString *reasonSubject = row[@"reason_subject"];
        NSString *subjectURI = row[@"subject_uri"];
        NSString *subjectCID = row[@"subject_cid"];
        NSString *authorDID = row[@"author_did"] ?: @"";
        NSInteger notifId = [row[@"id"] integerValue];
        NSString *indexedAt = row[@"indexed_at"] ?: @"";
        BOOL isRead = [row[@"is_read"] boolValue];

        // Hydrate author profile
        NSDictionary *author = nil;
        if (self.actorService && authorDID.length > 0) {
            author = [self.actorService getProfileForActor:authorDID error:nil];
        }
        if (!author && authorDID.length > 0) {
            author = @{@"did": authorDID, @"handle": @"handle.invalid"};
        }

        // Fetch the actual record that caused the notification
        NSDictionary *record = @{};
        if (subjectURI && subjectCID) {
            // Try to load the record from the blocks table
            CID *cid = [CID cidFromString:subjectCID];
            if (cid && authorDID.length > 0) {
                PDSDatabaseBlock *block = [self.database getBlockWithCid:cid.bytes repoDid:authorDID error:nil];
                if (block && block.blockData) {
                    NSDictionary *decoded = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
                    if (decoded) record = decoded;
                }
            }
        }

        NSMutableDictionary *notification = [NSMutableDictionary dictionary];
        notification[@"uri"] = subjectURI ?: @"";
        notification[@"cid"] = subjectCID ?: @"";
        notification[@"author"] = author ?: @{@"did": @"", @"handle": @""};
        notification[@"reason"] = reason;
        if (reasonSubject && ![reasonSubject isKindOfClass:[NSNull class]]) {
            notification[@"reasonSubject"] = reasonSubject;
        }
        notification[@"record"] = record;
        notification[@"isRead"] = @(isRead);
        notification[@"indexedAt"] = indexedAt;
        notification[@"labels"] = @[];

        [notifications addObject:notification];
    }

    return [notifications copy];
}

- (nullable NSDictionary *)getSubjectForNotification:(NSInteger)notificationId {
    NSString *query = @"SELECT subject_uri, subject_cid FROM notifications WHERE id = ?";
    NSArray *rows = [self.database executeParameterizedQuery:query params:@[@(notificationId)] error:nil];

    if (rows && rows.count > 0) {
        NSDictionary *row = rows.firstObject;
        NSString *uri = row[@"subject_uri"];
        NSString *cid = row[@"subject_cid"];
        if (uri) {
            return @{
                @"uri": uri,
                @"cid": cid ?: @""
            };
        }
    }
    return nil;
}

- (BOOL)markNotificationsAsReadForActor:(NSString *)actorDID
                                  limit:(NSInteger)limit
                                    error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"NotificationService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return NO;
    }

    NSMutableString *query = [NSMutableString stringWithString:@"UPDATE notifications SET is_read = 1 WHERE did = ? AND is_read = 0"];
    if (limit > 0) {
        [query appendString:@" AND id IN (SELECT id FROM notifications WHERE did = ? ORDER BY id DESC LIMIT ?)"];
    }

    NSMutableArray *args = [NSMutableArray arrayWithObject:actorDID];
    if (limit > 0) {
        [args addObject:actorDID];
        [args addObject:@(limit)];
    }

    NSError *queryError = nil;
    NSArray *result = [self.database executeParameterizedQuery:query params:args error:&queryError];

    if (queryError) {
        if (error) {
            *error = [NSError errorWithDomain:@"NotificationService" code:500 userInfo:@{NSLocalizedDescriptionKey: @"Failed to mark notifications as read", NSUnderlyingErrorKey: queryError}];
        }
        return NO;
    }

    return YES;
}

- (BOOL)createNotificationForActor:(NSString *)actorDID
                          authorDID:(NSString *)authorDID
                             reason:(NSString *)reason
                      reasonSubject:(nullable NSString *)reasonSubject
                         subjectURI:(nullable NSString *)subjectURI
                         subjectCID:(nullable NSString *)subjectCID
                              error:(NSError **)error {
    if (!actorDID || !reason || !authorDID) {
        return NO;
    }

    NSString *sql = @"INSERT INTO notifications (did, author_did, reason, reason_subject, subject_uri, subject_cid) VALUES (?, ?, ?, ?, ?, ?)";
    return [self.database executeParameterizedUpdate:sql
                                              params:@[
                                                  actorDID,
                                                  authorDID,
                                                  reason,
                                                  reasonSubject ?: [NSNull null],
                                                  subjectURI ?: [NSNull null],
                                                  subjectCID ?: [NSNull null]
                                              ]
                                               error:error];
}

- (NSInteger)getUnreadCountForActor:(NSString *)actorDID error:(NSError **)error {
    if (!actorDID) return 0;

    NSString *sql = @"SELECT COUNT(*) as count FROM notifications WHERE did = ? AND is_read = 0";
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[actorDID] error:error];
    if (rows.count > 0) {
        return [rows[0][@"count"] integerValue];
    }
    return 0;
}

- (BOOL)deleteNotificationsForSubjectURI:(NSString *)subjectURI error:(NSError **)error {
    if (!subjectURI) return YES;

    NSString *sql = @"DELETE FROM notifications WHERE subject_uri = ?";
    return [self.database executeParameterizedUpdate:sql params:@[subjectURI] error:error];
}

- (BOOL)unregisterPushToken:(NSString *)deviceToken
                   forActor:(NSString *)actorDID
                      error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"NotificationService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return NO;
    }
    if (!deviceToken || deviceToken.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"NotificationService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing device token"}];
        }
        return NO;
    }

    NSString *query = @"DELETE FROM actor_push_tokens WHERE did = ? AND device_token = ?";
    return [self.database executeParameterizedUpdate:query params:@[actorDID, deviceToken] error:error];
}

- (BOOL)putActivitySubscriptionForActor:(NSString *)actorDID
                               subject:(NSString *)subjectDID
                          postEnabled:(BOOL)postEnabled
                          replyEnabled:(BOOL)replyEnabled
                                error:(NSError **)error {
    if (!actorDID || actorDID.length == 0 || !subjectDID || subjectDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"NotificationService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameter"}];
        }
        return NO;
    }

    NSString *query = @"INSERT INTO actor_activity_subscriptions (owner_did, subject_did, post_enabled, reply_enabled) VALUES (?, ?, ?, ?) "
                      @"ON CONFLICT(owner_did, subject_did) DO UPDATE SET post_enabled = excluded.post_enabled, reply_enabled = excluded.reply_enabled, updated_at = datetime('now')";
    return [self.database executeParameterizedUpdate:query params:@[actorDID, subjectDID, @(postEnabled ? 1 : 0), @(replyEnabled ? 1 : 0)] error:error];
}

- (nullable NSDictionary *)getActivitySubscriptionsForActor:(NSString *)actorDID
                                                      limit:(NSInteger)limit
                                                    cursor:(nullable NSString *)cursor
                                                      error:(NSError **)error {
    if (!actorDID || actorDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"NotificationService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing actor DID"}];
        }
        return nil;
    }

    limit = MIN(limit > 0 ? limit : 50, 100);

    NSMutableString *query = [NSMutableString stringWithString:@"SELECT id, subject_did FROM actor_activity_subscriptions WHERE owner_did = ?"];
    if (cursor) {
        [query appendString:@" AND id > ?"];
    }
    [query appendString:@" ORDER BY id ASC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithObject:actorDID];
    if (cursor) {
        [args addObject:@([cursor integerValue])];
    }
    [args addObject:@(limit)];

    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];
    NSMutableArray *subscriptions = [NSMutableArray array];

    for (NSDictionary *row in rows) {
        NSString *subjectDID = row[@"subject_did"];
        if (!subjectDID || subjectDID.length == 0) continue;

        NSDictionary *profile = nil;
        if (self.actorService) {
            profile = [self.actorService getProfileForActor:subjectDID error:nil];
        }
        if (!profile) {
            profile = @{@"did": subjectDID, @"handle": @"handle.invalid"};
        }
        [subscriptions addObject:profile];
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:subscriptions forKey:@"subscriptions"];
    if (rows.count >= (NSUInteger)limit) {
        NSDictionary *lastRow = rows.lastObject;
        result[@"cursor"] = [NSString stringWithFormat:@"%@", lastRow[@"id"]];
    }
    return [result copy];
}

@end
