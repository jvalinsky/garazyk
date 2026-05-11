// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RecordLifecycleHandler.h

 @abstract Observes record changes and triggers side effects.

 @discussion Listens for PDSRecordDidChangeNotification and generates
 notifications for likes, follows, replies, mentions, reposts, and quotes.
 Also handles indexing for bookmarks and starter packs.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NotificationService;
@class BookmarkService;
@class GraphService;
@class FeedService;
@class PDSDatabase;

/*!
 @class RecordLifecycleHandler
 
 @abstract Handles record lifecycle events to generate notifications and index social data.
 */
@interface RecordLifecycleHandler : NSObject

/*! Initialize and start observing record changes. */
- (instancetype)initWithNotificationService:(NotificationService *)notificationService
                             bookmarkService:(BookmarkService *)bookmarkService
                                graphService:(GraphService *)graphService
                                 feedService:(FeedService *)feedService
                                    database:(PDSDatabase *)database;


/*! Stop observing. */
- (void)stopObserving;

@end

NS_ASSUME_NONNULL_END
