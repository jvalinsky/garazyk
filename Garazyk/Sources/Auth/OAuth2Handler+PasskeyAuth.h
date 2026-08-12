// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @category PasskeyAuth
 * @abstract Implements WebAuthn challenge issuance and assertion verification for consent sign-in.
 */
@interface ATProtoOAuth2Handler (PasskeyAuth)
/**
 * @abstract Issues a short-lived WebAuthn challenge bound to a submitted DID.
 * @discussion Validates the JSON body and configured relying-party origin, creates 32 random
 * bytes, and stores the challenge, DID, and expiry in process-local state under
 * sPasskeyChallengeQueue. The JSON success response contains the base64url challenge, opaque
 * session identifier, and relying-party identifier. Malformed input or unavailable randomness or
 * origin is reported in the response.
 * @param request The JSON request containing the DID to bind to the challenge.
 * @param response The JSON challenge or failure response.
 */
- (void)handlePasskeyChallenge:(ATProtoHttpRequest *)request
                      response:(ATProtoHttpResponse *)response;
/**
 * @abstract Verifies a WebAuthn assertion and creates a pending-consent session.
 * @discussion Requires a matching CSRF header and cookie, then atomically consumes the supplied
 * challenge before verifying its DID, bytes, relying-party origin, credential, and signature counter.
 * Consumption is one-time even when verification fails. Success persists the new signature count
 * and returns a process-local pending-consent token; failures are written as JSON responses.
 * @param request The JSON assertion submission with the challenge session identifier and DID.
 * @param response The JSON success or failure response.
 */
- (void)handlePasskeySignIn:(ATProtoHttpRequest *)request
                     response:(ATProtoHttpResponse *)response;
/**
 * @abstract Removes expired or malformed passkey challenge sessions.
 * @warning The caller must already be executing on sPasskeyChallengeQueue.
 */
- (void)cleanupExpiredPasskeyChallengesLocked;
/**
 * @abstract Atomically retrieves and deletes an unexpired passkey challenge session.
 * @discussion Synchronizes with sPasskeyChallengeQueue, removes expired sessions first, and
 * consumes the selected session regardless of whether its later assertion verification succeeds.
 * @param sessionId The opaque challenge session identifier supplied by the client.
 * @return The stored challenge dictionary, or nil when the identifier is empty, unknown, or expired.
 */
- (NSDictionary *)consumePasskeyChallengeForSessionId:(NSString *)sessionId;
@end

NS_ASSUME_NONNULL_END
