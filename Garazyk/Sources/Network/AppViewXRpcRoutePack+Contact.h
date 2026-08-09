// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

/**
 * @abstract Authenticated phone-verification and contact-sync XRPC route handlers.
 * @discussion Each handler scopes contact data to the DID from a validated bearer token. Missing
 * required body fields yield 400; verification-token failures yield 401 where distinguishable;
 * other service failures yield 500. Mutating handlers return an empty JSON object on success.
 */
@interface AppViewXRpcRoutePack (Contact)

/** @abstract Starts phone verification for required `phoneNumber` and returns its verification ID. */
- (void)handleStartPhoneVerification:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Verifies required `phoneNumber` and `code`, returning a contact-import token or 401. */
- (void)handleVerifyPhone:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Imports required `contacts` using a required verification token for the caller. */
- (void)handleImportContacts:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns the authenticated caller's current contact matches. */
- (void)handleGetContactMatches:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Validates a match DID and suppresses that match for the authenticated caller. */
- (void)handleDismissContactMatch:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns the authenticated caller's contact-sync status. */
- (void)handleGetContactSyncStatus:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Deletes all contact data owned by the authenticated caller. */
- (void)handleRemoveContactData:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;

@end
