// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewNotificationIndexer.h

 @abstract Indexes notification-generating events: mentions, replies, quotes,
 likes of local user posts, follows of local users.

 Handles (as event sources for notification fan-out):
  - app.bsky.feed.like       → notifies the post author
  - app.bsky.feed.repost     → notifies the post author
  - app.bsky.feed.post       → notifies mentioned / replied-to DIDs
  - app.bsky.graph.follow    → notifies the followed DID

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppViewIndexer.h"

NS_ASSUME_NONNULL_BEGIN

@class AppViewDatabase;

@interface AppViewNotificationIndexer : NSObject <AppViewIndexer>

- (instancetype)initWithDatabase:(AppViewDatabase *)database;

@end

NS_ASSUME_NONNULL_END
