// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppViewIndexer.h"

@class AppViewDatabase;
@class PDSBookmarkService;

NS_ASSUME_NONNULL_BEGIN

@class PDSBookmarkService;

@interface AppViewBookmarkIndexer : NSObject <AppViewIndexer>

- (instancetype)initWithDatabase:(AppViewDatabase *)database
               bookmarkService:(PDSBookmarkService *)bookmarkService;

@end

NS_ASSUME_NONNULL_END