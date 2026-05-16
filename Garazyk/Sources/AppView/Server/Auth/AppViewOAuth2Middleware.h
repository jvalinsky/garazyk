// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewOAuth2Middleware.h

 @abstract OAuth2/DPoP authentication middleware for the AppView.

 @discussion Extends the existing PDS OAuth2 implementation to the AppView
 side. Validates DPoP proofs and verifies client tokens against the
 issuing PDS. Required for write proxying and proper client auth.

 Reuses existing OAuth2 code from PDS (PDSOAuth2Provider,
 PDSOAuth2TokenIntrospector) where possible.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class AppViewDatabase;
@class HttpRequest;

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const AppViewOAuth2MiddlewareErrorDomain;

/*!
 */
typedef NS_ENUM(NSInteger, AppViewOAuth2MiddlewareErrorCode) {
    AppViewOAuth2ErrorInvalidToken = 1,
    AppViewOAuth2ErrorExpiredToken,
    AppViewOAuth2ErrorInvalidDPoPProof,
    AppViewOAuth2ErrorDPoPKeyMismatch,
    AppViewOAuth2ErrorIntrospectionFailed,
};

/*!
 @class AppViewOAuth2Middleware

 @abstract Validates OAuth2/DPoP tokens for AppView requests.
 */
@interface AppViewOAuth2Middleware : NSObject

/*!
 @method initWithDatabase:masterSecret:

 @abstract Initialize with the database and shared master secret.

 @param database     The AppView database.
 @param masterSecret The shared master secret for verifying PDS-signed JWTs.
 */
- (instancetype)initWithDatabase:(AppViewDatabase *)database
                    masterSecret:(nullable NSString *)masterSecret;

/*!
 @method validateRequest:callerDID:error:

 @abstract Validate the OAuth2/DPoP authentication on the request.

 @param request   The HTTP request to validate.
 @param callerDID Output parameter for the authenticated caller's DID.
 @param error     Output parameter for validation errors.

 @return YES if the request is authenticated, NO otherwise.
 */
- (BOOL)validateRequest:(HttpRequest *)request
              callerDID:(NSString *_Nullable *_Nullable)callerDID
                   error:(NSError **)error;

/*!
 @method extractBearerToken:

 @abstract Extract the Bearer token from the Authorization header.

 @param request The HTTP request.

 @return The Bearer token string, or nil if not present.
 */
- (nullable NSString *)extractBearerToken:(HttpRequest *)request;

/*!
 @method validateDPoPProof:token:tokenJkt:outThumbprint:error:

 @abstract Validate the DPoP proof and enforce cnf.jkt binding.

 @discussion Uses the canonical AuthCryptoDPoP verifier (RFC 9449) to
 verify the proof, then checks that the proof key thumbprint matches
 the access token's cnf.jkt claim. Rejects DPoP-bound tokens sent
 without a proof, and proofs that don't match the token binding.

 @param request       The HTTP request containing the DPoP header.
 @param token         The Bearer token string.
 @param tokenJkt      The cnf.jkt from the access token (nil if not DPoP-bound).
 @param outThumbprint Output parameter for the proof's JWK thumbprint.
 @param error         Output parameter for validation errors.

 @return YES if the DPoP proof is valid and binding matches, NO otherwise.
 */
- (BOOL)validateDPoPProof:(HttpRequest *)request
                    token:(NSString *)token
                tokenJkt:(nullable NSString *)tokenJkt
           outThumbprint:(NSString *_Nullable *_Nullable)outThumbprint
                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
