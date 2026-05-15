// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/Connection/ATProtoConnectionManager.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoConnectionPool;

@interface ATProtoConnectionManagerPooled : NSObject <ATProtoConnectionManager>

- (instancetype)initWithPool:(ATProtoConnectionPool *)pool;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
