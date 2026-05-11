// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAccountEvents.h

 @abstract Shared account lifecycle event names used across services and sync modules.

 @discussion These notifications bridge the account service layer (which has no
 direct reference to SubscribeReposHandler) and the firehose broadcast layer.
 SubscribeReposHandler observes these notifications and emits the corresponding
 #identity and #account firehose events.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Posted when a new account is created. */
extern NSNotificationName const PDSAccountCreatedNotification;

/*! Posted when an account is activated (reinstated from deactivation/takedown). */
extern NSNotificationName const PDSAccountActivatedNotification;

/*! Posted when an account is deactivated by the user. */
extern NSNotificationName const PDSAccountDeactivatedNotification;

#pragma mark - User Info Keys

/*! The DID of the account (NSString). */
extern NSString * const PDSAccountEventDidKey;

/*! The handle of the account (NSString, may be empty). */
extern NSString * const PDSAccountEventHandleKey;

/*! The account status string (NSString, e.g. "deactivated", "takendown"). */
extern NSString * const PDSAccountEventStatusKey;

NS_ASSUME_NONNULL_END
