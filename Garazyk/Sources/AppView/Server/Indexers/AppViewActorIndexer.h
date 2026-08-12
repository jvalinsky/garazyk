// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAppViewActorIndexer.h

 @abstract Indexes app.bsky.actor.profile records into the AppView database.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppViewIndexer.h"

NS_ASSUME_NONNULL_BEGIN

@class GZAppViewDatabase;

/*!
 @class GZAppViewActorIndexer

 @abstract Materializes actor profiles (display name, bio, avatar ATProtoCID, banner ATProtoCID).

 Handles:
  - app.bsky.actor.profile (create / update / delete)
 */
@interface GZAppViewActorIndexer : NSObject <AppViewIndexer>

- (instancetype)initWithDatabase:(GZAppViewDatabase *)database;

@end

NS_ASSUME_NONNULL_END
