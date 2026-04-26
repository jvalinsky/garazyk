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

- (BOOL)deleteSetValues:(NSString *)setId
                values:(NSArray *)values
             deletedBy:(NSString *)adminDid
                 error:(NSError **)error {
    for (NSString *did in values) {
        NSString *sql = @"DELETE FROM moderation_set_members WHERE set_id = ? AND did = ?";
        [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[setId, did] error:nil];
    }
    return YES;
}

- (nullable NSDictionary *)getSetValues:(NSString *)setId
                                  limit:(NSInteger)limit
                                 cursor:(nullable NSString *)cursor
                                  error:(NSError **)error {
    NSMutableArray *params = [NSMutableArray arrayWithObject:setId];
    NSString *sql = @"SELECT did, added_at FROM moderation_set_members WHERE set_id = ?";
    
    if (cursor && cursor.length > 0) {
        sql = [sql stringByAppendingString:@" AND did > ? ORDER BY did LIMIT ?"];
        [params addObject:cursor];
        [params addObject:@(limit)];
    } else {
        sql = [sql stringByAppendingString:@" ORDER BY did LIMIT ?"];
        [params addObject:@(limit)];
    }
    
    NSArray *rows = [self.database executeParameterizedQuery:sql params:params error:error];
    if (!rows) return nil;
    
    NSMutableArray *values = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        [values addObject:@{
            @"did": row[@"did"] ?: @"",
            @"addedAt": row[@"added_at"] ?: @""
        }];
    }
    
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:values forKey:@"values"];
    if (rows.count >= (NSUInteger)limit) {
        result[@"cursor"] = [rows.lastObject[@"did"] stringValue] ?: @"";
    }
    return [result copy];
}

- (nullable NSDictionary *)querySets:(NSInteger)limit
                              cursor:(nullable NSString *)cursor
                          namePrefix:(nullable NSString *)namePrefix
                              error:(NSError **)error {
    NSMutableArray *params = [NSMutableArray array];
    NSString *sql = @"SELECT id, name, created_by, created_at FROM moderation_sets";
    
    NSMutableArray *conditions = [NSMutableArray array];
    if (namePrefix && namePrefix.length > 0) {
        [conditions addObject:@"name LIKE ?"];
        [params addObject:[NSString stringWithFormat:@"%@%%", namePrefix]];
    }
    if (cursor && cursor.length > 0) {
        [conditions addObject:@"id > ?"];
        [params addObject:cursor];
    }
    
    if (conditions.count > 0) {
        sql = [sql stringByAppendingString:[NSString stringWithFormat:@" WHERE %@",
            [conditions componentsJoinedByString:@" AND "]]];
    }
    
    sql = [sql stringByAppendingString:@" ORDER BY id LIMIT ?"];
    [params addObject:@(limit)];
    
    NSArray *rows = [self.database executeParameterizedQuery:sql params:params error:error];
    if (!rows) return nil;
    
    NSMutableArray *sets = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        [sets addObject:@{
            @"id": row[@"id"] ?: @"",
            @"name": row[@"name"] ?: @"",
            @"createdBy": row[@"created_by"] ?: @"",
            @"createdAt": row[@"created_at"] ?: @""
        }];
    }
    
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:sets forKey:@"sets"];
    if (rows.count >= (NSUInteger)limit) {
        result[@"cursor"] = [rows.lastObject[@"id"] stringValue] ?: @"";
    }
    return [result copy];
}

#pragma mark - Communication Templates

