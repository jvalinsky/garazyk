#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

@interface GroupService : NSObject

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

// Group CRUD
- (nullable NSDictionary *)createGroupWithName:(NSString *)name
                                   description:(nullable NSString *)description
                                      creator:(NSString *)creatorDid
                                      privacy:(NSString *)privacy
                                  joinability:(NSString *)joinability
                                        error:(NSError **)error;

- (BOOL)editGroup:(NSString *)groupUri
          newName:(nullable NSString *)name
    newDescription:(nullable NSString *)description
        newPrivacy:(nullable NSString *)privacy
             error:(NSError **)error;

- (nullable NSDictionary *)getGroupPublicInfo:(NSString *)groupUri
                                       error:(NSError **)error;

// Member management
- (BOOL)addMembersToGroup:(NSString *)groupUri
                members:(NSArray<NSString *> *)memberDids
              invitedBy:(NSString *)inviterDid
                 error:(NSError **)error;

- (BOOL)removeMembersFromGroup:(NSString *)groupUri
                     members:(NSArray<NSString *> *)memberDids
                       error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listGroupMembers:(NSString *)groupUri
                                                 limit:(NSInteger)limit
                                                cursor:(nullable NSString *)cursor
                                                 error:(NSError **)error;

// Invite links
- (nullable NSString *)createInviteLinkForGroup:(NSString *)groupUri
                                      createdBy:(NSString *)createdByDid
                                       expiresAt:(nullable NSString *)expiresAt
                                        maxUses:(nullable NSNumber *)maxUses
                                          error:(NSError **)error;

- (BOOL)editInviteLink:(NSString *)linkId
              enabled:(NSNumber *)enabled
             expiresAt:(nullable NSString *)expiresAt
              maxUses:(nullable NSNumber *)maxUses
                error:(NSError **)error;

- (BOOL)disableInviteLink:(NSString *)linkId
                    error:(NSError **)error;

- (nullable NSDictionary *)validateAndUseInviteLink:(NSString *)linkId
                                         memberDid:(NSString *)memberDid
                                            error:(NSError **)error;

// Join requests
- (nullable NSString *)requestJoinGroup:(NSString *)groupUri
                            requesterDid:(NSString *)requesterDid
                                 error:(NSError **)error;

- (BOOL)approveJoinRequest:(NSString *)requestId
                 approvingDid:(NSString *)approvingDid
                       error:(NSError **)error;

- (BOOL)rejectJoinRequest:(NSString *)requestId
            rejectingDid:(NSString *)rejectingDid
                  error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listJoinRequestsForGroup:(NSString *)groupUri
                                                         error:(NSError **)error;

// Member leave
- (BOOL)leaveGroup:(NSString *)groupUri
         memberDid:(NSString *)memberDid
             error:(NSError **)error;

// Group messaging
- (nullable NSString *)sendMessageToGroup:(NSString *)groupUri
                                senderDid:(NSString *)senderDid
                                    text:(NSString *)text
                                   embed:(nullable NSString *)embed
                                   error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)getMessagesForGroup:(NSString *)groupUri
                                                    limit:(NSInteger)limit
                                                  cursor:(nullable NSString *)cursor
                                                   error:(NSError **)error;

- (BOOL)addReactionToGroupMessage:(NSString *)messageId
                       actorDid:(NSString *)actorDid
                         emoji:(NSString *)emoji
                         error:(NSError **)error;

- (BOOL)removeReactionFromGroupMessage:(NSString *)messageId
                            actorDid:(NSString *)actorDid
                              emoji:(NSString *)emoji
                              error:(NSError **)error;

- (BOOL)deleteGroupMessageForSelf:(NSString *)messageId
                        memberDid:(NSString *)memberDid
                            error:(NSError **)error;

// Permission checks
- (BOOL)isUserAdmin:(NSString *)userDid
           inGroup:(NSString *)groupUri
             error:(NSError **)error;

- (BOOL)isUserMember:(NSString *)userDid
            inGroup:(NSString *)groupUri
              error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
