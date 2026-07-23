// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler.h"

@class JWTMinter;

#import "Security/Space/PDSSpaceScope.h"

NS_ASSUME_NONNULL_BEGIN

BOOL OAuthHandlerScopeIsValid(NSString *scope);

#pragma mark - Shared State (defined in OAuth2Handler.m)
extern NSMutableDictionary *sPendingConsents;
extern NSMutableDictionary *sPasskeyChallenges;
extern dispatch_queue_t sPasskeyChallengeQueue;
extern dispatch_queue_t sAuthGlobalsQueue;
extern dispatch_queue_t sClientMetadataQueue;
extern NSCache *sClientMetadataCache;

extern const NSTimeInterval kPendingConsentTTLSeconds;
extern const NSTimeInterval kPasskeyChallengeTTLSeconds;
extern const NSUInteger kMaxPendingConsents;
extern const NSTimeInterval kClientValidationTimeoutSeconds;
extern NSInteger const kClientValidationTimeoutCode;
extern dispatch_once_t sClientCacheOnceToken;

#pragma mark - Private Interface
@interface OAuth2Handler ()

@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, copy) NSString *serverOrigin;

#pragma mark - Route Handlers
- (void)handleAuthorizeRequest:(HttpRequest *)request
                      response:(HttpResponse *)response;
- (void)handleAuthorizeConfirm:(HttpRequest *)request
                      response:(HttpResponse *)response;
- (void)handleAuthorizeSignIn:(HttpRequest *)request
                     response:(HttpResponse *)response;
- (void)handlePasskeyChallenge:(HttpRequest *)request
                      response:(HttpResponse *)response;
- (void)handlePasskeySignIn:(HttpRequest *)request
                     response:(HttpResponse *)response;
- (void)handleTokenRequest:(HttpRequest *)request
                  response:(HttpResponse *)response;
- (void)handleRevokeRequest:(HttpRequest *)request
                   response:(HttpResponse *)response;
- (void)handleAuthorizationServerMetadata:(HttpRequest *)request
                                 response:(HttpResponse *)response;
- (void)handleProtectedResourceMetadata:(HttpRequest *)request
                               response:(HttpResponse *)response;
- (void)handleJWKS:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handlePARRequest:(HttpRequest *)request
                response:(HttpResponse *)response;
- (void)handleIntrospectRequest:(HttpRequest *)request
                       response:(HttpResponse *)response;
- (void)handleCSSRequest:(HttpRequest *)request
                response:(HttpResponse *)response;
- (void)setCorsHeaders:(HttpResponse *)response
            forRequest:(HttpRequest *)request;

#pragma mark - Client Validation
- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata
                                   error:(NSError **)error;
- (NSDictionary *)getClientPublicKeys:(NSDictionary *)client
                                error:(NSError **)error;
- (BOOL)validateJWTAssertion:(NSString *)assertion
                   withClient:(NSDictionary *)client
                        error:(NSError **)error;
- (nullable NSDictionary *)validatedClientForClientID:(NSString *)clientID
                                                error:(NSError **)error;
- (BOOL)isClientValidationTimeoutError:(NSError *)error;
- (void)setOAuthErrorResponse:(HttpResponse *)response
                       status:(NSInteger)status
                        error:(NSString *)errorCode
             errorDescription:(NSString *)errorDescription;
- (NSDictionary *)sanitizeClientMetadataIfNeeded:(NSDictionary *)validatedClient
                                        clientID:(NSString *)clientID;
- (BOOL)isLoopbackURL:(NSString *)urlString;
- (BOOL)validateRedirectURI:(NSString *)redirectURI
                  forClient:(NSDictionary *)client
                      error:(NSError **)error;
- (void)fetchClientMetadataFromURL:(NSString *)url
                        completion:(void (^)(NSDictionary *_Nullable metadata,
                                             NSError *_Nullable error))completion;
- (NSDictionary *)parseClientMetadataFromInput:(id)clientMetadataInput;

#pragma mark - Consent & Passkey Session Store
- (NSString *)createPendingConsentSessionForDid:(NSString *)did
                                         handle:(NSString *)handle;
- (void)cleanupExpiredPendingConsentsLocked;
- (void)enforcePendingConsentCapacityLocked;
- (NSUInteger)pendingConsentCountForTesting;
- (void)clearPendingConsentsForTesting;
- (void)cleanupExpiredPasskeyChallengesLocked;
- (NSDictionary *)consumePasskeyChallengeForSessionId:(NSString *)sessionId;

#pragma mark - DPoP & Request Origin
- (BOOL)validateDPoPForRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
                 outThumbprint:(NSString **)outThumbprint;
- (void)attachDPoPNonceToResponseIfMissing:(HttpResponse *)response;
- (NSURL *)expectedDPoPURLForRequest:(HttpRequest *)request;
- (NSString *)requestOriginForRequest:(HttpRequest *)request;
- (BOOL)requestShouldTrustForwardedHeaders:(HttpRequest *)request;

#pragma mark - PAR
- (NSDictionary *)consumePARRequestForURI:(NSString *)requestURI
                                 clientID:(NSString *)clientID
                                    error:(NSError **)error;

#pragma mark - Assets & HTML
- (NSString *)assetsPath;
- (NSString *)sharedCSSPath;
- (NSString *)escapeHtml:(NSString *)input;

#pragma mark - Parsing & Helpers
- (NSDictionary *)parseJSONBody:(NSData *)data;
- (NSDictionary *)parseFormUrlEncodedString:(NSString *)input;
- (NSString *)iso8601StringFromDate:(NSDate *)date;
- (NSDate *)dateFromISO8601String:(NSString *)dateString;

#pragma mark - Authorization Page
- (void)serveAuthorizePage:(HttpResponse *)response
                    params:(NSDictionary *)params
                    client:(NSDictionary *)client;

#pragma mark - Crypto Helpers
- (SecKeyRef)createECPublicKeyFromX:(NSData *)xData Y:(NSData *)yData;

@end

NS_ASSUME_NONNULL_END