- (nullable NSString *)createCommunicationTemplate:(NSDictionary *)templateDict
                                         createdBy:(NSString *)adminDid
                                             error:(NSError **)error {
    NSString *id = [[NSUUID UUID] UUIDString];
    NSString *name = templateDict[@"name"];
    NSString *text = templateDict[@"text"];
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

- (nullable NSDictionary *)scheduleAction:(NSDictionary *)payload
                             createdBy:(NSString *)adminDid
                                 error:(NSError **)error {
    NSDictionary *action = payload[@"action"];
    NSArray *subjects = payload[@"subjects"];
    NSDictionary *scheduling = payload[@"scheduling"];
    NSString *modTool = payload[@"modTool"];

    if (!action || !subjects || !scheduling) {
        if (error) *error = [NSError errorWithDomain:@"ModerationService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"action, subjects, and scheduling are required"}];
        return nil;
    }

    NSString *actionType = action[@"$type"] ?: @"takedown";
    NSString *comment = action[@"comment"] ?: @"";
    NSNumber *duration = action[@"durationInHours"] ?: @0;
    NSNumber *ackSubjects = action[@"acknowledgeAccountSubjects"] ?: @0;
    NSArray *policies = action[@"policies"] ?: @[];
    NSString *severity = action[@"severityLevel"] ?: @"";
    NSNumber *strikeCount = action[@"strikeCount"] ?: @0;
    NSString *strikeExpiresAt = action[@"strikeExpiresAt"] ?: @"";
    NSString *emailContent = action[@"emailContent"] ?: @"";
    NSString *emailSubject = action[@"emailSubject"] ?: @"";

    NSString *executeAt = scheduling[@"executeAt"] ?: @"";
    NSString *executeAfter = scheduling[@"executeAfter"] ?: @"";
    NSString *executeUntil = scheduling[@"executeUntil"] ?: @"";

    NSData *policiesData = [NSJSONSerialization dataWithJSONObject:policies options:0 error:nil];
    NSString *policiesJson = [[NSString alloc] initWithData:policiesData encoding:NSUTF8StringEncoding];

    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    NSTimeInterval executeAtInterval = executeAt.length > 0 ? [[formatter dateFromString:executeAt] timeIntervalSince1970] : 0;
    NSTimeInterval executeAfterInterval = executeAfter.length > 0 ? [[formatter dateFromString:executeAfter] timeIntervalSince1970] : 0;
    NSTimeInterval executeUntilInterval = executeUntil.length > 0 ? [[formatter dateFromString:executeUntil] timeIntervalSince1970] : 0;
    NSTimeInterval strikeExpiresInterval = strikeExpiresAt.length > 0 ? [[formatter dateFromString:strikeExpiresAt] timeIntervalSince1970] : 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    NSMutableArray *succeeded = [NSMutableArray array];
    NSMutableArray *failed = [NSMutableArray array];

    for (NSString *subjectDid in subjects) {
        NSString *actionId = [[NSUUID UUID] UUIDString];

        NSString *sql = @"INSERT INTO moderation_scheduled_actions (id, subject_did, action_type, comment, duration_in_hours, acknowledge_account_subjects, policies_json, severity_level, strike_count, strike_expires_at, email_content, email_subject, execute_at, execute_after, execute_until, created_by, created_at, status, mod_tool) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

        BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[actionId, subjectDid, actionType, comment, duration, ackSubjects, policiesJson, severity, strikeCount, @(strikeExpiresInterval), emailContent, emailSubject, @(executeAtInterval), @(executeAfterInterval), @(executeUntilInterval), adminDid, @(now), @"pending", modTool ?: [NSNull null]] error:error];

        if (success) {
            [succeeded addObject:subjectDid];
        } else {
            [failed addObject:@{@"subject": subjectDid, @"error": @"Failed to save to database", @"errorCode": @"DatabaseError"}];
        }
    }

    return @{@"succeeded": succeeded, @"failed": failed};
}

- (nullable NSArray<NSDictionary *> *)listScheduledActions:(NSDictionary *)filters
                                                      error:(NSError **)error {
    NSString *sql = @"SELECT * FROM moderation_scheduled_actions WHERE status = 'pending' ORDER BY created_at DESC";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:sql params:@[] error:error];
    if (!rows) return nil;

    NSMutableArray *actions = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSMutableDictionary *action = [NSMutableDictionary dictionary];
        action[@"id"] = row[@"id"];
        action[@"subject"] = row[@"subject_did"];
        action[@"action"] = row[@"action_type"];
        action[@"comment"] = row[@"comment"];
        action[@"duration_in_hours"] = row[@"duration_in_hours"];
        action[@"status"] = row[@"status"];
        action[@"created_by"] = row[@"created_by"];
        action[@"created_at"] = @([row[@"created_at"] doubleValue]);
        action[@"execute_at"] = @([row[@"execute_at"] doubleValue]);
        
        [actions addObject:action];
    }
    return actions;
}

- (BOOL)cancelScheduledAction:(NSString *)actionId
                    cancelledBy:(NSString *)adminDid
                          error:(NSError **)error {
    NSString *sql = @"UPDATE moderation_scheduled_actions SET status = 'cancelled' WHERE id = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[actionId] error:error];
}

- (nullable NSDictionary *)cancelScheduledActions:(NSArray<NSString *> *)subjects
                                          comment:(nullable NSString *)comment
                                      cancelledBy:(NSString *)adminDid
                                            error:(NSError **)error {
    NSMutableArray *succeeded = [NSMutableArray array];
    NSMutableArray *failed = [NSMutableArray array];

    for (NSString *subjectDid in subjects) {
        NSString *sql = @"UPDATE moderation_scheduled_actions SET status = 'cancelled' WHERE subject_did = ? AND status = 'pending'";
        BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:@[subjectDid] error:nil];
        if (success) {
            [succeeded addObject:subjectDid];
        } else {
            [failed addObject:@{
                @"did": subjectDid,
                @"error": @"Failed to cancel scheduled actions",
                @"errorCode": @"DatabaseError"
            }];
        }
    }

    return @{@"succeeded": succeeded, @"failed": failed};
}

