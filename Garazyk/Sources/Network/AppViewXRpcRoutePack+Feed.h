// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

/**
 * @abstract Feed XRPC route handlers.
 * @discussion Read handlers return a JSON result on success, 400 for missing required query
 * fields, and usually 500 for service failures. Page-based handlers clamp `limit` to 1...100
 * and forward `cursor`; timeline reads require a valid caller bearer token.
 */
@interface ATProtoAppViewXRpcRoutePack (Feed)

/** @abstract Returns the authenticated actor's timeline, paginated by optional cursor. */
- (void)handleGetTimeline:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns an actor feed after validating `actor`, with cursor and optional filter. */
- (void)handleGetAuthorFeed:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns a post thread for `uri`, clamping optional depth to 0...100; absent threads return 404. */
- (void)handleGetPostThread:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns feed-generator output for `feed`, with cursor pagination. */
- (void)handleGetFeed:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns likes made by `actor`, with cursor pagination. */
- (void)handleGetActorLikes:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns posts for a required comma-separated `uris` query value. */
- (void)handleGetPosts:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns feed generators for a required comma-separated `uris` query value. */
- (void)handleGetFeedGenerators:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns likes for a required post `uri`, with cursor pagination. */
- (void)handleGetLikes:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns reposters for a required post `uri`, with cursor pagination. */
- (void)handleGetRepostedBy:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;

@end
