// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

/**
 * @abstract Search-skeleton XRPC route handlers.
 * @discussion These public read routes require a `q` query field, clamp `limit` to 1...100,
 * forward an optional cursor, and return 400 for a missing query or 500 when the search index
 * fails. They write a service-provided JSON result on success.
 */
@interface ATProtoAppViewXRpcRoutePack (Search)

/** @abstract Searches actor skeletons for the required `q` query. */
- (void)handleSearchActorsSkeleton:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Searches post skeletons for the required `q` query. */
- (void)handleSearchPostsSkeleton:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Searches starter-pack skeletons for the required `q` query. */
- (void)handleSearchStarterPacksSkeleton:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;

@end
