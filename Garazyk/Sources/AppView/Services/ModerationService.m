#import "ModerationService.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"

@interface ModerationService ()
@property (nonatomic, weak) id<PDSQueryDatabase> database;
@end

@implementation ModerationService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

#pragma mark - Core Moderation Events

- (nullable NSDictionary *)emitModerationEvent:(NSDictionary *)event
                                     createdBy:(NSString *)adminDid
                                         error:(NSError **)error {
    if (!event || !adminDid) {
        if (error) *error = [NSError errorWithDomain:@"ModerationService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Event and admin DID are required"}];
        return nil;
    }

    NSString *eventId = [[NSUUID UUID] UUIDString];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    
    NSDictionary *subject = event[@"subject"];
    NSString *subjectDid = subject[@"did"] ?: @"";
    NSString *subjectType = subject[@"$type"] ?: @"com.atproto.admin.defs#repoRef";
    NSString *action = event[@"$type"] ?: @"tools.ozone.moderation.defs#modEventComment";
    NSString *reason = event[@"comment"] ?: @"";

    NSError *serializeError = nil;
    NSData *eventData = [NSJSONSerialization dataWithJSONObject:event options:0 error:&serializeError];
    NSString *eventJson = [[NSString alloc] initWithData:eventData encoding:NSUTF8StringEncoding];

    NSString *insertQuery = @"INSERT INTO moderation_events (id, action, subject_did, subject_type, reason, created_by, created_at, details_json) "
                           @"VALUES (?, ?, ?, ?, ?, ?, ?, ?)";

    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:insertQuery
                                                   params:@[eventId, action, subjectDid, subjectType,
                                                               reason, adminDid, now, eventJson]
                                                        error:error];

    if (!success) return nil;

    // Also record in general audit log
    NSString *auditQuery = @"INSERT INTO admin_audit_log (admin_did, action, subject_type, subject_id, details, created_at) "
                          @"VALUES (?, ?, ?, ?, ?, datetime('now'))";
    [(PDSDatabase *)self.database executeParameterizedUpdate:auditQuery
                                           params:@[adminDid, @"MODERATION_EVENT", subjectType, subjectDid, eventJson]
                                                error:nil];

    return @{
        @"id": eventId,
        @"event": event,
        @"createdBy": adminDid,
        @"createdAt": now
    };
}

- (nullable NSDictionary *)queryModerationStatuses:(NSDictionary *)filters
                                           limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error {
    if (limit <= 0) limit = 50;
    
    // Simplistic implementation: group events by subject
    NSString *query = @"SELECT subject_did, subject_type, MAX(created_at) as last_at, action "
                     @"FROM moderation_events GROUP BY subject_did ORDER BY last_at DESC LIMIT ?";

    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[@(limit)]
                                                                       error:error];
    if (!rows) return nil;

    NSMutableArray *statuses = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        [statuses addObject:@{
            @"subject": @{@"did": row[@"subject_did"], @"$type": row[@"subject_type"]},
            @"reviewState": @"tools.ozone.moderation.defs#reviewClosed",
            @"lastEvent": @{@"id": @"", @"action": row[@"action"]},
            @"updatedAt": row[@"last_at"]
        }];
    }

    return @{@"statuses": statuses};
}

- (nullable NSDictionary *)queryModerationEvents:(NSDictionary *)filters
                                          limit:(NSInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error {
    if (limit <= 0) limit = 50;

    NSString *sql = @"SELECT * FROM moderation_events ORDER BY created_at DESC LIMIT ?";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:sql
                                                                      params:@[@(limit)]
                                                                       error:error];
    if (!rows) return nil;

    NSMutableArray *events = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        [events addObject:@{
            @"id": row[@"id"],
            @"action": row[@"action"],
            @"subject": row[@"subject_did"],
            @"createdBy": row[@"created_by"],
            @"createdAt": row[@"created_at"],
            @"comment": row[@"reason"]
        }];
    }

    return @{@"events": events};
}

