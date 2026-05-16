// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/Connection/ATProtoConnectionManager.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Provides serialized database connection access.
 */
@interface ATProtoConnectionManagerSerial : NSObject <ATProtoConnectionManager>

- (instancetype)initWithLabel:(NSString *)label;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
