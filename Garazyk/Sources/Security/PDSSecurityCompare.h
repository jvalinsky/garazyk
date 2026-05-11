// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSSecurityCompare : NSObject

+ (BOOL)constantTimeEqualData:(nullable NSData *)a
                         data:(nullable NSData *)b;

+ (BOOL)constantTimeEqualString:(nullable NSString *)a
                         string:(nullable NSString *)b;

@end

NS_ASSUME_NONNULL_END
