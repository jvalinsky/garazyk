// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "GroupService.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"

@interface GroupService ()
@property (nonatomic, weak) id<PDSQueryDatabase> database;
@end

@implementation GroupService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

#pragma mark - Group CRUD

- (nullable NSDictionary *)createGroupWithName:(NSString *)name
                                   description:(nullable NSString *)description
                                      creator:(NSString *)creatorDid
                                      privacy:(NSString *)privacy
                                  joinability:(NSString *)joinability
                                        error:(NSError **)error {
    if (!name || name.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group name is required"}];
        return nil;
    }

    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *groupUri = [NSString stringWithFormat:@"at://%@/chat.bsky.group.definition/%@",
                         creatorDid, [[NSUUID UUID] UUIDString]];

    // Create group
    NSString *insertQuery = @"INSERT INTO groups (uri, creator_did, name, description, privacy, joinability, created_at, updated_at) "
                           @"VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:insertQuery
                                                   params:@[groupUri, creatorDid, name, description ?: @"",
                                                               privacy, joinability, now, now]
                                                        error:error];
    if (!success) return nil;

    // Add creator as admin
    NSString *memberQuery = @"INSERT INTO group_members (group_uri, member_did, role, status, joined_at) "
                           @"VALUES (?, ?, ?, ?, ?)";
    success = [(PDSDatabase *)self.database executeParameterizedUpdate:memberQuery
                                              params:@[groupUri, creatorDid, @"admin", @"accepted", now]
                                                   error:error];
    if (!success) return nil;

    return [self getGroupPublicInfo:groupUri error:error];
}

- (BOOL)editGroup:(NSString *)groupUri
         newName:(nullable NSString *)name
   newDescription:(nullable NSString *)description
       newPrivacy:(nullable NSString *)privacy
            error:(NSError **)error {
    if (!groupUri) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                              userInfo:@{NSLocalizedDescriptionKey: @"Group URI is required"}];
        return NO;
    }

    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    // Whitelist of allowed column names for dynamic update
    NSSet<NSString *> *allowedColumns = [NSSet setWithArray:@[@"name", @"description", @"privacy"]];
    NSMutableArray *updates = [NSMutableArray array];
    NSMutableArray *params = [NSMutableArray array];

    if (name) {
        [updates addObject:@"name = ?"];
        [params addObject:name];
    }
    if (description) {
        [updates addObject:@"description = ?"];
        [params addObject:description];
    }
    if (privacy) {
        // Validate privacy value against allowed values
        NSSet<NSString *> *allowedPrivacy = [NSSet setWithArray:@[@"public", @"private", @"restricted"]];
        if (![allowedPrivacy containsObject:privacy]) {
            if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid privacy value"}];
            return NO;
        }
        [updates addObject:@"privacy = ?"];
        [params addObject:privacy];
    }

    if (updates.count == 0) {
        return YES; // No updates to make
    }

    [updates addObject:@"updated_at = ?"];
    [params addObject:now];
    [params addObject:groupUri];

    NSString *updateQuery = [NSString stringWithFormat:@"UPDATE groups SET %@ WHERE uri = ?",
                            [updates componentsJoinedByString:@", "]];

    return [(PDSDatabase *)self.database executeParameterizedUpdate:updateQuery params:params error:error];
}

- (BOOL)deleteGroup:(NSString *)groupUri
              error:(NSError **)error {
    if (!groupUri) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI is required"}];
        return NO;
    }

    // Delete members, invite links, join requests, reactions, messages, and the group itself
    // In a real implementation we might use a transaction or foreign key cascading.
    // Assuming cascading is not enabled/guaranteed for all SQLite builds here, we do it manually.
    
    NSArray *queries = @[
        @"DELETE FROM group_message_reactions WHERE message_id IN (SELECT id FROM group_messages WHERE group_uri = ?)",
        @"DELETE FROM group_messages WHERE group_uri = ?",
        @"DELETE FROM group_join_requests WHERE group_uri = ?",
        @"DELETE FROM group_invite_links WHERE group_uri = ?",
        @"DELETE FROM group_members WHERE group_uri = ?",
        @"DELETE FROM groups WHERE uri = ?"
    ];

    for (NSString *query in queries) {
        if (![(PDSDatabase *)self.database executeParameterizedUpdate:query params:@[groupUri] error:error]) {
            return NO;
        }
    }

    return YES;
}

