// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler.h"

@class ATProtoJWTMinter;

#import "Security/Space/PDSSpaceScope.h"

NS_ASSUME_NONNULL_BEGIN

/** @abstract Returns whether scope is valid under this authorization server's supported scope policy. */
BOOL OAuthHandlerScopeIsValid(NSString *scope);

#pragma mark - Shared State (defined in OAuth2Handler.m)
/** @abstract Pending-consent state, accessed only while holding sAuthGlobalsQueue. */
extern NSMutableDictionary *sPendingConsents;
/** @abstract Passkey challenges, accessed only while holding sPasskeyChallengeQueue. */
extern NSMutableDictionary *sPasskeyChallenges;
/** @abstract Serial queue protecting sPasskeyChallenges and its expiry cleanup. */
extern dispatch_queue_t sPasskeyChallengeQueue;
/** @abstract Serial queue protecting shared authorization state, including pending consents. */
extern dispatch_queue_t sAuthGlobalsQueue;
/** @abstract Serial queue protecting dynamic-client metadata cache initialization and updates. */
extern dispatch_queue_t sClientMetadataQueue;
/** @abstract Cache of previously validated client metadata; never treat entries as raw client input. */
extern NSCache *sClientMetadataCache;

extern const NSTimeInterval kPendingConsentTTLSeconds;
extern const NSTimeInterval kPasskeyChallengeTTLSeconds;
extern const NSUInteger kMaxPendingConsents;
extern const NSTimeInterval kClientValidationTimeoutSeconds;
extern NSInteger const kClientValidationTimeoutCode;
extern dispatch_once_t sClientCacheOnceToken;

#pragma mark - Private Interface
/**
 * @abstract Declares OAuth2Handler's private endpoint and security helpers.
 * @discussion Route methods validate untrusted HTTP input and write protocol responses. Shared
 * session state is confined to the queues documented above.
 */
@interface OAuth2Handler ()

/** @abstract Database used to resolve accounts, consents, and token state for OAuth flows. */
@property (nonatomic, strong) PDSDatabase *database;
/** @abstract Canonical externally visible server origin used in OAuth and DPoP comparisons. */
@property (nonatomic, copy) NSString *serverOrigin;

/** @abstract Validates a passkey challenge request and stores a short-lived challenge session. */
- (void)handlePasskeyChallenge:(HttpRequest *)request
                      response:(HttpResponse *)response;
/** @abstract Verifies a one-time passkey assertion and continues the associated sign-in flow. */
- (void)handlePasskeySignIn:(HttpRequest *)request
                     response:(HttpResponse *)response;
/** @abstract Validates a token grant and emits no-store OAuth token or error response data. */
- (void)handleTokenRequest:(HttpRequest *)request
                  response:(HttpResponse *)response;
/** @abstract Authenticates a revocation request and invalidates the specified token when permitted. */
- (void)handleRevokeRequest:(HttpRequest *)request
                   response:(HttpResponse *)response;
/** @abstract Emits authorization-server metadata derived from the configured public origin. */
- (void)handleAuthorizationServerMetadata:(HttpRequest *)request
                                 response:(HttpResponse *)response;
/** @abstract Emits protected-resource metadata for DPoP-aware resource clients. */
- (void)handleProtectedResourceMetadata:(HttpRequest *)request
                               response:(HttpResponse *)response;
/** @abstract Emits the public JWK set used by this authorization server. */
- (void)handleJWKS:(HttpRequest *)request response:(HttpResponse *)response;
/** @abstract Validates and stores a pushed authorization request before returning its request URI. */
- (void)handlePARRequest:(HttpRequest *)request
                response:(HttpResponse *)response;
/** @abstract Authenticates an introspection request and reports token activity without exposing secrets. */
- (void)handleIntrospectRequest:(HttpRequest *)request
                       response:(HttpResponse *)response;
/** @abstract Adds CORS headers only when the request origin matches configured allowed origins. */
- (void)setCorsHeaders:(HttpResponse *)response
            forRequest:(HttpRequest *)request;

#pragma mark - Client Validation
/** @abstract Validates and normalizes dynamic client metadata before it is trusted or cached. */
- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata
                                   error:(NSError **)error;
/** @abstract Extracts usable public verification keys from validated client metadata. */
- (NSDictionary *)getClientPublicKeys:(NSDictionary *)client
                                error:(NSError **)error;
/** @abstract Verifies a private-key JWT assertion against validated client metadata and registered keys. */
- (BOOL)validateJWTAssertion:(NSString *)assertion
                   withClient:(NSDictionary *)client
                        error:(NSError **)error;
