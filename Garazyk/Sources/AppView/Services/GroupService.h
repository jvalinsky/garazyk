// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/**
 * @abstract Service layer for group metadata, membership, invites, join requests, and messages.
 */
@interface GroupService : NSObject

/**
 * @abstract Creates a group service backed by a query database.
 */
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

// Group CRUD
/** Creates a group and returns its persisted representation. */
- (nullable NSDictionary *)createGroupWithName:(NSString *)name
                                   description:(nullable NSString *)description
                                      creator:(NSString *)creatorDid
                                      privacy:(NSString *)privacy
                                  joinability:(NSString *)joinability
                                        error:(NSError **)error;

/** Updates mutable group metadata fields. */
- (BOOL)editGroup:(NSString *)groupUri
          newName:(nullable NSString *)name
    newDescription:(nullable NSString *)description
        newPrivacy:(nullable NSString *)privacy
             error:(NSError **)error;

/** Deletes a group by URI. */
- (BOOL)deleteGroup:(NSString *)groupUri
              error:(NSError **)error;

/** Returns public metadata for a group URI. */
- (nullable NSDictionary *)getGroupPublicInfo:(NSString *)groupUri
                                       error:(NSError **)error;

// Member management
/** Adds member DIDs to a group invitation or membership set. */
- (BOOL)addMembersToGroup:(NSString *)groupUri
                members:(NSArray<NSString *> *)memberDids
              invitedBy:(NSString *)inviterDid
                 error:(NSError **)error;

/** Removes member DIDs from a group. */
- (BOOL)removeMembersFromGroup:(NSString *)groupUri
                     members:(NSArray<NSString *> *)memberDids
                       error:(NSError **)error;

/** Lists members for a group with cursor pagination. */
- (nullable NSArray<NSDictionary *> *)listGroupMembers:(NSString *)groupUri
                                                 limit:(NSInteger)limit
                                                cursor:(nullable NSString *)cursor
                                                 error:(NSError **)error;

/** Lists groups visible to the caller with optional search text. */
- (nullable NSArray<NSDictionary *> *)listAllGroupsWithLimit:(NSInteger)limit
                                                      cursor:(nullable NSString *)cursor
                                                       query:(nullable NSString *)query
                                                       error:(NSError **)error;

// Invite links
/** Creates an invite link for a group. */
- (nullable NSString *)createInviteLinkForGroup:(NSString *)groupUri
                                      createdBy:(NSString *)createdByDid
                                       expiresAt:(nullable NSString *)expiresAt
                                        maxUses:(nullable NSNumber *)maxUses
                                          error:(NSError **)error;

/** Lists invite links with optional search text. */
- (nullable NSArray<NSDictionary *> *)listAllInviteLinksWithLimit:(NSInteger)limit
                                                           cursor:(nullable NSString *)cursor
                                                            query:(nullable NSString *)query
                                                            error:(NSError **)error;

/** Updates an invite link's enabled state, expiration, or usage limit. */
- (BOOL)editInviteLink:(NSString *)linkId
              enabled:(NSNumber *)enabled
             expiresAt:(nullable NSString *)expiresAt
              maxUses:(nullable NSNumber *)maxUses
                error:(NSError **)error;

/** Disables an invite link. */
- (BOOL)disableInviteLink:(NSString *)linkId
                    error:(NSError **)error;

/** Validates an invite link and consumes one use for the joining member. */
- (nullable NSDictionary *)validateAndUseInviteLink:(NSString *)linkId
                                         memberDid:(NSString *)memberDid
                                            error:(NSError **)error;

// Join requests
/** Creates a request to join a group. */
- (nullable NSString *)requestJoinGroup:(NSString *)groupUri
                            requesterDid:(NSString *)requesterDid
                                 error:(NSError **)error;

/** Approves a pending group join request. */
- (BOOL)approveJoinRequest:(NSString *)requestId
                 approvingDid:(NSString *)approvingDid
                       error:(NSError **)error;

/** Rejects a pending group join request. */
- (BOOL)rejectJoinRequest:(NSString *)requestId
            rejectingDid:(NSString *)rejectingDid
                  error:(NSError **)error;

/** Lists pending join requests for a group. */
- (nullable NSArray<NSDictionary *> *)listJoinRequestsForGroup:(NSString *)groupUri
                                                         error:(NSError **)error;

// Member leave
/** Removes a member from a group at the member's request. */
- (BOOL)leaveGroup:(NSString *)groupUri
         memberDid:(NSString *)memberDid
             error:(NSError **)error;

// Group messaging
/** Sends a message into a group conversation. */
- (nullable NSString *)sendMessageToGroup:(NSString *)groupUri
                                senderDid:(NSString *)senderDid
                                    text:(NSString *)text
                                   embed:(nullable NSString *)embed
                                   error:(NSError **)error;

/** Returns group messages with cursor pagination. */
- (nullable NSArray<NSDictionary *> *)getMessagesForGroup:(NSString *)groupUri
                                                    limit:(NSInteger)limit
                                                  cursor:(nullable NSString *)cursor
                                                   error:(NSError **)error;

/** Adds an emoji reaction to a group message. */
- (BOOL)addReactionToGroupMessage:(NSString *)messageId
                       actorDid:(NSString *)actorDid
                         emoji:(NSString *)emoji
                         error:(NSError **)error;

/** Removes an emoji reaction from a group message. */
- (BOOL)removeReactionFromGroupMessage:(NSString *)messageId
                            actorDid:(NSString *)actorDid
                              emoji:(NSString *)emoji
                              error:(NSError **)error;

/** Deletes a group message from one member's view. */
- (BOOL)deleteGroupMessageForSelf:(NSString *)messageId
                        memberDid:(NSString *)memberDid
                            error:(NSError **)error;

// Permission checks
/** Returns whether a DID has administrator privileges in a group. */
- (BOOL)isUserAdmin:(NSString *)userDid
           inGroup:(NSString *)groupUri
             error:(NSError **)error;

/** Returns whether a DID is a member of a group. */
- (BOOL)isUserMember:(NSString *)userDid
            inGroup:(NSString *)groupUri
              error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