- (nullable NSDictionary *)getGroupPublicInfo:(NSString *)groupUri
                                       error:(NSError **)error {
    if (!groupUri) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI is required"}];
        return nil;
    }

    NSString *query = @"SELECT uri, creator_did, name, description, privacy, joinability, created_at, updated_at FROM groups WHERE uri = ?";
    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[groupUri]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    if (rows.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:404
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group not found"}];
        return nil;
    }

    NSDictionary *group = rows[0];

    // Get member count
    NSString *countQuery = @"SELECT COUNT(*) as count FROM group_members WHERE group_uri = ? AND status = 'accepted'";
    NSArray *countRows = [(PDSDatabase *)self.database executeParameterizedQuery:countQuery
                                                                           params:@[groupUri]
                                                                            error:nil];
    NSInteger memberCount = countRows.count > 0 ? [countRows[0][@"count"] integerValue] : 0;

    return @{
        @"uri": group[@"uri"],
        @"creator": group[@"creator_did"],
        @"name": group[@"name"],
        @"description": group[@"description"] ?: @"",
        @"privacy": group[@"privacy"],
        @"joinability": group[@"joinability"],
        @"memberCount": @(memberCount),
        @"createdAt": group[@"created_at"],
        @"updatedAt": group[@"updated_at"]
    };
}

#pragma mark - Member Management

- (BOOL)addMembersToGroup:(NSString *)groupUri
                members:(NSArray<NSString *> *)memberDids
              invitedBy:(NSString *)inviterDid
                 error:(NSError **)error {
    if (!groupUri || !memberDids || memberDids.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI and members are required"}];
        return NO;
    }

    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    // Add each member
    for (NSString *memberDid in memberDids) {
        NSString *insertQuery = @"INSERT OR IGNORE INTO group_members (group_uri, member_did, role, status, invited_by, joined_at) "
                               @"VALUES (?, ?, ?, ?, ?, ?)";
        BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:insertQuery
                                                       params:@[groupUri, memberDid, @"member", @"accepted",
                                                                   inviterDid, now]
                                                            error:error];
        if (!success) return NO;
    }

    return YES;
}

- (BOOL)removeMembersFromGroup:(NSString *)groupUri
                     members:(NSArray<NSString *> *)memberDids
                       error:(NSError **)error {
    if (!groupUri || !memberDids || memberDids.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI and members are required"}];
        return NO;
    }

    // Remove each member
    for (NSString *memberDid in memberDids) {
        NSString *deleteQuery = @"DELETE FROM group_members WHERE group_uri = ? AND member_did = ?";
        BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:deleteQuery
                                                       params:@[groupUri, memberDid]
                                                            error:error];
        if (!success) return NO;
    }

    return YES;
}

- (nullable NSArray<NSDictionary *> *)listGroupMembers:(NSString *)groupUri
                                                 limit:(NSInteger)limit
                                                cursor:(nullable NSString *)cursor
                                                 error:(NSError **)error {
    if (!groupUri) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI is required"}];
        return nil;
    }

    if (limit <= 0) limit = 50;
    if (limit > 100) limit = 100;

    NSString *query = @"SELECT member_did, role, status, invited_by, joined_at FROM group_members "
                     @"WHERE group_uri = ? AND status = 'accepted' ORDER BY joined_at ASC LIMIT ?";

    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[groupUri, @(limit + 1)]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    NSMutableArray *members = [NSMutableArray array];
    BOOL hasMore = rows.count > limit;

    NSInteger count = MIN((NSInteger)rows.count, limit);
    for (NSInteger i = 0; i < count; i++) {
        NSDictionary *row = rows[i];
        [members addObject:@{
            @"did": row[@"member_did"],
            @"role": row[@"role"],
            @"status": row[@"status"],
            @"joinedAt": row[@"joined_at"]
        }];
    }

    return members;
}

