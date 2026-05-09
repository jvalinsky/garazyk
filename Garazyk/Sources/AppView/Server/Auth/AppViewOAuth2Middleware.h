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
 @enum AppViewOAuth2MiddlewareErrorCode
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
 @method validateDPoPProof:forToken:

 @abstract Validate the DPoP proof for the given token.

 @param request The HTTP request containing the DPoP header.
 @param token   The Bearer token to validate the proof against.

 @return YES if the DPoP proof is valid or not required, NO if invalid.
 */
- (BOOL)validateDPoPProof:(HttpRequest *)request forToken:(NSString *)token;

@end

NS_ASSUME_NONNULL_END
