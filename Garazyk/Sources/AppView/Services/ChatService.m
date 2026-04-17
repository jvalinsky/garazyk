#import "ChatService.h"
#import "Database/PDSDatabase.h"
#import "Core/NSURL+Extensions.h"
#import "Debug/PDSLogger.h"

@interface ChatService ()
@property (nonatomic, weak) id<PDSQueryDatabase> database;
@end

@implementation ChatService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

#pragma mark - Conversation Management

- (nullable NSDictionary *)createConversationWithMembers:(NSArray<NSString *> *)memberDids
                                                  error:(NSError **)error {
    if (memberDids.count < 2) {
        if (error) *error = [NSError errorWithDomain:@"ChatService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Conversation requires at least 2 members"}];
        return nil;
    }

    // Generate conversation ID (e.g., convo/abc123)
    NSString *convoId = [NSString stringWithFormat:@"convo/%@", [[NSUUID UUID] UUIDString]];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    // Create conversation
    NSString *insertQuery = @"INSERT INTO conversations (id, created_at, updated_at) VALUES (?, ?, ?)";
    BOOL success = [(PDSDatabase *)self.database executeUpdate:insertQuery
                                                    withParams:@[convoId, now, now]
                                                         error:error];
    if (!success) return nil;

    // Add members
    for (NSString *memberDid in memberDids) {
        NSString *memberQuery = @"INSERT INTO conversation_members (convo_id, member_did, status, joined_at) VALUES (?, ?, ?, ?)";
        success = [(PDSDatabase *)self.database executeUpdate:memberQuery
                                                   withParams:@[convoId, memberDid, @"pending", now]
                                                        error:error];
        if (!success) return nil;
    }

    return [self getConversationWithId:convoId error:error];
}

- (nullable NSDictionary *)getConversationForMembers:(NSArray<NSString *> *)memberDids
                                               error:(NSError **)error {
    if (memberDids.count < 2) {
        if (error) *error = [NSError errorWithDomain:@"ChatService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Need at least 2 members"}];
        return nil;
    }

    // Sort members for deterministic query
    NSArray *sortedMembers = [memberDids sortedArrayUsingSelector:@selector(compare:)];

    // Query conversations with exact member set
    NSString *query = @"SELECT DISTINCT cm1.convo_id FROM conversation_members cm1 "
                     @"WHERE cm1.member_did = ? AND cm1.convo_id IN ("
                     @"  SELECT convo_id FROM conversation_members "
                     @"  GROUP BY convo_id HAVING COUNT(DISTINCT member_did) = ?"
                     @") LIMIT 1";

    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[sortedMembers[0], @(sortedMembers.count)]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    if (rows.count > 0) {
        NSString *convoId = rows[0][@"convo_id"];
        return [self getConversationWithId:convoId error:error];
    }

    // Create new conversation if not found
    return [self createConversationWithMembers:memberDids error:error];
}

- (nullable NSDictionary *)getConversationWithId:(NSString *)convoId
                                           error:(NSError **)error {
    NSString *query = @"SELECT id, created_at, updated_at FROM conversations WHERE id = ?";
    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[convoId]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    if (rows.count == 0) return nil;

    NSDictionary *convoRow = rows[0];

    // Fetch members
    NSString *membersQuery = @"SELECT member_did, status, muted, last_read_id, joined_at FROM conversation_members WHERE convo_id = ?";
    NSArray *memberRows = [(PDSDatabase *)self.database executeParameterizedQuery:membersQuery
                                                                            params:@[convoId]
                                                                             error:nil] ?: @[];

    NSMutableArray *members = [NSMutableArray array];
    for (NSDictionary *memberRow in memberRows) {
        [members addObject:@{
            @"did": memberRow[@"member_did"],
            @"status": memberRow[@"status"],
            @"muted": memberRow[@"muted"],
            @"lastReadId": memberRow[@"last_read_id"] ?: [NSNull null],
            @"joinedAt": memberRow[@"joined_at"]
        }];
    }

    return @{
        @"id": convoRow[@"id"],
        @"createdAt": convoRow[@"created_at"],
        @"updatedAt": convoRow[@"updated_at"],
        @"members": members
    };
}

- (nullable NSArray<NSDictionary *> *)listConversationsForActor:(NSString *)actorDid
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                          error:(NSError **)error {
    NSString *query = @"SELECT DISTINCT c.id, c.created_at, c.updated_at "
                     @"FROM conversations c "
                     @"JOIN conversation_members cm ON c.id = cm.convo_id "
                     @"WHERE cm.member_did = ?";
    if (cursor) {
        query = [query stringByAppendingString:@" AND c.id < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY c.updated_at DESC LIMIT ?"];

    NSMutableArray *params = [NSMutableArray arrayWithObject:actorDid];
    if (cursor) [params addObject:cursor];
    [params addObject:@(limit + 1)];

    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:params
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    NSMutableArray *conversations = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        if (conversations.count >= (NSUInteger)limit) break;
        NSDictionary *convo = [self getConversationWithId:row[@"id"] error:nil];
        if (convo) [conversations addObject:convo];
    }

    return conversations;
}