- (nullable NSArray<NSDictionary *> *)listAllGroupsWithLimit:(NSInteger)limit
                                                      cursor:(nullable NSString *)cursor
                                                       query:(nullable NSString *)query
                                                       error:(NSError **)error {
    if (limit <= 0) limit = 50;
    
    NSString *sql = @"SELECT uri, name, creator_did, created_at, updated_at FROM groups";
    NSMutableArray *params = [NSMutableArray array];
    
    if (query || cursor) {
        sql = [sql stringByAppendingString:@" WHERE"];
        BOOL needsAnd = NO;
        if (query) {
            sql = [sql stringByAppendingString:@" (name LIKE ? OR uri LIKE ? OR creator_did LIKE ?)"];
            NSString *likePattern = [NSString stringWithFormat:@"%%%@%%", query];
            [params addObject:likePattern];
            [params addObject:likePattern];
            [params addObject:likePattern];
            needsAnd = YES;
        }
        if (cursor) {
            if (needsAnd) sql = [sql stringByAppendingString:@" AND"];
            sql = [sql stringByAppendingString:@" uri < ?"];
            [params addObject:cursor];
        }
    }
    
    sql = [sql stringByAppendingString:@" ORDER BY updated_at DESC LIMIT ?"];
    [params addObject:@(limit)];

    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:sql
                                                                      params:params
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    NSMutableArray *groups = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSDictionary *groupInfo = [self getGroupPublicInfo:row[@"uri"] error:nil];
        if (groupInfo) [groups addObject:groupInfo];
    }

    return groups;
}

#pragma mark - Invite Links

- (nullable NSString *)createInviteLinkForGroup:(NSString *)groupUri
                                      createdBy:(NSString *)createdByDid
                                       expiresAt:(nullable NSString *)expiresAt
                                        maxUses:(nullable NSNumber *)maxUses
                                          error:(NSError **)error {
    if (!groupUri) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI is required"}];
        return nil;
    }

    NSString *linkId = [[NSUUID UUID] UUIDString];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    NSString *insertQuery = @"INSERT INTO group_invite_links (id, group_uri, created_by, created_at, expires_at, max_uses, uses, enabled) "
                           @"VALUES (?, ?, ?, ?, ?, ?, ?, ?)";

    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:insertQuery
                                                   params:@[linkId, groupUri, createdByDid, now,
                                                               expiresAt ?: @"", maxUses ?: @0, @0, @1]
                                                        error:error];
    if (!success) return nil;

    return linkId;
}

- (BOOL)editInviteLink:(NSString *)linkId
              enabled:(NSNumber *)enabled
             expiresAt:(nullable NSString *)expiresAt
              maxUses:(nullable NSNumber *)maxUses
                error:(NSError **)error {
    if (!linkId) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Link ID is required"}];
        return NO;
    }

    NSMutableArray *updates = [NSMutableArray array];
    NSMutableArray *params = [NSMutableArray array];

    if (enabled) {
        [updates addObject:@"enabled = ?"];
        [params addObject:enabled];
    }
    if (expiresAt) {
        [updates addObject:@"expires_at = ?"];
        [params addObject:expiresAt];
    }
    if (maxUses) {
        [updates addObject:@"max_uses = ?"];
        [params addObject:maxUses];
    }

    if (updates.count == 0) {
        return YES;
    }

    [params addObject:linkId];

    NSString *updateQuery = [NSString stringWithFormat:@"UPDATE group_invite_links SET %@ WHERE id = ?",
                            [updates componentsJoinedByString:@", "]];

    return [(PDSDatabase *)self.database executeParameterizedUpdate:updateQuery params:params error:error];
}

- (BOOL)disableInviteLink:(NSString *)linkId
                    error:(NSError **)error {
    if (!linkId) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Link ID is required"}];
        return NO;
    }

    NSString *updateQuery = @"UPDATE group_invite_links SET enabled = 0 WHERE id = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:updateQuery params:@[linkId] error:error];
}

- (nullable NSArray<NSDictionary *> *)listAllInviteLinksWithLimit:(NSInteger)limit
                                                           cursor:(nullable NSString *)cursor
                                                            query:(nullable NSString *)query
                                                            error:(NSError **)error {
    if (limit <= 0) limit = 50;
    
    NSString *sql = @"SELECT id, group_uri, created_by, created_at, expires_at, max_uses, uses, enabled FROM group_invite_links";
    NSMutableArray *params = [NSMutableArray array];
    
    if (query || cursor) {
        sql = [sql stringByAppendingString:@" WHERE"];
        BOOL needsAnd = NO;
        if (query) {
            sql = [sql stringByAppendingString:@" (id LIKE ? OR group_uri LIKE ? OR created_by LIKE ?)"];
            NSString *likePattern = [NSString stringWithFormat:@"%%%@%%", query];
            [params addObject:likePattern];
            [params addObject:likePattern];
            [params addObject:likePattern];
            needsAnd = YES;
        }
        if (cursor) {
            if (needsAnd) sql = [sql stringByAppendingString:@" AND"];
            sql = [sql stringByAppendingString:@" id < ?"];
            [params addObject:cursor];
        }
    }
    
    sql = [sql stringByAppendingString:@" ORDER BY created_at DESC LIMIT ?"];
    [params addObject:@(limit)];

    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:sql
                                                                      params:params
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    return rows;
}

