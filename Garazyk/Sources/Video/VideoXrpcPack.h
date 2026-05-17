// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Registers video service XRPC routes.
 */
@interface ATProtoVideoXrpcPack : NSObject <XrpcRoutePack>

/**
 * @abstract Validates that bytes match a supported video container signature.
 */
+ (BOOL)validateVideoContentType:(NSData *)data declaredMimeType:(NSString *)mimeType;

@end

NS_ASSUME_NONNULL_END
