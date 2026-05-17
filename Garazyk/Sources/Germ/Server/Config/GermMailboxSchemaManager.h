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

/**
 * @abstract Provides SQL schema strings for the Germ mailbox store.
 */
@interface GermMailboxSchemaManager : NSObject

/** Returns the shared schema manager instance. */
+ (instancetype)sharedManager;

/** Returns SQL for the ephemeral mailbox address table. */
- (NSString *)mailboxesTableSchema;
/** Returns SQL for the ephemeral mailbox message table. */
- (NSString *)mailboxMessagesTableSchema;
/** Returns SQL for the rendezvous address table. */
- (NSString *)rendezvousTableSchema;
/** Returns SQL for the rendezvous message table. */
- (NSString *)rendezvousMessagesTableSchema;

/** Returns the complete mailbox schema SQL batch. */
- (NSString *)mailboxSchemaSQL;

@end

NS_ASSUME_NONNULL_END
