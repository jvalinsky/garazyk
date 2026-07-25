// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppViewIndexer.h"

@class AppViewDatabase;
@class BookmarkService;

NS_ASSUME_NONNULL_BEGIN

@class BookmarkService;

@interface AppViewBookmarkIndexer : NSObject <AppViewIndexer>

- (instancetype)initWithDatabase:(AppViewDatabase *)database
               bookmarkService:(BookmarkService *)bookmarkService;

@end

NS_ASSUME_NONNULL_END