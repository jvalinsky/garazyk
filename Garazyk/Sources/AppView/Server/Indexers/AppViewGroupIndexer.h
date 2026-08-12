// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppViewIndexer.h"

@class GZAppViewDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface GZAppViewGroupIndexer : NSObject <AppViewIndexer>

- (instancetype)initWithDatabase:(GZAppViewDatabase *)database;

@end

NS_ASSUME_NONNULL_END