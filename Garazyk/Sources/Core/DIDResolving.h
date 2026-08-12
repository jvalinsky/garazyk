// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol DIDResolving

 @abstract Resolves a DID to its document.

 @discussion Extracted so callers that need to resolve a DID (e.g.
 Sync's ATProtoRelayEventValidator) can depend on the capability without
 depending on PLC, which owns the concrete PLC-directory-backed
 implementation (ATProtoDIDPLCResolver). Breaks the PLC <-> Sync cycle from
 workstream 08 M4: ATProtoPLCServer already legitimately depends on Sync
 (PDSWebSocketNetworkAdapter) for its own WebSocket transport, so the
 dependency the other direction needs to go through Core instead of
 Sync importing PLC concretely.
 */
@protocol DIDResolving <NSObject>

/*!
 @method resolveDID:error:

 @abstract Resolves a DID to its document.

 @param did The DID to resolve.
 @param error On return, contains an error if resolution failed.
 @return The resolved DID document, or nil on failure.
 */
- (nullable NSDictionary *)resolveDID:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