/** @abstract Resolves client metadata synchronously with the configured validation timeout. */
- (nullable NSDictionary *)validatedClientForClientID:(NSString *)clientID
                                                error:(NSError **)error;
/** @abstract Reports whether an error represents the synchronous client-validation timeout. */
- (BOOL)isClientValidationTimeoutError:(NSError *)error;
/** @abstract Writes a protocol-safe OAuth error response from the supplied status and OAuth fields. */
- (void)setOAuthErrorResponse:(HttpResponse *)response
                       status:(NSInteger)status
                        error:(NSString *)errorCode
             errorDescription:(NSString *)errorDescription;
/** @abstract Removes client metadata fields that must not be reflected to the caller. */
- (NSDictionary *)sanitizeClientMetadataIfNeeded:(NSDictionary *)validatedClient
                                        clientID:(NSString *)clientID;
/** @abstract Returns whether a URL uses an IPv4 or IPv6 loopback host. */
- (BOOL)isLoopbackURL:(NSString *)urlString;
/** @abstract Confirms a redirect URI is registered and permitted for the validated client. */
- (BOOL)validateRedirectURI:(NSString *)redirectURI
                  forClient:(NSDictionary *)client
                      error:(NSError **)error;

#pragma mark - Consent & Passkey Session Store
/** @abstract Creates a bounded, expiring consent session while holding the authorization-state lock. */
- (NSString *)createPendingConsentSessionForDid:(NSString *)did
                                         handle:(NSString *)handle;
/** @abstract Removes expired consent sessions; callers must hold sAuthGlobalsQueue. */
- (void)cleanupExpiredPendingConsentsLocked;
/** @abstract Evicts pending consent sessions to the configured capacity; callers must hold sAuthGlobalsQueue. */
- (void)enforcePendingConsentCapacityLocked;
/** @abstract Returns the queue-synchronized pending-consent count for tests. */
- (NSUInteger)pendingConsentCountForTesting;
/** @abstract Removes every pending-consent session for test isolation. */
- (void)clearPendingConsentsForTesting;
/** @abstract Removes expired passkey challenges; callers must hold sPasskeyChallengeQueue. */
- (void)cleanupExpiredPasskeyChallengesLocked;
/** @abstract Atomically returns and deletes a nonexpired passkey challenge session. */
- (NSDictionary *)consumePasskeyChallengeForSessionId:(NSString *)sessionId;

#pragma mark - DPoP & Request Origin
/**
 * @abstract Verifies the DPoP proof binding for a request and writes challenge responses on failure.
 * @discussion Uses the canonical expected URL and returns the validated key thumbprint only after
 * method, URL, proof, and replay protections succeed.
 */
- (BOOL)validateDPoPForRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
                 outThumbprint:(NSString * _Nullable * _Nullable)outThumbprint;
/** @abstract Adds a fresh DPoP nonce only when the response does not already carry one. */
- (void)attachDPoPNonceToResponseIfMissing:(HttpResponse *)response;
/** @abstract Builds the canonical URL used for DPoP htu validation. */
- (NSURL *)expectedDPoPURLForRequest:(HttpRequest *)request;
/** @abstract Returns the canonical request origin for OAuth audience and origin comparisons. */
- (NSString *)requestOriginForRequest:(HttpRequest *)request;
/** @abstract Returns whether forwarded headers may be trusted for this request's origin derivation. */
- (BOOL)requestShouldTrustForwardedHeaders:(HttpRequest *)request;

#pragma mark - PAR
/** @abstract Atomically consumes a pushed authorization request only for its bound client identifier. */
- (NSDictionary *)consumePARRequestForURI:(NSString *)requestURI
                                 clientID:(NSString *)clientID
                                    error:(NSError **)error;

#pragma mark - Parsing & Helpers
/** @abstract Parses a nonempty JSON request body into a dictionary, or nil for invalid input. */
- (NSDictionary *)parseJSONBody:(NSData *)data;
/** @abstract Parses application/x-www-form-urlencoded input into decoded key/value pairs. */
- (NSDictionary *)parseFormUrlEncodedString:(NSString *)input;
/** @abstract Formats a date using the AT Protocol ISO-8601 representation. */
- (NSString *)iso8601StringFromDate:(NSDate *)date;
/** @abstract Parses an AT Protocol ISO-8601 date string, or nil if it is invalid. */
- (NSDate *)dateFromISO8601String:(NSString *)dateString;

#pragma mark - Crypto Helpers
/** @abstract Creates a retained P-256 public key from JWK affine coordinates, or nil if invalid. */
- (SecKeyRef)createECPublicKeyFromX:(NSData *)xData Y:(NSData *)yData;

@end

NS_ASSUME_NONNULL_END
