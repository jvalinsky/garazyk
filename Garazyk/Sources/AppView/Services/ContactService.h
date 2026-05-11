// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ContactService.h

 @abstract Contact import and matching service.

 @discussion Handles phone verification, contact import, and secure
 contact matching between users. Uses private set intersection for
 privacy-preserving contact discovery.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class ActorService;

/*!
 @class ContactService

 @abstract Service for contact import and matching.
 */
@interface ContactService : NSObject

/*! Initialize with database connection and actor service. */
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database
                    actorService:(nullable ActorService *)actorService;

/*! Database connection. */
@property (nonatomic, strong, readonly) id<PDSQueryDatabase> database;

#pragma mark - Phone Verification

/*! Start phone verification, returns verification ID. */
- (nullable NSString *)startPhoneVerification:(NSString *)phoneNumber
                                       actor:(NSString *)actorDID
                                       error:(NSError **)error;

/*! Verify phone code, returns JWT token for contact import. */
- (nullable NSString *)verifyPhone:(NSString *)phoneNumber
                             code:(NSString *)code
                            actor:(NSString *)actorDID
                            error:(NSError **)error;

#pragma mark - Contact Import

/*! Import contacts, returns matches with contact indexes. */
- (nullable NSDictionary *)importContacts:(NSArray<NSString *> *)contacts
                                    token:(NSString *)token
                                    actor:(NSString *)actorDID
                                    error:(NSError **)error;

/*! Get matches for actor. */
- (nullable NSArray<NSDictionary *> *)getMatchesForActor:(NSString *)actorDID
                                                   error:(NSError **)error;

/*! Dismiss a match. */
- (BOOL)dismissMatch:(NSString *)matchDID
              actor:(NSString *)actorDID
              error:(NSError **)error;

#pragma mark - Sync Status

/*! Get sync status for actor. */
- (nullable NSDictionary *)getSyncStatusForActor:(NSString *)actorDID
                                           error:(NSError **)error;

/*! Remove all contact data for actor. */
- (BOOL)removeDataForActor:(NSString *)actorDID
                     error:(NSError **)error;

#pragma mark - Notifications (Admin)

/*! Send contact notification (admin/system only). */
- (BOOL)sendNotificationFrom:(NSString *)fromDID
                          to:(NSString *)toDID
                       error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
