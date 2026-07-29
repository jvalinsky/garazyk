// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @category ConsentStore
 * @abstract Manages the bounded, process-local pending-consent session store.
 */
@interface OAuth2Handler (ConsentStore)
/**
 * @abstract Creates an opaque, bounded pending-consent session for an authenticated DID.
 * @discussion The session is process-local state protected by sAuthGlobalsQueue and expires after
 * the configured TTL. Creation removes expired entries and evicts the oldest at capacity. An empty
 * handle becomes the DID; the returned token is a bearer credential for consent submission.
 * @param did The authenticated nonempty DID to bind to the session.
 * @param handle The authenticated handle to retain for the authorization response, or an empty
 * string to use the DID.
 * @return A newly generated session token, or nil when did is empty.
 */
- (NSString *)createPendingConsentSessionForDid:(NSString *)did
                                         handle:(NSString *)handle;
/**
 * @abstract Removes expired or malformed pending-consent sessions.
 * @warning The caller must already be executing on sAuthGlobalsQueue.
 */
- (void)cleanupExpiredPendingConsentsLocked;
/**
 * @abstract Evicts the oldest pending-consent sessions until the configured capacity allows one more.
 * @warning The caller must already be executing on sAuthGlobalsQueue.
 */
- (void)enforcePendingConsentCapacityLocked;
/**
 * @abstract Returns the current pending-consent count for test assertions.
 * @discussion Synchronizes with sAuthGlobalsQueue and removes expired sessions before counting.
 * @return The number of unexpired process-local pending-consent sessions.
 */
- (NSUInteger)pendingConsentCountForTesting;
/**
 * @abstract Removes every pending-consent session for test isolation.
 * @discussion Synchronizes with sAuthGlobalsQueue. This destroys process-local authentication
 * state and must not be used by request handling.
 */
- (void)clearPendingConsentsForTesting;
@end

NS_ASSUME_NONNULL_END
