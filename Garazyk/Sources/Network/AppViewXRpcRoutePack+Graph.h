// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

/**
 * @abstract Graph XRPC route handlers.
 * @discussion Public graph reads validate their required query fields and return 400 for missing
 * values. List endpoints clamp `limit` to 1...100 and forward an optional cursor. Operations
 * requiring the caller's graph state authenticate through `requireAuth:response:`; service
 * failures produce 500 JSON error responses unless a handler documents a 404 result.
 */
@interface AppViewXRpcRoutePack (Graph)

/** @abstract Returns one actor's follows after validating `actor`, with cursor pagination. */
- (void)handleGetFollows:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns one actor's followers after validating `actor`, with cursor pagination. */
- (void)handleGetFollowers:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns the authenticated actor's blocks, with cursor pagination. */
- (void)handleGetBlocks:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns the authenticated actor's mutes, with cursor pagination. */
- (void)handleGetMutes:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns the relationship for `actor` and the first supplied `others` target. */
- (void)handleGetRelationships:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns a starter pack for `uri`, or 404 when no pack is available. */
- (void)handleGetStarterPack:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns an actor's starter packs after validating `actor`, with cursor pagination. */
- (void)handleGetStarterPacks:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns an actor's lists after validating `actor`, with cursor pagination. */
- (void)handleGetLists:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns a list for `list`, with cursor pagination, or 404 when absent. */
- (void)handleGetList:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Authenticates the caller, validates a JSON `actor`, and adds it to the caller's mutes. */
- (void)handleMuteActor:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Authenticates the caller, validates a JSON `actor`, and removes it from the caller's mutes. */
- (void)handleUnmuteActor:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns starter packs for the supplied `uris` values; an absent list yields an empty result. */
- (void)handleGetStarterPacksBulk:(HttpRequest *)request response:(HttpResponse *)response;

@end
