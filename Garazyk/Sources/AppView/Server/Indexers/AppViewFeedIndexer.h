// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewFeedIndexer.h

 @abstract Indexes app.bsky.feed.* records: posts, reposts, likes, feed generators.

 Handles:
  - app.bsky.feed.post
  - app.bsky.feed.repost
  - app.bsky.feed.like
  - app.bsky.feed.generator
  - app.bsky.feed.threadgate
  - app.bsky.feed.postgate

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppViewIndexer.h"

NS_ASSUME_NONNULL_BEGIN

@class AppViewDatabase;

@interface AppViewFeedIndexer : NSObject <AppViewIndexer>

/**
 * @abstract Performs the initWithDatabase operation.
 */
- (instancetype)initWithDatabase:(AppViewDatabase *)database;

@end

NS_ASSUME_NONNULL_END
