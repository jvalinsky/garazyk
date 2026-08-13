// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoWebTileMothership.h

 @abstract Host-side Web Tile mothership resolve-path mediation (WS10 Phase 11).

 @discussion The unique-origin service worker asks the mothership to
 @c resolve-path. This mediator answers with the normative
 @c { status, headers, body } shape from a CAR-backed @c ATProtoWebTile.
 AT-network loading of the tile archive uses @c +tileWithGetBlob… below.
 Deno @dasl/tiles package remains out of scope.
 */

#import <Foundation/Foundation.h>
#import "Core/ATProtoWebTile.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ATProtoWebTileMothershipErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoWebTileMothershipErrorCode) {
    ATProtoWebTileMothershipErrorInvalidArgument = 1,
    ATProtoWebTileMothershipErrorFetchFailed = 2,
    ATProtoWebTileMothershipErrorUnknownType = 3,
};

/** Injected synchronous HTTP client (composition root supplies SafeHTTP / URLSession). */
@protocol ATProtoWebTileHTTPClient <NSObject>
- (nullable NSData *)sendSynchronousRequest:(NSURLRequest *)request
                                    options:(nullable id)options
                                   response:(NSHTTPURLResponse * _Nullable * _Nullable)response
                                      error:(NSError * _Nullable * _Nullable)error;
@end

/**
 Mediates worker → mothership requests for one loaded tile.
 */
@interface ATProtoWebTileMothership : NSObject

@property (nonatomic, strong, readonly) ATProtoWebTile *tile;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithTile:(ATProtoWebTile *)tile NS_DESIGNATED_INITIALIZER;

/**
 Handles a worker request payload.

 Recognized @c type: @c resolve-path with @c path.
 Returns @{ @"response": @{ @"status", @"headers", @"body" } } on success, or
 @{ @"error": <string> }. Echoes @c requestId when present.
 */
- (NSDictionary *)handleRequest:(NSDictionary *)request;

/** Convenience for resolve-path only (returns the inner response dict). */
- (NSDictionary *)resolvePath:(NSString *)path;

/**
 Fetches a `.tile` / CAR blob via @c com.atproto.sync.getBlob and loads it as a
 Web Tile. @c pdsBaseURL is a PDS origin without a trailing slash.
 */
+ (nullable ATProtoWebTile *)tileWithGetBlobFromPDSBaseURL:(NSString *)pdsBaseURL
                                                      did:(NSString *)did
                                                      cid:(NSString *)cidString
                                               httpClient:(id<ATProtoWebTileHTTPClient>)httpClient
                                                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