- (nullable NSDictionary *)getModerationEvent:(NSString *)eventId
                                        error:(NSError **)error {
    NSString *query = @"SELECT * FROM moderation_events WHERE id = ?";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[eventId]
                                                                       error:error];
    if (!rows || rows.count == 0) return nil;
    
    NSDictionary *row = rows[0];
    return @{
        @"id": row[@"id"],
        @"action": row[@"action"],
        @"subject": row[@"subject_did"],
        @"createdBy": row[@"created_by"],
        @"createdAt": row[@"created_at"],
        @"comment": row[@"reason"]
    };
}

#pragma mark - Subject Information

- (nullable NSDictionary *)getModerationRecord:(NSString *)uri
                                          error:(NSError **)error {
    return @{@"uri": uri, @"value": @{}, @"labels": @[]};
}

- (nullable NSArray<NSDictionary *> *)getModerationRecords:(NSArray<NSString *> *)uris
                                                      error:(NSError **)error {
    NSMutableArray *res = [NSMutableArray array];
    for (NSString *uri in uris) [res addObject:@{@"uri": uri}];
    return res;
}

- (nullable NSDictionary *)getModerationRepo:(NSString *)did
                                        error:(NSError **)error {
    return @{@"did": did, @"status": @"active"};
}

- (nullable NSArray<NSDictionary *> *)getModerationRepos:(NSArray<NSString *> *)dids
                                                    error:(NSError **)error {
    NSMutableArray *res = [NSMutableArray array];
    for (NSString *did in dids) [res addObject:@{@"did": did}];
    return res;
}

- (nullable NSDictionary *)searchModerationRepos:(NSDictionary *)filters
                                           limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error {
    return @{@"repos": @[]};
}

#pragma mark - Subject Status

- (nullable NSDictionary *)getSubjectStatus:(NSString *)subject
                                       error:(NSError **)error {
    return @{@"subject": @{@"did": subject}, @"labels": @[]};
}

- (nullable NSArray<NSDictionary *> *)getSubjectStatuses:(NSArray<NSString *> *)subjects
                                                    error:(NSError **)error {
    NSMutableArray *res = [NSMutableArray array];
    for (NSString *s in subjects) [res addObject:@{@"subject": @{@"did": s}}];
    return res;
}

#pragma mark - Team Management

