// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSRecordLifecycleHandler.h

 @abstract Observes record changes and triggers side effects.

 @discussion Listens for PDSRecordDidChangeNotification and generates
 notifications for likes, follows, replies, mentions, reposts, and quotes.
 Also handles indexing for bookmarks and starter packs.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSNotificationService;
@class PDSBookmarkService;
@class PDSGraphService;
@class PDSFeedService;
@class PDSDatabase;

/*!
 @class PDSRecordLifecycleHandler
 
 @abstract Handles record lifecycle events to generate notifications and index social data.
 */
@interface PDSRecordLifecycleHandler : NSObject

/*! Initialize and start observing record changes. */
- (instancetype)initWithNotificationService:(PDSNotificationService *)notificationService
                             bookmarkService:(PDSBookmarkService *)bookmarkService
                                graphService:(PDSGraphService *)graphService
                                 feedService:(PDSFeedService *)feedService
                                    database:(PDSDatabase *)database;


/*! Stop observing. */
- (void)stopObserving;

@end

NS_ASSUME_NONNULL_END
