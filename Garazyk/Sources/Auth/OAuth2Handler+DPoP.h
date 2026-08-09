// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @category DPoP
 * @abstract Provides request-origin derivation and DPoP proof validation for OAuth endpoints.
 */
@interface OAuth2Handler (DPoP)
/**
 * @abstract Validates the DPoP proof bound to an OAuth endpoint request.
 * @discussion Treats proof and request headers as untrusted; derives a canonical URL and requires a nonce.
 * Verifies method, URL, and replay protections; failures write JSON errors.
 * Nonce failures add DPoP nonce, WWW-Authenticate, and cache headers; success adds a nonce and output.
 * @param request The incoming request whose DPoP proof and request target are verified.
 * @param response The response mutated with an OAuth error or a DPoP nonce as required.
 * @param outThumbprint Optional storage for the verified proof key's JWK thumbprint.
 * @return YES when the proof is valid for the canonical request; otherwise NO.
 */
- (BOOL)validateDPoPForRequest:(ATProtoHttpRequest *)request
                      response:(ATProtoHttpResponse *)response
                 outThumbprint:(NSString **)outThumbprint;
/**
 * @abstract Adds a fresh DPoP nonce response header when no nonce is already present.
 * @discussion Preserves either casing of an existing DPoP nonce header. The generated nonce comes
 * from the process nonce manager and is not persisted by this method.
 * @param response The response to inspect and, when needed, mutate.
 */
- (void)attachDPoPNonceToResponseIfMissing:(ATProtoHttpResponse *)response;
/**
 * @abstract Derives the canonical URL used to compare a DPoP proof's `htu` claim.
 * @discussion Outside local development and an explicitly trusted reverse proxy, this method uses
 * the configured issuer authority instead of the client-controlled Host header. Forwarded scheme
 * headers are considered only when requestShouldTrustForwardedHeaders: permits them. Returns nil
 * when no usable authority or URL can be constructed.
 * @param request The request supplying the path, query, and conditionally trusted origin headers.
 * @return The canonical request URL, or nil when the target cannot be formed.
 */
- (NSURL *)expectedDPoPURLForRequest:(ATProtoHttpRequest *)request;
/**
 * @abstract Derives the canonical origin used by OAuth metadata and audience comparisons.
 * @discussion Applies the same Host and forwarded-header trust boundary as
 * expectedDPoPURLForRequest:. It falls back to the configured issuer when no authority is
 * available.
 * @param request The request supplying the conditionally trusted origin headers.
 * @return The canonical scheme-and-authority origin, or the configured issuer fallback.
 */
- (NSString *)requestOriginForRequest:(ATProtoHttpRequest *)request;
/**
 * @abstract Reports whether this request may supply trusted forwarded origin headers.
 * @discussion Forwarded headers are trusted only when `PDS_TRUST_PROXY_HEADERS` is enabled and
 * the peer address is loopback or an accepted RFC 1918 IPv4 private address. This prevents a
 * remote client from selecting the DPoP or metadata origin through forwarded headers.
 * @param request The request whose peer address is evaluated.
 * @return YES when forwarded headers may participate in origin derivation; otherwise NO.
 */
- (BOOL)requestShouldTrustForwardedHeaders:(ATProtoHttpRequest *)request;
@end

NS_ASSUME_NONNULL_END
