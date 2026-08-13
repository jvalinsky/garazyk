// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

@class GZAdminUIHost;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Embedded admin UI pack for the syrena-chat service.
 * @discussion Registers privacy-safe routes. Conversation/message bodies are
 * never rendered. Live metadata is fetched from local Chat admin endpoints
 * configured via @c +configureHost:serviceBaseURL:adminSecret:.
 */
@interface GZChatAdminUIPack : NSObject <GZAdminUIPack>

/**
 Configures the loopback Chat protocol base URL and admin Bearer secret used
 by conversation/message partials for @c host.
 */
+ (void)configureHost:(GZAdminUIHost *)host
       serviceBaseURL:(NSURL *)serviceBaseURL
          adminSecret:(NSString *)adminSecret;

/** @abstract Renders headline counter cards from /_admin/stats. */
+ (NSString *)statsHTML:(NSDictionary *)stats;
/** @abstract Renders allowlisted conversation metadata rows. */
+ (NSString *)convosHTML:(NSDictionary *)data;
/** @abstract Renders allowlisted message metadata rows for one conversation. */
+ (NSString *)messagesHTML:(NSDictionary *)data convoID:(NSString *)convoID;

@end

NS_ASSUME_NONNULL_END