- (nullable NSString *)addTeamMember:(NSDictionary *)member
                           createdBy:(NSString *)adminDid
                               error:(NSError **)error {
    NSString *did = member[@"did"];
    NSString *role = member[@"role"] ?: @"moderator";
    if (!did) return nil;

    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *sql = @"INSERT OR REPLACE INTO moderation_team (did, role, joined_at) VALUES (?, ?, ?)";
    
    if (![(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[did, role, now] error:error]) {
        return nil;
    }
    return did;
}

- (BOOL)updateTeamMember:(NSString *)memberId
               newRole:(NSString *)role
               updatedBy:(NSString *)adminDid
                   error:(NSError **)error {
    NSString *sql = @"UPDATE moderation_team SET role = ? WHERE did = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[role, memberId] error:error];
}

- (BOOL)removeTeamMember:(NSString *)memberId
               removedBy:(NSString *)adminDid
                   error:(NSError **)error {
    NSString *sql = @"DELETE FROM moderation_team WHERE did = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[memberId] error:error];
}

- (nullable NSArray<NSDictionary *> *)listTeamMembers:(NSError **)error {
    NSString *sql = @"SELECT * FROM moderation_team ORDER BY joined_at DESC";
    return [(PDSDatabase *)self.database executeParameterizedQuery:sql params:@[] error:error];
}

#pragma mark - Set Management

- (nullable NSString *)createSet:(NSDictionary *)set
                       createdBy:(NSString *)adminDid
                           error:(NSError **)error {
    NSString *id = [[NSUUID UUID] UUIDString];
    NSString *name = set[@"name"];
    NSString *desc = set[@"description"] ?: @"";
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    NSString *sql = @"INSERT INTO moderation_sets (id, name, description, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)";
    if (![(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[id, name, desc, adminDid, now, now] error:error]) {
        return nil;
    }
    return id;
}

- (BOOL)updateSet:(NSString *)setId
          newName:(nullable NSString *)name
        newValues:(nullable NSArray *)values
        updatedBy:(NSString *)adminDid
            error:(NSError **)error {
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    if (name) {
        NSString *sql = @"UPDATE moderation_sets SET name = ?, updated_at = ? WHERE id = ?";
        if (![(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[name, now, setId] error:error]) return NO;
    }
    if (values) {
        // Clear and refill members
        NSString *del = @"DELETE FROM moderation_set_members WHERE set_id = ?";
        [(PDSDatabase *)self.database executeParameterizedUpdate:del params:@[setId] error:nil];
        for (NSString *did in values) {
            [self addSetValues:setId values:@[did] addedBy:adminDid error:nil];
        }
    }
    return YES;
}

- (BOOL)deleteSet:(NSString *)setId
        deletedBy:(NSString *)adminDid
            error:(NSError **)error {
    NSString *sql = @"DELETE FROM moderation_sets WHERE id = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[setId] error:error];
}

- (nullable NSDictionary *)getSet:(NSString *)setId
                              error:(NSError **)error {
    NSString *sql = @"SELECT * FROM moderation_sets WHERE id = ?";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:sql params:@[setId] error:error];
    if (!rows || rows.count == 0) return nil;
    
    NSMutableDictionary *set = [rows[0] mutableCopy];
    NSString *mSql = @"SELECT did FROM moderation_set_members WHERE set_id = ?";
    NSArray *mRows = [(PDSDatabase *)self.database executeParameterizedQuery:mSql params:@[setId] error:nil];
    NSMutableArray *values = [NSMutableArray array];
    for (NSDictionary *r in mRows) [values addObject:r[@"did"]];
    set[@"values"] = values;
    return set;
}

- (nullable NSArray<NSDictionary *> *)listSets:(NSError **)error {
    NSString *sql = @"SELECT s.*, (SELECT COUNT(*) FROM moderation_set_members WHERE set_id = s.id) as memberCount "
                   @"FROM moderation_sets s ORDER BY updated_at DESC";
    return [(PDSDatabase *)self.database executeParameterizedQuery:sql params:@[] error:error];
}

- (BOOL)addSetValues:(NSString *)setId
               values:(NSArray *)values
             addedBy:(NSString *)adminDid
               error:(NSError **)error {
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    for (NSString *did in values) {
        NSString *sql = @"INSERT OR IGNORE INTO moderation_set_members (set_id, did, added_at) VALUES (?, ?, ?)";
        [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[setId, did, now] error:nil];
    }
    return YES;
}

#pragma mark - Communication Templates

- (nullable NSString *)createCommunicationTemplate:(NSDictionary *)template
                                         createdBy:(NSString *)adminDid
                                             error:(NSError **)error {
    NSString *id = [[NSUUID UUID] UUIDString];
    NSString *name = template[@"name"];
    NSString *text = template[@"text"];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    NSString *sql = @"INSERT INTO moderation_templates (id, name, text, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)";
    if (![(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[id, name, text, adminDid, now, now] error:error]) {
        return nil;
    }
    return id;
}

- (BOOL)updateCommunicationTemplate:(NSString *)templateId
                           newName:(nullable NSString *)name
                          newText:(nullable NSString *)text
                        updatedBy:(NSString *)adminDid
                              error:(NSError **)error {
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSMutableArray *updates = [NSMutableArray array];
    NSMutableArray *params = [NSMutableArray array];
    if (name) { [updates addObject:@"name = ?"]; [params addObject:name]; }
    if (text) { [updates addObject:@"text = ?"]; [params addObject:text]; }
    if (updates.count == 0) return YES;
    
    [updates addObject:@"updated_at = ?"]; [params addObject:now];
    [params addObject:templateId];
    
    NSString *sql = [NSString stringWithFormat:@"UPDATE moderation_templates SET %@ WHERE id = ?", [updates componentsJoinedByString:@", "]];
    return [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)deleteCommunicationTemplate:(NSString *)templateId
                          deletedBy:(NSString *)adminDid
                              error:(NSError **)error {
    NSString *sql = @"DELETE FROM moderation_templates WHERE id = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[templateId] error:error];
}

- (nullable NSArray<NSDictionary *> *)listCommunicationTemplates:(NSError **)error {
    NSString *sql = @"SELECT * FROM moderation_templates ORDER BY updated_at DESC";
    return [(PDSDatabase *)self.database executeParameterizedQuery:sql params:@[] error:error];
}

#pragma mark - Verification

- (nullable NSString *)grantVerification:(NSString *)did
                               grantedBy:(NSString *)adminDid
                                   error:(NSError **)error {
    return [[NSUUID UUID] UUIDString];
}

- (BOOL)revokeVerification:(NSString *)did
                revokedBy:(NSString *)adminDid
                    error:(NSError **)error {
    return YES;
}

- (nullable NSArray<NSString *> *)listVerifications:(NSError **)error {
    return @[];
}

#pragma mark - Statistics & Analytics

- (nullable NSDictionary *)getReporterStats:(NSString *)reporterDid
                                      error:(NSError **)error {
    return @{@"did": reporterDid ?: @"", @"reportCount": @0};
}

- (nullable NSDictionary *)getAccountTimeline:(NSString *)did
                                        limit:(NSInteger)limit
                                       cursor:(nullable NSString *)cursor
                                        error:(NSError **)error {
    return @{@"events": @[]};
}

#pragma mark - Scheduled Actions

- (nullable NSString *)scheduleAction:(NSDictionary *)action
                             createdBy:(NSString *)adminDid
                                 error:(NSError **)error {
    return [[NSUUID UUID] UUIDString];
}

- (nullable NSArray<NSDictionary *> *)listScheduledActions:(NSDictionary *)filters
                                                      error:(NSError **)error {
    return @[];
}

- (BOOL)cancelScheduledAction:(NSString *)actionId
                    cancelledBy:(NSString *)adminDid
                          error:(NSError **)error {
    return YES;
}

#pragma mark - Safelinks

- (nullable NSString *)createSafelink:(NSDictionary *)safelink
                             createdBy:(NSString *)adminDid
                                 error:(NSError **)error {
    return [[NSUUID UUID] UUIDString];
}

- (BOOL)updateSafelink:(NSString *)safelinkId
                newUrl:(nullable NSString *)url
             newAction:(nullable NSString *)action
           updatedBy:(NSString *)adminDid
                error:(NSError **)error {
    return YES;
}

- (BOOL)deleteSafelink:(NSString *)safelinkId
             deletedBy:(NSString *)adminDid
                 error:(NSError **)error {
    return YES;
}

- (nullable NSDictionary *)getSafelink:(NSString *)safelinkId
                                   error:(NSError **)error {
    return nil;
}

- (nullable NSArray<NSDictionary *> *)listSafelinks:(NSError **)error {
    return @[];
}

#pragma mark - Signatures

- (nullable NSDictionary *)getSignature:(NSString *)signatureId
                                   error:(NSError **)error {
    return @{@"id": signatureId, @"type": @"coordinated_behavior"};
}

- (nullable NSArray<NSDictionary *> *)listSignatures:(NSError **)error {
    return @[];
}

- (BOOL)reportSignatureMatch:(NSString *)signatureId
                    matchDid:(NSString *)did
                 reportedBy:(NSString *)adminDid
                       error:(NSError **)error {
    return YES;
}

#pragma mark - Settings

- (nullable NSDictionary *)getServerConfig:(NSError **)error {
    return @{@"serverName": @"Ozone", @"serverVersion": @"1.0.0"};
}

- (BOOL)updateServerSettings:(NSDictionary *)settings
                   updatedBy:(NSString *)adminDid
                       error:(NSError **)error {
    return YES;
}

#pragma mark - Hosting History

- (nullable NSArray<NSDictionary *> *)getAccountHostingHistory:(NSString *)did
                                                         limit:(NSInteger)limit
                                                        cursor:(nullable NSString *)cursor
                                                         error:(NSError **)error {
    return @[];
}

@end
