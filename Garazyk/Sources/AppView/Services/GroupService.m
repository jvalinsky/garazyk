#import "GroupService.h"
#import "Database/PDSDatabase.h"
#import "Core/NSURL+Extensions.h"
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
    BOOL success = [(PDSDatabase *)self.database executeUpdate:insertQuery
                                                   withParams:@[groupUri, creatorDid, name, description ?: @"",
                                                               privacy, joinability, now, now]
                                                        error:error];
    if (!success) return nil;

    // Add creator as admin
    NSString *memberQuery = @"INSERT INTO group_members (group_uri, member_did, role, status, joined_at) "
                           @"VALUES (?, ?, ?, ?, ?)";
    success = [(PDSDatabase *)self.database executeUpdate:memberQuery
                                              withParams:@[groupUri, creatorDid, @"admin", @"accepted", now]
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

    // Build dynamic update query
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

    return [(PDSDatabase *)self.database executeUpdate:updateQuery withParams:params error:error];
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
        BOOL success = [(PDSDatabase *)self.database executeUpdate:insertQuery
                                                       withParams:@[groupUri, memberDid, @"member", @"accepted",
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
        BOOL success = [(PDSDatabase *)self.database executeUpdate:deleteQuery
                                                       withParams:@[groupUri, memberDid]
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

    BOOL success = [(PDSDatabase *)self.database executeUpdate:insertQuery
                                                   withParams:@[linkId, groupUri, createdByDid, now,
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

    return [(PDSDatabase *)self.database executeUpdate:updateQuery withParams:params error:error];
}

- (BOOL)disableInviteLink:(NSString *)linkId
                    error:(NSError **)error {
    if (!linkId) {
        if (error) *error = [NSError errorWithDomain:@"GroupService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Link ID is required"}];
        return NO;
    }

    NSString *updateQuery = @"UPDATE group_invite_links SET enabled = 0 WHERE id = ?";
    return [(PDSDatabase *)self.database executeUpdate:updateQuery withParams:@[linkId] error:error];
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
    BOOL success = [(PDSDatabase *)self.database executeUpdate:insertQuery
                                                   withParams:@[groupUri, memberDid, @"member", @"accepted", now]
                                                        error:error];
    if (!success) return nil;

    // Increment uses
    NSString *updateQuery = @"UPDATE group_invite_links SET uses = uses + 1 WHERE id = ?";
    [(PDSDatabase *)self.database executeUpdate:updateQuery withParams:@[linkId] error:nil];

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

    BOOL success = [(PDSDatabase *)self.database executeUpdate:insertQuery
                                                   withParams:@[requestId, groupUri, requesterDid, @"pending", now]
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
    BOOL success = [(PDSDatabase *)self.database executeUpdate:insertQuery
                                                   withParams:@[groupUri, requesterDid, @"member", @"accepted",
                                                               approvingDid, now]
                                                        error:error];
    if (!success) return NO;

    // Update request status
    NSString *updateQuery = @"UPDATE group_join_requests SET status = 'approved', responded_at = ?, responded_by = ? WHERE id = ?";
    return [(PDSDatabase *)self.database executeUpdate:updateQuery
                                           withParams:@[now, approvingDid, requestId]
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
