// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

/**
 * @abstract Identity, label, and delegated-write XRPC route handlers.
 * @discussion Public reads validate required query fields and write JSON errors for malformed
 * input. Account-info, subject-status, and delegated writes authenticate the caller; proxy writes
 * transfer the request and authenticated DID to the configured write proxy, which owns response
 * completion and mutation semantics.
 */
@interface ATProtoAppViewXRpcRoutePack (Identity)

/** @abstract Resolves required `handle` to a DID, returning 404 when resolution fails. */
- (void)handleResolveHandle:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Parses required AT URI and returns its stored record, with 400, 404, or 503 as applicable. */
- (void)handleGetRecord:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns labels for required comma-separated `uris`; an unavailable database produces an empty list. */
- (void)handleQueryLabels:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns available account information for required `dids` to an authenticated caller. */
- (void)handleGetAccountInfos:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns the placeholder moderation status for required `did` or `uri` to an authenticated caller. */
- (void)handleGetSubjectStatus:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Authenticates the caller and delegates the named repository write to the configured proxy. */
- (void)handleProxyWrite:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response nsid:(NSString *)nsid;

@end
