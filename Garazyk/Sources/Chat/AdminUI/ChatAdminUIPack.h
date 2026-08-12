// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Embedded admin UI pack for the syrena-chat service.
 * @discussion Registers privacy-safe routes directly — no centralized
 * backend proxy. Conversation metadata is allowlisted; message bodies
 * are never rendered by default.
 */
@interface GZChatAdminUIPack : NSObject <GZAdminUIPack>

@end

NS_ASSUME_NONNULL_END