- (BOOL)acceptConversation:(NSString *)convoId
                 memberDid:(NSString *)memberDid
                     error:(NSError **)error {
    NSString *query = @"UPDATE conversation_members SET status = ? WHERE convo_id = ? AND member_did = ?";
    return [(PDSDatabase *)self.database executeUpdate:query
                                            withParams:@[@"accepted", convoId, memberDid]
                                                 error:error];
}

- (BOOL)leaveConversation:(NSString *)convoId
                memberDid:(NSString *)memberDid
                   error:(NSError **)error {
    NSString *query = @"UPDATE conversation_members SET status = ? WHERE convo_id = ? AND member_did = ?";
    return [(PDSDatabase *)self.database executeUpdate:query
                                            withParams:@[@"left", convoId, memberDid]
                                                 error:error];
}

- (nullable NSArray<NSDictionary *> *)listConversationRequestsForActor:(NSString *)actorDid
                                                                 error:(NSError **)error {
    NSString *query = @"SELECT c.id, c.created_at FROM conversations c "
                     @"JOIN conversation_members cm ON c.id = cm.convo_id "
                     @"WHERE cm.member_did = ? AND cm.status = ? "
                     @"ORDER BY c.created_at DESC";

    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:@[actorDid, @"pending"]
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    NSMutableArray *requests = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSDictionary *convo = [self getConversationWithId:row[@"id"] error:nil];
        if (convo) [requests addObject:convo];
    }

    return requests;
}

#pragma mark - Message Management

- (nullable NSDictionary *)sendMessage:(NSString *)convoId
                            senderDid:(NSString *)senderDid
                                 text:(nullable NSString *)text
                            embedJson:(nullable NSString *)embedJson
                                error:(NSError **)error {
    NSString *messageId = [NSString stringWithFormat:@"msg/%@", [[NSUUID UUID] UUIDString]];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    NSString *query = @"INSERT INTO messages (id, convo_id, sender_did, text, embed_json, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    BOOL success = [(PDSDatabase *)self.database executeUpdate:query
                                                    withParams:@[messageId, convoId, senderDid, text ?: [NSNull null], embedJson ?: [NSNull null], now]
                                                         error:error];
    if (!success) return nil;

    // Update conversation updated_at
    NSString *updateQuery = @"UPDATE conversations SET updated_at = ? WHERE id = ?";
    [(PDSDatabase *)self.database executeUpdate:updateQuery withParams:@[now, convoId] error:nil];

    return @{
        @"id": messageId,
        @"convoId": convoId,
        @"senderDid": senderDid,
        @"text": text ?: [NSNull null],
        @"embedJson": embedJson ?: [NSNull null],
        @"createdAt": now
    };
}

- (nullable NSArray<NSDictionary *> *)getMessagesForConversation:(NSString *)convoId
                                                           limit:(NSInteger)limit
                                                          cursor:(nullable NSString *)cursor
                                                           error:(NSError **)error {
    NSString *query = @"SELECT id, sender_did, text, embed_json, created_at FROM messages WHERE convo_id = ?";
    if (cursor) {
        query = [query stringByAppendingString:@" AND id < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY created_at DESC LIMIT ?"];

    NSMutableArray *params = [NSMutableArray arrayWithObject:convoId];
    if (cursor) [params addObject:cursor];
    [params addObject:@(limit + 1)];

    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:params
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    NSMutableArray *messages = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        if (messages.count >= (NSUInteger)limit) break;
        [messages addObject:@{
            @"id": row[@"id"],
            @"convoId": convoId,
            @"senderDid": row[@"sender_did"],
            @"text": row[@"text"] ?: [NSNull null],
            @"embedJson": row[@"embed_json"] ?: [NSNull null],
            @"createdAt": row[@"created_at"]
        }];
    }

    return messages;
}

- (BOOL)deleteMessageForSelf:(NSString *)messageId
                   memberDid:(NSString *)memberDid
                       error:(NSError **)error {
    // Fetch current deletion list
    NSString *fetchQuery = @"SELECT deleted_for_json FROM messages WHERE id = ?";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:fetchQuery
                                                                      params:@[messageId]
                                                                       error:error];
    if (!rows || rows.count == 0) return NO;

    NSString *deletedForJson = rows[0][@"deleted_for_json"];
    NSMutableArray *deletedFor = [NSMutableArray array];
    if (deletedForJson) {
        NSData *jsonData = [deletedForJson dataUsingEncoding:NSUTF8StringEncoding];
        NSError *parseError = nil;
        NSArray *parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&parseError];
        if (parsed) deletedFor = [parsed mutableCopy];
    }

    if (![deletedFor containsObject:memberDid]) {
        [deletedFor addObject:memberDid];
    }

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:deletedFor options:0 error:&jsonError];
    NSString *newJson = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    NSString *updateQuery = @"UPDATE messages SET deleted_for_json = ? WHERE id = ?";
    return [(PDSDatabase *)self.database executeUpdate:updateQuery
                                            withParams:@[newJson, messageId]
                                                 error:error];
}

