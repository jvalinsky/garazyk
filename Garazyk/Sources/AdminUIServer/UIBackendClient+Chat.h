// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient (Chat)

/**
 * @abstract Fetch chat convos with limit.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor from a previous response.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchChatConvosWithLimit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

- (NSDictionary *)fetchChatMessagesForConvoID:(NSString *)convoID limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

- (NSDictionary *)lockChatConvo:(NSString *)convoID;

@end

NS_ASSUME_NONNULL_END