- (nullable NSArray<NSDictionary *> *)getSubjects:(NSArray<NSString *> *)subjects
                                            error:(NSError **)error {
    NSMutableArray *results = [NSMutableArray array];

    for (NSString *subject in subjects) {
        // Get moderation status for subject
        NSString *statusSql = @"SELECT * FROM moderation_subjects WHERE did = ?";
        NSArray *statusRows = [self.database executeParameterizedQuery:statusSql params:@[subject] error:nil];

        NSMutableDictionary *subjectView = [NSMutableDictionary dictionary];
        subjectView[@"did"] = subject;

        if (statusRows && statusRows.count > 0) {
            NSDictionary *row = statusRows.firstObject;
            subjectView[@"reviewState"] = row[@"review_state"] ?: @"none";
            subjectView[@"reviewedAt"] = row[@"reviewed_at"] ?: @"";
            subjectView[@"reviewerDid"] = row[@"reviewer_did"] ?: @"";
            subjectView[@"lastReviewedBy"] = row[@"reviewer_did"] ?: @"";
        } else {
            subjectView[@"reviewState"] = @"none";
        }

        [results addObject:subjectView];
    }

    return [results copy];
}

#pragma mark - Safelinks

- (nullable NSString *)createSafelink:(NSDictionary *)safelink
                             createdBy:(NSString *)adminDid
                                 error:(NSError **)error {
    NSString *url = safelink[@"url"] ?: @"";
    NSString *pattern = safelink[@"pattern"] ?: @"domain";
    NSString *action = safelink[@"action"] ?: @"block";
    NSString *reason = safelink[@"reason"] ?: @"none";
    NSString *comment = safelink[@"comment"] ?: @"";
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    if (url.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"ModerationService" code:1 userInfo:@{NSLocalizedDescriptionKey: @"URL required"}];
        return nil;
    }

    NSString *sql = [NSString stringWithFormat:
        @"INSERT INTO moderation_safelinks (url, pattern, action, reason, comment, created_by, created_at, updated_at) "
        @"VALUES (?, ?, ?, ?, ?, ?, ?, ?)"];

    BOOL success = [self.database executeParameterizedUpdate:sql
                                                       params:@[url, pattern, action, reason, comment, adminDid, @(now), @(now)]
                                                        error:error];

    if (success) {
        return [NSString stringWithFormat:@"%@:%@", url, pattern];
    }
    return nil;
}

- (BOOL)updateSafelink:(NSString *)safelinkId
                newUrl:(nullable NSString *)url
             newAction:(nullable NSString *)action
           updatedBy:(NSString *)adminDid
                error:(NSError **)error {
    if (!safelinkId || safelinkId.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"ModerationService" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Safelink ID required"}];
        return NO;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableString *sql = [NSMutableString stringWithString:@"UPDATE moderation_safelinks SET updated_at = ?"];
    NSMutableArray *params = [NSMutableArray arrayWithObject:@(now)];

    if (action && action.length > 0) {
        [sql appendString:@", action = ?"];
        [params addObject:action];
    }

    NSArray *parts = [safelinkId componentsSeparatedByString:@":"];
    if (parts.count == 2) {
        [sql appendFormat:@" WHERE url = ? AND pattern = ?"];
        [params addObject:parts[0]];
        [params addObject:parts[1]];
    }

    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)deleteSafelink:(NSString *)safelinkId
             deletedBy:(NSString *)adminDid
                 error:(NSError **)error {
    if (!safelinkId || safelinkId.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"ModerationService" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Safelink ID required"}];
        return NO;
    }

    NSArray *parts = [safelinkId componentsSeparatedByString:@":"];
    if (parts.count == 2) {
        NSString *sql = @"DELETE FROM moderation_safelinks WHERE url = ? AND pattern = ?";
        return [self.database executeParameterizedUpdate:sql params:@[parts[0], parts[1]] error:error];
    }

    if (error) *error = [NSError errorWithDomain:@"ModerationService" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid safelink ID format"}];
    return NO;
}

- (nullable NSDictionary *)getSafelink:(NSString *)safelinkId
                                   error:(NSError **)error {
    if (!safelinkId || safelinkId.length == 0) return nil;

    NSArray *parts = [safelinkId componentsSeparatedByString:@":"];
    if (parts.count != 2) return nil;

    NSString *sql = @"SELECT * FROM moderation_safelinks WHERE url = ? AND pattern = ?";
    NSArray<NSDictionary *> *results = [self.database executeParameterizedQuery:sql params:@[parts[0], parts[1]] error:error];
    return results.firstObject;
}

- (nullable NSArray<NSDictionary *> *)listSafelinks:(NSError **)error {
    NSString *sql = @"SELECT * FROM moderation_safelinks ORDER BY created_at DESC";
    return [self.database executeParameterizedQuery:sql params:@[] error:error];
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