- (nullable NSDictionary *)validateAndUseInviteLink:(NSString *)linkId
                                         memberDid:(NSString *)memberDid
                                            error:(NSError **)error {
    if (!linkId || !memberDid) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Link ID and member DID are required"}];
        return nil;
    }

    // Get link and validate
    NSString *query = @"SELECT id, group_uri, enabled, expires_at, max_uses, uses FROM group_invite_links WHERE id = ?";
    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[linkId]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    if (rows.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:404
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invite link not found"}];
        return nil;
    }

    NSDictionary *link = rows[0];

    // Check if enabled
    if (![link[@"enabled"] boolValue]) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:403
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invite link is disabled"}];
        return nil;
    }

    // Check expiry
    NSString *expiresAt = link[@"expires_at"];
    if (expiresAt && expiresAt.length > 0) {
        NSTimeInterval expiryTime = [expiresAt doubleValue];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (now > expiryTime) {
            if (error) *error = [NSError errorWithDomain:@"GroupService" code:403
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Invite link has expired"}];
            return nil;
        }
    }

    // Check max uses
    NSInteger maxUses = [link[@"max_uses"] integerValue];
    NSInteger currentUses = [link[@"uses"] integerValue];
    if (maxUses > 0 && currentUses >= maxUses) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:403
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invite link has reached max uses"}];
        return nil;
    }

    // Add member to group
    NSString *groupUri = link[@"group_uri"];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    NSString *insertQuery = @"INSERT OR IGNORE INTO group_members (group_uri, member_did, role, status, joined_at) "
                           @"VALUES (?, ?, ?, ?, ?)";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:insertQuery
                                                   params:@[groupUri, memberDid, @"member", @"accepted", now]
                                                        error:error];
    if (!success) return nil;

    // Increment uses
    NSString *updateQuery = @"UPDATE group_invite_links SET uses = uses + 1 WHERE id = ?";
    [(PDSDatabase *)self.database executeParameterizedUpdate:updateQuery params:@[linkId] error:nil];

    return @{@"groupUri": groupUri, @"status": @"success"};
}

#pragma mark - Join Requests

- (nullable NSString *)requestJoinGroup:(NSString *)groupUri
                            requesterDid:(NSString *)requesterDid
                                 error:(NSError **)error {
    if (!groupUri || !requesterDid) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI and requester DID are required"}];
        return nil;
    }

    NSString *requestId = [[NSUUID UUID] UUIDString];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    NSString *insertQuery = @"INSERT OR IGNORE INTO group_join_requests (id, group_uri, requester_did, status, requested_at) "
                           @"VALUES (?, ?, ?, ?, ?)";

    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:insertQuery
                                                   params:@[requestId, groupUri, requesterDid, @"pending", now]
                                                        error:error];
    if (!success) return nil;

    return requestId;
}

- (BOOL)approveJoinRequest:(NSString *)requestId
             approvingDid:(NSString *)approvingDid
                   error:(NSError **)error {
    if (!requestId) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Request ID is required"}];
        return NO;
    }

    // Get join request
    NSString *query = @"SELECT group_uri, requester_did FROM group_join_requests WHERE id = ?";
    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[requestId]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return NO;
    }

    if (rows.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:404
                                             userInfo:@{NSLocalizedDescriptionKey: @"Join request not found"}];
        return NO;
    }

    NSDictionary *request = rows[0];
    NSString *groupUri = request[@"group_uri"];
    NSString *requesterDid = request[@"requester_did"];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    // Add member to group
    NSString *insertQuery = @"INSERT OR IGNORE INTO group_members (group_uri, member_did, role, status, invited_by, joined_at) "
                           @"VALUES (?, ?, ?, ?, ?, ?)";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:insertQuery
                                                   params:@[groupUri, requesterDid, @"member", @"accepted",
                                                               approvingDid, now]
                                                        error:error];
    if (!success) return NO;

    // Update request status
    NSString *updateQuery = @"UPDATE group_join_requests SET status = 'approved', responded_at = ?, responded_by = ? WHERE id = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:updateQuery
                                           params:@[now, approvingDid, requestId]
                                                error:error];
}

