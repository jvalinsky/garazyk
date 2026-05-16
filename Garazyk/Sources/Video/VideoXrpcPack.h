// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoVideoXrpcPack : NSObject <XrpcRoutePack>

/// Validates that the data appears to be a valid video container (MP4 ftyp or Matroska header).
+ (BOOL)validateVideoContentType:(NSData *)data declaredMimeType:(NSString *)mimeType;

@end

NS_ASSUME_NONNULL_END
