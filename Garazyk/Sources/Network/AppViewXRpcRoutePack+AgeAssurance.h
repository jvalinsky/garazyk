// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

/**
 * @abstract Age-assurance XRPC route handlers.
 * @discussion Begin and state routes authenticate the actor. Required request fields yield 400,
 * an unavailable age-assurance dependency yields 503, and service failures yield 500. The config
 * route is public but has the same dependency and error semantics.
 */
@interface AppViewXRpcRoutePack (AgeAssurance)

/** @abstract Starts age assurance for the caller when email, language, and country code are present. */
- (void)handleAgeAssuranceBegin:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns age-assurance configuration without requiring actor authentication. */
- (void)handleAgeAssuranceGetConfig:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns the caller's state for required `countryCode` and optional `regionCode`. */
- (void)handleAgeAssuranceGetState:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;

@end
