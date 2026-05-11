// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewActorIndexer.h

 @abstract Indexes app.bsky.actor.profile records into the AppView database.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppViewIndexer.h"

NS_ASSUME_NONNULL_BEGIN

@class AppViewDatabase;

/*!
 @class AppViewActorIndexer

 @abstract Materializes actor profiles (display name, bio, avatar CID, banner CID).

 Handles:
  - app.bsky.actor.profile (create / update / delete)
 */
@interface AppViewActorIndexer : NSObject <AppViewIndexer>

- (instancetype)initWithDatabase:(AppViewDatabase *)database;

@end

NS_ASSUME_NONNULL_END
