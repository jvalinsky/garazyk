// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ChatService.h"
#import "Database/PDSDatabase.h"
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
    return [self createConversationWithMembers:memberDids mode:@"plaintext" error:error];
}

- (nullable NSDictionary *)createConversationWithMembers:(NSArray<NSString *> *)memberDids
                                                    mode:(NSString *)mode
                                                  error:(NSError **)error {
    if (memberDids.count < 2) {
        if (error) *error = [NSError errorWithDomain:@"ChatService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Conversation requires at least 2 members"}];
        return nil;
    }

    // Validate mode
    if (![mode isEqualToString:@"plaintext"] && ![mode isEqualToString:@"e2ee"]) {
        if (error) *error = [NSError errorWithDomain:@"ChatService" code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Mode must be 'plaintext' or 'e2ee'"}];
        return nil;
    }

    // Generate conversation ID (e.g., convo/abc123)
    NSString *convoId = [NSString stringWithFormat:@"convo/%@", [[NSUUID UUID] UUIDString]];
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

    // Create conversation with mode
    NSString *insertQuery = @"INSERT INTO conversations (id, mode, created_at, updated_at) VALUES (?, ?, ?, ?)";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:insertQuery
                                                    params:@[convoId, mode, now, now]
                                                         error:error];
    if (!success) return nil;

    // Add members
    for (NSString *memberDid in memberDids) {
        NSString *memberQuery = @"INSERT INTO conversation_members (convo_id, member_did, status, joined_at) VALUES (?, ?, ?, ?)";
        success = [(PDSDatabase *)self.database executeParameterizedUpdate:memberQuery
                                                   params:@[convoId, memberDid, @"pending", now]
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

    // Build query that checks ALL members are present and no extras exist.
    // For N members: each member must be in the conversation, AND the total
    // member count must equal N (prevents matching a superset conversation).
    NSMutableString *query = [NSMutableString stringWithString:@"SELECT c.id FROM conversations c WHERE "];
    NSMutableArray *params = [NSMutableArray array];

    for (NSUInteger i = 0; i < sortedMembers.count; i++) {
        if (i > 0) [query appendString:@" AND "];
        [query appendFormat:@"c.id IN (SELECT convo_id FROM conversation_members WHERE member_did = ?)"];
        [params addObject:sortedMembers[i]];
    }
    [query appendFormat:@" AND (SELECT COUNT(*) FROM conversation_members WHERE convo_id = c.id) = ? LIMIT 1"];
    [params addObject:@(sortedMembers.count)];

    NSError *queryError = nil;
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query
                                                                      params:params
                                                                       error:&queryError];
    if (queryError) {
        if (error) *error = queryError;
        return nil;
    }

    if (rows.count > 0) {
        NSString *convoId = rows[0][@"id"];
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
    NSMutableArray *memberDids = [NSMutableArray array];
    for (NSDictionary *memberRow in memberRows) {
        NSString *did = memberRow[@"member_did"];
        [members addObject:@{
            @"did": did,
            @"status": memberRow[@"status"],
            @"muted": memberRow[@"muted"],
            @"lastReadId": memberRow[@"last_read_id"] ?: [NSNull null],
            @"joinedAt": memberRow[@"joined_at"]
        }];
        [memberDids addObject:did];
    }

    NSArray *lastMessages = [self getMessagesForConversation:convoId limit:1 cursor:nil error:nil];
    NSDictionary *lastMessage = lastMessages.count > 0 ? lastMessages[0] : nil;

    NSMutableDictionary *conversation = [@{
        @"id": convoRow[@"id"],
        @"createdAt": convoRow[@"created_at"],
        @"updatedAt": convoRow[@"updated_at"],
        @"members": members,
        @"memberList": [memberDids componentsJoinedByString:@", "]
    } mutableCopy];
    if (lastMessage) {
        conversation[@"lastMessage"] = lastMessage;
    }
    return conversation;
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

- (nullable NSArray<NSDictionary *> *)listAllConversationsWithLimit:(NSInteger)limit
                                                             cursor:(nullable NSString *)cursor
                                                              error:(NSError **)error {
    NSString *query = @"SELECT id, created_at, updated_at FROM conversations";
    if (cursor) {
        query = [query stringByAppendingString:@" WHERE id < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY updated_at DESC LIMIT ?"];

    NSMutableArray *params = [NSMutableArray array];
    if (cursor) [params addObject:cursor];
    [params addObject:@(limit)];

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
        NSDictionary *convo = [self getConversationWithId:row[@"id"] error:nil];
        if (convo) [conversations addObject:convo];
    }

    return conversations;
}

- (BOOL)acceptConversation:(NSString *)convoId
                 memberDid:(NSString *)memberDid
                     error:(NSError **)error {
    NSString *query = @"UPDATE conversation_members SET status = ? WHERE convo_id = ? AND member_did = ?";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:query
                                            params:@[@"accepted", convoId, memberDid]
                                                 error:error];
    if (success) {
        [self logChatEvent:@"accept" convoId:convoId actorDid:memberDid data:nil error:nil];
    }
    return success;
}

- (BOOL)leaveConversation:(NSString *)convoId
                memberDid:(NSString *)memberDid
                   error:(NSError **)error {
    NSString *query = @"UPDATE conversation_members SET status = ? WHERE convo_id = ? AND member_did = ?";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:query
                                            params:@[@"left", convoId, memberDid]
                                                 error:error];
    if (success) {
        [self logChatEvent:@"leave" convoId:convoId actorDid:memberDid data:nil error:nil];
    }
    return success;
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

#pragma mark - Event Logging

- (BOOL)logChatEvent:(NSString *)eventType
             convoId:(NSString *)convoId
            actorDid:(NSString *)actorDid
                data:(nullable NSDictionary *)data
               error:(NSError **)error {
    NSString *eventId = [[NSUUID UUID] UUIDString];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSString *dataJson = nil;
    if (data) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:nil];
        dataJson = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    
    NSString *sql = @"INSERT INTO chat_event_log (id, convo_id, actor_did, event_type, event_data, created_at) "
                    @"VALUES (?, ?, ?, ?, ?, ?)";
    NSArray *params = @[
        eventId,
        convoId,
        actorDid,
        eventType,
        dataJson ?: [NSNull null],
        @( (long long)now )
    ];
    
    return [(PDSDatabase *)self.database executeParameterizedUpdate:sql params:params error:error];
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
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:query
                                                    params:@[messageId, convoId, senderDid, text ?: [NSNull null], embedJson ?: [NSNull null], now]
                                                         error:error];
    if (!success) return nil;

    // Log the message event
    [self logChatEvent:@"message" convoId:convoId actorDid:senderDid data:@{@"messageId": messageId} error:nil];

    // Update conversation updated_at
    NSString *updateQuery = @"UPDATE conversations SET updated_at = ? WHERE id = ?";
    [(PDSDatabase *)self.database executeParameterizedUpdate:updateQuery params:@[now, convoId] error:nil];

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
    return [(PDSDatabase *)self.database executeParameterizedUpdate:updateQuery
                                            params:@[newJson, messageId]
                                                 error:error];
}