- (BOOL)updateLastReadMessage:(NSString *)convoId
                    memberDid:(NSString *)memberDid
                    messageId:(NSString *)messageId
                        error:(NSError **)error {
    NSString *query = @"UPDATE conversation_members SET last_read_id = ? WHERE convo_id = ? AND member_did = ?";
    return [(PDSDatabase *)self.database executeUpdate:query
                                            withParams:@[messageId, convoId, memberDid]
                                                 error:error];
}

#pragma mark - Reactions

- (BOOL)addReaction:(NSString *)messageId
            actorDid:(NSString *)actorDid
               emoji:(NSString *)emoji
               error:(NSError **)error {
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *query = @"INSERT OR REPLACE INTO message_reactions (message_id, actor_did, emoji, created_at) VALUES (?, ?, ?, ?)";
    return [(PDSDatabase *)self.database executeUpdate:query
                                            withParams:@[messageId, actorDid, emoji, now]
                                                 error:error];
}

- (BOOL)removeReaction:(NSString *)messageId
              actorDid:(NSString *)actorDid
                 emoji:(NSString *)emoji
                 error:(NSError **)error {
    NSString *query = @"DELETE FROM message_reactions WHERE message_id = ? AND actor_did = ? AND emoji = ?";
    return [(PDSDatabase *)self.database executeUpdate:query
                                            withParams:@[messageId, actorDid, emoji]
                                                 error:error];
}

#pragma mark - Conversation Preferences

- (BOOL)muteConversation:(NSString *)convoId
              memberDid:(NSString *)memberDid
                  error:(NSError **)error {
    NSString *query = @"UPDATE conversation_members SET muted = 1 WHERE convo_id = ? AND member_did = ?";
    return [(PDSDatabase *)self.database executeUpdate:query
                                            withParams:@[convoId, memberDid]
                                                 error:error];
}

- (BOOL)unmuteConversation:(NSString *)convoId
                 memberDid:(NSString *)memberDid
                     error:(NSError **)error {
    NSString *query = @"UPDATE conversation_members SET muted = 0 WHERE convo_id = ? AND member_did = ?";
    return [(PDSDatabase *)self.database executeUpdate:query
                                            withParams:@[convoId, memberDid]
                                                 error:error];
}

#pragma mark - Conversation Locking

- (BOOL)lockConversation:(NSString *)convoId
                  error:(NSError **)error {
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *query = @"UPDATE conversations SET locked = 1, updated_at = ? WHERE id = ?";
    return [(PDSDatabase *)self.database executeUpdate:query
                                            withParams:@[now, convoId]
                                                 error:error];
}

- (BOOL)unlockConversation:(NSString *)convoId
                     error:(NSError **)error {
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *query = @"UPDATE conversations SET locked = 0, updated_at = ? WHERE id = ?";
    return [(PDSDatabase *)self.database executeUpdate:query
                                            withParams:@[now, convoId]
                                                 error:error];
}

#pragma mark - Batch Operations

- (nullable NSArray<NSDictionary *> *)sendMessageBatch:(NSString *)convoId
                                            senderDid:(NSString *)senderDid
                                             messages:(NSArray<NSDictionary *> *)messages
                                                error:(NSError **)error {
    if (messages.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"ChatService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"messages array cannot be empty"}];
        return nil;
    }

    // Check if conversation is locked
    NSString *checkQuery = @"SELECT locked FROM conversations WHERE id = ?";
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:checkQuery
                                                                      params:@[convoId]
                                                                       error:error];
    if (!rows || rows.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"ChatService" code:404
                                             userInfo:@{NSLocalizedDescriptionKey: @"Conversation not found"}];
        return nil;
    }

    NSInteger locked = [rows[0][@"locked"] integerValue];
    if (locked) {
        if (error) *error = [NSError errorWithDomain:@"ChatService" code:403
                                             userInfo:@{NSLocalizedDescriptionKey: @"Conversation is locked"}];
        return nil;
    }

    // Send all messages
    NSMutableArray *sentMessages = [NSMutableArray array];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    for (NSDictionary *msgData in messages) {
        NSString *text = msgData[@"text"];
        NSString *embedJson = msgData[@"embedJson"];

        NSDictionary *sentMsg = [self sendMessage:convoId
                                       senderDid:senderDid
                                            text:text
                                       embedJson:embedJson
                                           error:error];
        if (!sentMsg) return nil;

        [sentMessages addObject:sentMsg];
    }

    return sentMessages;
}

@end
