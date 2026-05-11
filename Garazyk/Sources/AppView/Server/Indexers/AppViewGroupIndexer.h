// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppViewIndexer.h"

@class AppViewDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface AppViewGroupIndexer : NSObject <AppViewIndexer>

- (instancetype)initWithDatabase:(AppViewDatabase *)database;

@end

NS_ASSUME_NONNULL_END