// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Decodes multibase-encoded AT Protocol public keys.
 */
@interface ATProtoMultibase : NSObject

/**
 * Decodes a `publicKeyMultibase` value and removes the optional
 * `secp256k1-pub` multicodec prefix.
 */
+ (nullable NSData *)publicKeyBytesFromMultibase:(NSString *)multibase
                                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
