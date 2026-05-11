// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSLogRedactor : NSObject

+ (NSString *)redactString:(nullable NSString *)message;
+ (NSString *)redactURLString:(nullable NSString *)urlString;

/*!
 @brief Partially masks a standalone token (e.g. returning "abcd...wxyz").
 If the token is too short to mask securely, it returns "<redacted>".
 */
+ (NSString *)maskToken:(nullable NSString *)token;

@end

NS_ASSUME_NONNULL_END