- (BOOL)rejectJoinRequest:(NSString *)requestId
            rejectingDid:(NSString *)rejectingDid
                  error:(NSError **)error {
    if (!requestId) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Request ID is required"}];
        return NO;
    }

    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    NSString *updateQuery = @"UPDATE group_join_requests SET status = 'rejected', responded_at = ?, responded_by = ? WHERE id = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:updateQuery
                                           params:@[now, rejectingDid, requestId]
                                                error:error];
}

- (nullable NSArray<NSDictionary *> *)listJoinRequestsForGroup:(NSString *)groupUri
                                                         error:(NSError **)error {
    if (!groupUri) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI is required"}];
        return nil;
    }

    NSString *query = @"SELECT id, requester_did, status, requested_at, responded_at FROM group_join_requests "
                     @"WHERE group_uri = ? AND status = 'pending' ORDER BY requested_at ASC";

    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[groupUri]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    NSMutableArray *requests = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        [requests addObject:@{
            @"id": row[@"id"],
            @"requesterDid": row[@"requester_did"],
            @"status": row[@"status"],
            @"requestedAt": row[@"requested_at"]
        }];
    }

    return requests;
}

- (BOOL)leaveGroup:(NSString *)groupUri
         memberDid:(NSString *)memberDid
             error:(NSError **)error {
    if (!groupUri || !memberDid) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI and member DID are required"}];
        return NO;
    }

    // Prevent creator from leaving (would orphan the group)
    NSString *creatorQuery = @"SELECT creator_did FROM groups WHERE uri = ?";
    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:creatorQuery
                                                                      params:@[groupUri]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return NO;
    }

    if (rows.count > 0 && [rows[0][@"creator_did"] isEqualToString:memberDid]) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:403
                                             userInfo:@{NSLocalizedDescriptionKey: @"Creator cannot leave group"}];
        return NO;
    }

    NSString *deleteQuery = @"DELETE FROM group_members WHERE group_uri = ? AND member_did = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:deleteQuery
                                           params:@[groupUri, memberDid]
                                                error:error];
}

#pragma mark - Group Messaging

- (nullable NSString *)sendMessageToGroup:(NSString *)groupUri
                                senderDid:(NSString *)senderDid
                                    text:(NSString *)text
                                   embed:(nullable NSString *)embed
                                   error:(NSError **)error {
    if (!groupUri || !senderDid || !text || text.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI, sender DID, and text are required"}];
        return nil;
    }

    // Verify sender is a member
    BOOL isMember = [self isUserMember:senderDid inGroup:groupUri error:error];
    if (!isMember) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:403
                                             userInfo:@{NSLocalizedDescriptionKey: @"User is not a member of this group"}];
        return nil;
    }

    NSString *messageId = [NSString stringWithFormat:@"msg/%@", [[NSUUID UUID] UUIDString]];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    NSString *insertQuery = @"INSERT INTO group_messages (id, group_uri, sender_did, text, embed_json, created_at) "
                           @"VALUES (?, ?, ?, ?, ?, ?)";

    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:insertQuery
                                                   params:@[messageId, groupUri, senderDid, text,
                                                               embed ?: @"", now]
                                                        error:error];
    if (!success) return nil;

    return messageId;
}

- (nullable NSArray<NSDictionary *> *)getMessagesForGroup:(NSString *)groupUri
                                                    limit:(NSInteger)limit
                                                  cursor:(nullable NSString *)cursor
                                                   error:(NSError **)error {
    if (!groupUri) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Group URI is required"}];
        return nil;
    }

    if (limit <= 0) limit = 50;
    if (limit > 100) limit = 100;

    NSString *query = @"SELECT id, sender_did, text, embed_json, created_at FROM group_messages "
                     @"WHERE group_uri = ? ORDER BY created_at DESC LIMIT ?";

    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[groupUri, @(limit + 1)]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    NSMutableArray *messages = [NSMutableArray array];
    NSInteger count = MIN((NSInteger)rows.count, limit);
    for (NSInteger i = 0; i < count; i++) {
        NSDictionary *row = rows[i];
        [messages addObject:@{
            @"id": row[@"id"],
            @"senderDid": row[@"sender_did"],
            @"text": row[@"text"],
            @"embed": row[@"embed_json"] ?: @"",
            @"createdAt": row[@"created_at"]
        }];
    }

    return messages;
}

