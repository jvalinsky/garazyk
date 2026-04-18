#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

@interface ChatService : NSObject

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

// Conversation management
- (nullable NSDictionary *)createConversationWithMembers:(NSArray<NSString *> *)memberDids
                                                  error:(NSError **)error;

- (nullable NSDictionary *)getConversationForMembers:(NSArray<NSString *> *)memberDids
                                               error:(NSError **)error;

- (nullable NSDictionary *)getConversationWithId:(NSString *)convoId
                                           error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listConversationsForActor:(NSString *)actorDid
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                          error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listAllConversationsWithLimit:(NSInteger)limit
                                                             cursor:(nullable NSString *)cursor
                                                              error:(NSError **)error;

- (BOOL)acceptConversation:(NSString *)convoId
                  memberDid:(NSString *)memberDid
                      error:(NSError **)error;

- (BOOL)leaveConversation:(NSString *)convoId
                memberDid:(NSString *)memberDid
                   error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listConversationRequestsForActor:(NSString *)actorDid
                                                                 error:(NSError **)error;

// Message management
- (nullable NSDictionary *)sendMessage:(NSString *)convoId
                            senderDid:(NSString *)senderDid
                                 text:(nullable NSString *)text
                            embedJson:(nullable NSString *)embedJson
                                error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)getMessagesForConversation:(NSString *)convoId
                                                           limit:(NSInteger)limit
                                                          cursor:(nullable NSString *)cursor
                                                           error:(NSError **)error;

- (BOOL)deleteMessageForSelf:(NSString *)messageId
                   memberDid:(NSString *)memberDid
                       error:(NSError **)error;

- (BOOL)updateLastReadMessage:(NSString *)convoId
                    memberDid:(NSString *)memberDid
                    messageId:(NSString *)messageId
                        error:(NSError **)error;

// Reactions
- (BOOL)addReaction:(NSString *)messageId
            actorDid:(NSString *)actorDid
               emoji:(NSString *)emoji
               error:(NSError **)error;

- (BOOL)removeReaction:(NSString *)messageId
              actorDid:(NSString *)actorDid
                 emoji:(NSString *)emoji
                 error:(NSError **)error;

// Conversation preferences
- (BOOL)muteConversation:(NSString *)convoId
              memberDid:(NSString *)memberDid
                  error:(NSError **)error;

- (BOOL)unmuteConversation:(NSString *)convoId
                 memberDid:(NSString *)memberDid
                     error:(NSError **)error;

// Conversation locking
- (BOOL)lockConversation:(NSString *)convoId
                  error:(NSError **)error;

- (BOOL)unlockConversation:(NSString *)convoId
                     error:(NSError **)error;

// Batch operations
- (nullable NSArray<NSDictionary *> *)sendMessageBatch:(NSString *)convoId
                                            senderDid:(NSString *)senderDid
                                             messages:(NSArray<NSDictionary *> *)messages
                                                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
