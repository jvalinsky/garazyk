#import "AppView/NotificationService.h"
#import "Database/PDSDatabase.h"

@interface NotificationService ()
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation NotificationService

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
        [self ensureTablesExist];
    }
    return self;
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
                                             @"reason TEXT NOT NULL, "
                                             @"reason_subject TEXT, "
                                             @"subject_uri TEXT, "
                                             @"subject_cid TEXT, "
                                             @"is_read INTEGER DEFAULT 0, "
                                             @"indexed_at TEXT DEFAULT (datetime('now')))";

    [self.database executeRawSQL:createNotificationsTableSQL error:nil];
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
        NSString *reason = row[@"reason"];
        NSString *reasonSubject = row[@"reason_subject"];
        NSInteger notifId = [row[@"id"] integerValue];
        NSString *indexedAt = row[@"indexed_at"] ?: @"";

        NSMutableDictionary *notification = [NSMutableDictionary dictionary];
        notification[@"uri"] = [NSString stringWithFormat:@"at://%@/app.bsky.notification.record/%ld", actorDID, (long)notifId];
        notification[@"cid"] = @"";
        notification[@"did"] = actorDID;
        notification[@"record"] = @{
            @"reason": reason ?: @"",
            @"reasonSubject": reasonSubject ?: [NSNull null],
            @"subject": [self getSubjectForNotification:notifId],
            @"isRead": @([row[@"is_read"] boolValue]),
            @"indexedAt": indexedAt
        };
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
                             reason:(NSString *)reason
                      reasonSubject:(nullable NSString *)reasonSubject
                         subjectURI:(nullable NSString *)subjectURI
                         subjectCID:(nullable NSString *)subjectCID
                              error:(NSError **)error {
    if (!actorDID || !reason) {
        return NO;
    }

    NSString *sql = @"INSERT INTO notifications (did, reason, reason_subject, subject_uri, subject_cid) VALUES (?, ?, ?, ?, ?)";
    return [self.database executeParameterizedUpdate:sql
                                              params:@[
                                                  actorDID,
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

@end