- (BOOL)addReactionToGroupMessage:(NSString *)messageId
                       actorDid:(NSString *)actorDid
                         emoji:(NSString *)emoji
                         error:(NSError **)error {
    if (!messageId || !actorDid || !emoji) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Message ID, actor DID, and emoji are required"}];
        return NO;
    }

    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    NSString *insertQuery = @"INSERT OR REPLACE INTO group_message_reactions (message_id, actor_did, emoji, created_at) "
                           @"VALUES (?, ?, ?, ?)";

    return [(PDSDatabase *)self.database executeParameterizedUpdate:insertQuery
                                           params:@[messageId, actorDid, emoji, now]
                                                error:error];
}

- (BOOL)removeReactionFromGroupMessage:(NSString *)messageId
                            actorDid:(NSString *)actorDid
                              emoji:(NSString *)emoji
                              error:(NSError **)error {
    if (!messageId || !actorDid || !emoji) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Message ID, actor DID, and emoji are required"}];
        return NO;
    }

    NSString *deleteQuery = @"DELETE FROM group_message_reactions WHERE message_id = ? AND actor_did = ? AND emoji = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:deleteQuery
                                           params:@[messageId, actorDid, emoji]
                                                error:error];
}

- (BOOL)deleteGroupMessageForSelf:(NSString *)messageId
                        memberDid:(NSString *)memberDid
                            error:(NSError **)error {
    if (!messageId || !memberDid) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Message ID and member DID are required"}];
        return NO;
    }

    // Get current deleted_for list
    NSString *query = @"SELECT deleted_for_json FROM group_messages WHERE id = ?";
    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[messageId]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return NO;
    }

    if (rows.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:404
                                             userInfo:@{NSLocalizedDescriptionKey: @"Message not found"}];
        return NO;
    }

    // Parse JSON and add member
    NSMutableArray *deletedFor = [NSMutableArray array];
    NSString *deletedForJson = rows[0][@"deleted_for_json"];
    if (deletedForJson && deletedForJson.length > 0) {
        NSError *parseError = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:[deletedForJson dataUsingEncoding:NSUTF8StringEncoding]
                                                    options:0 error:&parseError];
        if (parsed && [parsed isKindOfClass:[NSArray class]]) {
            [deletedFor addObjectsFromArray:(NSArray *)parsed];
        }
    }

    if (![deletedFor containsObject:memberDid]) {
        [deletedFor addObject:memberDid];
    }

    // Update with new JSON
    NSError *serializeError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:deletedFor options:0 error:&serializeError];
    NSString *newDeletedForJson = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    NSString *updateQuery = @"UPDATE group_messages SET deleted_for_json = ? WHERE id = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:updateQuery
                                           params:@[newDeletedForJson, messageId]
                                                error:error];
}

#pragma mark - Permission Checks

- (BOOL)isUserAdmin:(NSString *)userDid
           inGroup:(NSString *)groupUri
             error:(NSError **)error {
    if (!userDid || !groupUri) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"User DID and group URI are required"}];
        return NO;
    }

    NSString *query = @"SELECT role FROM group_members WHERE member_did = ? AND group_uri = ? AND status = 'accepted'";
    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[userDid, groupUri]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return NO;
    }

    if (rows.count == 0) return NO;

    NSString *role = rows[0][@"role"];
    return [role isEqualToString:@"admin"] || [role isEqualToString:@"creator"];
}

- (BOOL)isUserMember:(NSString *)userDid
            inGroup:(NSString *)groupUri
              error:(NSError **)error {
    if (!userDid || !groupUri) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"User DID and group URI are required"}];
        return NO;
    }

    NSString *query = @"SELECT 1 FROM group_members WHERE member_did = ? AND group_uri = ? AND status = 'accepted'";
    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[userDid, groupUri]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return NO;
    }

    return rows.count > 0;
}

@end
