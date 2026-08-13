// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UITilePathResolver.h

 @abstract Injected mothership boundary for Admin UI tile resolve-path.

 @discussion AdminUI links only Transport+Core, so CAR mothership stays in
 Repository. The composition root (or tests) injects a resolver that answers
 the same @{type,path,requestId} → @{response|error} shape as
 @c ATProtoWebTileMothership.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol GZAdminUITilePathResolver <NSObject>
/**
 Handles a worker/mothership request dictionary.

 Recognized @c type: @c resolve-path with @c path.
 Returns @{ @"response": @{ @"status", @"headers", @"body" } } or
 @{ @"error": <string> }, echoing @c requestId when present.
 */
- (NSDictionary *)handleTileRequest:(NSDictionary *)request;
@end

NS_ASSUME_NONNULL_END
