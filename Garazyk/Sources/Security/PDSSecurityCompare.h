// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Declares the PDSSecurityCompare public API.
 */
@interface PDSSecurityCompare : NSObject

/**
 * @abstract Performs the constantTimeEqualData operation.
 */
+ (BOOL)constantTimeEqualData:(nullable NSData *)a
                         data:(nullable NSData *)b;

/**
 * @abstract Performs the constantTimeEqualString operation.
 */
+ (BOOL)constantTimeEqualString:(nullable NSString *)a
                         string:(nullable NSString *)b;

@end

NS_ASSUME_NONNULL_END