- (BOOL)updateLastReadMessage:(NSString *)convoId
                    memberDid:(NSString *)memberDid
                    messageId:(NSString *)messageId
                        error:(NSError **)error {
    NSString *query = @"UPDATE conversation_members SET last_read_id = ? WHERE convo_id = ? AND member_did = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:query
                                            params:@[messageId, convoId, memberDid]
                                                 error:error];
}

#pragma mark - Reactions

- (BOOL)addReaction:(NSString *)messageId
            actorDid:(NSString *)actorDid
               emoji:(NSString *)emoji
               error:(NSError **)error {
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *query = @"INSERT OR REPLACE INTO message_reactions (message_id, actor_did, emoji, created_at) VALUES (?, ?, ?, ?)";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:query
                                            params:@[messageId, actorDid, emoji, now]
                                                 error:error];
    if (success) {
        // Get convoId for this message
        NSString *convoQuery = @"SELECT convo_id FROM messages WHERE id = ?";
        NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:convoQuery params:@[messageId] error:nil];
        if (rows.count > 0) {
            [self logChatEvent:@"reaction_add" convoId:rows[0][@"convo_id"] actorDid:actorDid data:@{@"messageId": messageId, @"emoji": emoji} error:nil];
        }
    }
    return success;
}

- (BOOL)removeReaction:(NSString *)messageId
               actorDid:(NSString *)actorDid
                  emoji:(NSString *)emoji
                  error:(NSError **)error {
    NSString *query = @"DELETE FROM message_reactions WHERE message_id = ? AND actor_did = ? AND emoji = ?";
    BOOL success = [(PDSDatabase *)self.database executeParameterizedUpdate:query
                                            params:@[messageId, actorDid, emoji]
                                                 error:error];
    if (success) {
        // Get convoId for this message
        NSString *convoQuery = @"SELECT convo_id FROM messages WHERE id = ?";
        NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:convoQuery params:@[messageId] error:nil];
        if (rows.count > 0) {
            [self logChatEvent:@"reaction_remove" convoId:rows[0][@"convo_id"] actorDid:actorDid data:@{@"messageId": messageId, @"emoji": emoji} error:nil];
        }
    }
    return success;
}


