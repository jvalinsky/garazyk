// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GermMailboxSchemaManager.h

 @abstract Schema manager for the Germ E2EE mailbox transport database.

 @discussion Manages the SQLite schema for Germ Protocol mailbox
 transport. Addresses are opaque strings assigned to agents (not DIDs)
 to protect metadata. Ephemeral addresses are single-use and expire;
 rendezvous addresses are epoch-derived and rotate with MLS epochs.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GermMailboxSchemaManager : NSObject

+ (instancetype)sharedManager;

- (NSString *)mailboxesTableSchema;
- (NSString *)mailboxMessagesTableSchema;
- (NSString *)rendezvousTableSchema;
- (NSString *)rendezvousMessagesTableSchema;

- (NSString *)mailboxSchemaSQL;

@end

NS_ASSUME_NONNULL_END
