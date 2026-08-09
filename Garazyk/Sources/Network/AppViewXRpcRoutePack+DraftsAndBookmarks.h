// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

/**
 * @abstract Authenticated draft and bookmark XRPC route handlers.
 * @discussion Both handlers scope results to the DID from a validated bearer token. Authentication
 * failures write a response before returning; backing-service failures produce 500 JSON errors.
 * Bookmark reads clamp `limit` to 1...100 and forward an optional cursor.
 */
@interface AppViewXRpcRoutePack (DraftsAndBookmarks)

/** @abstract Returns drafts owned by the authenticated actor. */
- (void)handleGetDrafts:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns bookmarks owned by the authenticated actor with optional cursor pagination. */
- (void)handleGetBookmarks:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;

@end
