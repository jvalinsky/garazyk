// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

/**
 * @abstract Actor XRPC route handlers.
 * @discussion Public profile and search reads validate their required query fields where
 * applicable and return 500 for actor-service failures. Preference endpoints authenticate the
 * caller, validate required JSON bodies, and return 400 for malformed input or 500 on storage
 * failure. Paginated actor search clamps `limit` to 1...100.
 */
@interface AppViewXRpcRoutePack (Actor)

/** @abstract Returns the profile for required `actor`, or 404 when the actor is absent. */
- (void)handleGetProfile:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns profiles for required comma-separated `actors`. */
- (void)handleGetProfiles:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Searches actors using optional `q` or `term`, with cursor pagination. */
- (void)handleSearchActors:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns typeahead actors for optional `q` or `term`, without cursor pagination. */
- (void)handleSearchActorsTypeahead:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns preferences belonging to the authenticated actor. */
- (void)handleGetPreferences:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Validates a JSON `preferences` array and replaces the authenticated actor's preferences. */
- (void)handlePutPreferences:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Returns an empty suggestions response; no service state is read or changed. */
- (void)handleGetSuggestions:(HttpRequest *)request response:(HttpResponse *)response;

@end
