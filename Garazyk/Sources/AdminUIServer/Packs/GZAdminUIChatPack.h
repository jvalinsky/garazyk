// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

/** @abstract Admin UI pack for the Chat surface. */
@interface GZAdminUIChatPack : NSObject <GZAdminUIPack>

/** @abstract Renders chat-conversation results. */
+ (NSString *)renderChatConvosPartial:(NSDictionary *)result;
/** @abstract Renders chat-message results. */
+ (NSString *)renderChatMessagesPartial:(NSDictionary *)result;

@end

NS_ASSUME_NONNULL_END
