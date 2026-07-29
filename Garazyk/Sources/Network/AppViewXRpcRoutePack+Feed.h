// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

/**
 * @abstract Feed XRPC route handlers.
 * @discussion Read handlers return a JSON result on success, 400 for missing required query
 * fields, and usually 500 for service failures. Page-based handlers clamp `limit` to 1...100
 * and forward `cursor`; timeline reads require a valid caller bearer token.
 */
@interface AppViewXRpcRoutePack (Feed)

/** @abstract Returns the authenticated actor's timeline, paginated by optional cursor. */
- (void)handleGetTimeline:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns an actor feed after validating `actor`, with cursor and optional filter. */
- (void)handleGetAuthorFeed:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns a post thread for `uri`, clamping optional depth to 0...100; absent threads return 404. */
- (void)handleGetPostThread:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns feed-generator output for `feed`, with cursor pagination. */
- (void)handleGetFeed:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns likes made by `actor`, with cursor pagination. */
- (void)handleGetActorLikes:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns posts for a required comma-separated `uris` query value. */
- (void)handleGetPosts:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns feed generators for a required comma-separated `uris` query value. */
- (void)handleGetFeedGenerators:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns likes for a required post `uri`, with cursor pagination. */
- (void)handleGetLikes:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns reposters for a required post `uri`, with cursor pagination. */
- (void)handleGetRepostedBy:(HttpRequest *)request response:(HttpResponse *)response;

@end
