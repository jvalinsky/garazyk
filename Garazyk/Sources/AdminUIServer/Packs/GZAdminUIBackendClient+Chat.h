// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Chat administration operations used by the authenticated admin UI.
 * @discussion Calls use the configured chat admin token and block for completion. Successful
 * responses are returned as JSON; invalid input and non-2xx responses return an `error` and
 * usually a `message`. Locking a conversation permanently changes its moderation state.
 */
@interface GZAdminUIBackendClient (Chat)

/**
 * @abstract Lists chat conversations, forwarding an optional cursor and normalizing zero limit to 25.
 */
- (NSDictionary *)fetchChatConvosWithLimit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

/** @abstract Lists messages for a nonempty conversation ID; zero limit is normalized to 50. */
- (NSDictionary *)fetchChatMessagesForConvoID:(NSString *)convoID limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

/** @abstract Requests a lock for a nonempty conversation ID and changes its moderation state. */
- (NSDictionary *)lockChatConvo:(NSString *)convoID;

@end

NS_ASSUME_NONNULL_END
