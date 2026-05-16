// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

/**
 * @abstract Database query interface used by chat service operations.
 */
@protocol PDSQueryDatabase;

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

@interface ChatService : NSObject

/**
 * @abstract Initializes the receiver with the supplied dependencies.
 * @param database Database dependency used for persistence and queries.
 * @return An initialized instance.
 */
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

// Conversation management
- (nullable NSDictionary *)createConversationWithMembers:(NSArray<NSString *> *)memberDids
                                                  error:(NSError **)error;

/**
 * @abstract Create conversation with members.
 * @param memberDids Member DIDs for the conversation.
 * @param mode Conversation mode.
 * @param error Receives details when the operation fails.
 * @return The response dictionary, or nil when the request fails.
 */
- (nullable NSDictionary *)createConversationWithMembers:(NSArray<NSString *> *)memberDids
                                                    mode:(NSString *)mode
                                                  error:(NSError **)error;

/**
 * @abstract Get conversation for members.
 * @param memberDids Member DIDs for the conversation.
 * @param error Receives details when the operation fails.
 * @return The response dictionary, or nil when the request fails.
 */
- (nullable NSDictionary *)getConversationForMembers:(NSArray<NSString *> *)memberDids
                                               error:(NSError **)error;

- (nullable NSDictionary *)getConversationWithId:(NSString *)convoId
                                           error:(NSError **)error;

/**
 * @abstract List conversations for actor.
 * @param actorDid Actor DID for the request.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor from a previous response.
 * @param error Receives details when the operation fails.
 * @return The response array, or nil when the request fails.
 */
- (nullable NSArray<NSDictionary *> *)listConversationsForActor:(NSString *)actorDid
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                          error:(NSError **)error;

/**
 * @abstract List all conversations with limit.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor from a previous response.
 * @param error Receives details when the operation fails.
 * @return The response array, or nil when the request fails.
 */
- (nullable NSArray<NSDictionary *> *)listAllConversationsWithLimit:(NSInteger)limit
                                                             cursor:(nullable NSString *)cursor
                                                              error:(NSError **)error;

/**
 * @abstract Accept conversation.
 * @param convoId Conversation identifier.
 * @param memberDid Actor DID for the request.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)acceptConversation:(NSString *)convoId
                  memberDid:(NSString *)memberDid
                      error:(NSError **)error;

/**
 * @abstract Leave conversation.
 * @param convoId Conversation identifier.
 * @param memberDid Actor DID for the request.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)leaveConversation:(NSString *)convoId
                memberDid:(NSString *)memberDid
                   error:(NSError **)error;

/**
 * @abstract List conversation requests for actor.
 * @param actorDid Actor DID for the request.
 * @param error Receives details when the operation fails.
 * @return The response array, or nil when the request fails.
 */
- (nullable NSArray<NSDictionary *> *)listConversationRequestsForActor:(NSString *)actorDid
                                                                 error:(NSError **)error;

// Message management
- (nullable NSDictionary *)sendMessage:(NSString *)convoId
                            senderDid:(NSString *)senderDid
                                 text:(nullable NSString *)text
                            embedJson:(nullable NSString *)embedJson
                                error:(NSError **)error;

/**
 * @abstract Get messages for conversation.
 * @param convoId Conversation identifier.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor from a previous response.
 * @param error Receives details when the operation fails.
 * @return The response array, or nil when the request fails.
 */
- (nullable NSArray<NSDictionary *> *)getMessagesForConversation:(NSString *)convoId
                                                           limit:(NSInteger)limit
                                                          cursor:(nullable NSString *)cursor
                                                           error:(NSError **)error;

/**
 * @abstract Delete message for self.
 * @param messageId Message identifier.
 * @param memberDid Actor DID for the request.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)deleteMessageForSelf:(NSString *)messageId
                   memberDid:(NSString *)memberDid
                       error:(NSError **)error;

/**
 * @abstract Update last read message.
 * @param convoId Conversation identifier.
 * @param memberDid Actor DID for the request.
 * @param messageId Message identifier.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)updateLastReadMessage:(NSString *)convoId
                    memberDid:(NSString *)memberDid
                    messageId:(NSString *)messageId
                        error:(NSError **)error;

// Reactions
/**
 * @abstract Add reaction.
 * @param messageId Message identifier.
 * @param actorDid Actor DID for the request.
 * @param emoji Emoji reaction.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)addReaction:(NSString *)messageId
            actorDid:(NSString *)actorDid
               emoji:(NSString *)emoji
               error:(NSError **)error;

/**
 * @abstract Remove reaction.
 * @param messageId Message identifier.
 * @param actorDid Actor DID for the request.
 * @param emoji Emoji reaction.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)removeReaction:(NSString *)messageId
              actorDid:(NSString *)actorDid
                 emoji:(NSString *)emoji
                 error:(NSError **)error;

// Conversation preferences
/**
 * @abstract Mute conversation.
 * @param convoId Conversation identifier.
 * @param memberDid Actor DID for the request.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)muteConversation:(NSString *)convoId
              memberDid:(NSString *)memberDid
                  error:(NSError **)error;

/**
 * @abstract Unmute conversation.
 * @param convoId Conversation identifier.
 * @param memberDid Actor DID for the request.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)unmuteConversation:(NSString *)convoId
                 memberDid:(NSString *)memberDid
                     error:(NSError **)error;

// Conversation locking
/**
 * @abstract Lock conversation.
 * @param convoId Conversation identifier.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)lockConversation:(NSString *)convoId
                  error:(NSError **)error;

- (BOOL)unlockConversation:(NSString *)convoId
                     error:(NSError **)error;

// Conversation mode (plaintext|e2ee)
/**
 * @abstract Set conversation mode.
 * @param convoId Conversation identifier.
 * @param mode Conversation mode.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)setConversationMode:(NSString *)convoId
                       mode:(NSString *)mode
                      error:(NSError **)error;

// Batch operations
/**
 * @abstract Send message batch.
 * @param convoId Conversation identifier.
 * @param senderDid Actor DID for the request.
 * @param messages Message payloads to send.
 * @param error Receives details when the operation fails.
 * @return The response array, or nil when the request fails.
 */
- (nullable NSArray<NSDictionary *> *)sendMessageBatch:(NSString *)convoId
                                             senderDid:(NSString *)senderDid
                                              messages:(NSArray<NSDictionary *> *)messages
                                                 error:(NSError **)error;

// Event Log
/**
 * @abstract Get chat log with limit.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor from a previous response.
 * @param error Receives details when the operation fails.
 * @return The response array, or nil when the request fails.
 */
- (nullable NSArray<NSDictionary *> *)getChatLogWithLimit:(NSInteger)limit
                                                 cursor:(nullable NSString *)cursor
                                                  error:(NSError **)error;

@end


NS_ASSUME_NONNULL_END