#pragma mark - Conversation Preferences

- (BOOL)muteConversation:(NSString *)convoId
              memberDid:(NSString *)memberDid
                  error:(NSError **)error {
    NSString *query = @"UPDATE conversation_members SET muted = 1 WHERE convo_id = ? AND member_did = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:query
                                            params:@[convoId, memberDid]
                                                 error:error];
}

- (BOOL)unmuteConversation:(NSString *)convoId
                 memberDid:(NSString *)memberDid
                     error:(NSError **)error {
    NSString *query = @"UPDATE conversation_members SET muted = 0 WHERE convo_id = ? AND member_did = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:query
                                            params:@[convoId, memberDid]
                                                 error:error];
}

#pragma mark - Conversation Locking

- (BOOL)lockConversation:(NSString *)convoId
                  error:(NSError **)error {
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *query = @"UPDATE conversations SET locked = 1, updated_at = ? WHERE id = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:query
                                            params:@[now, convoId]
                                                 error:error];
}

- (BOOL)unlockConversation:(NSString *)convoId
                     error:(NSError **)error {
    NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *query = @"UPDATE conversations SET locked = 0, updated_at = ? WHERE id = ?";
    return [(PDSDatabase *)self.database executeParameterizedUpdate:query
                                            params:@[now, convoId]
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

- (nullable NSArray<NSDictionary *> *)getChatLogWithLimit:(NSInteger)limit
                                                 cursor:(nullable NSString *)cursor
                                                  error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);
    
    NSString *query = @"SELECT * FROM chat_event_log ";
    NSMutableArray *params = [NSMutableArray array];
    
    if (cursor) {
        query = [query stringByAppendingString:@"WHERE created_at < ? "];
        [params addObject:cursor];
    }
    
    query = [query stringByAppendingString:@"ORDER BY created_at DESC LIMIT ?"];
    [params addObject:@(limit)];
    
    NSArray *rows = [(PDSDatabase *)self.database executeParameterizedQuery:query params:params error:error];
    if (!rows) return nil;
    
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSMutableDictionary *logEntry = [row mutableCopy];
        // Parse event_data if present
        NSString *dataJson = row[@"event_data"];
        if (dataJson && ![dataJson isKindOfClass:[NSNull class]]) {
            NSData *data = [dataJson dataUsingEncoding:NSUTF8StringEncoding];
            logEntry[@"data"] = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] ?: @{};
        }
        [results addObject:logEntry];
    }
    
    return results;
}

@end
