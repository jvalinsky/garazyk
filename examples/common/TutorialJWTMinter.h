/*!
 @file TutorialJWTMinter.h

 @abstract ES256 JWT token creation for tutorial examples.

 @discussion Creates and signs JWT tokens using real ECDSA P-256 (ES256).
 This is the educational version of the production JWTMinter in
 Garazyk/Sources/Auth/JWT.h.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class TutorialECDSAKeyPair;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const TutorialJWTErrorDomain;

/*!
 @class TutorialJWTMinter

 @abstract Creates and signs ES256 JWT tokens.
 */
@interface TutorialJWTMinter : NSObject

/*! The issuer claim for minted tokens (e.g., @"did:web:localhost:2583"). */
@property (nonatomic, copy) NSString *issuer;

/*! The signing key pair. Generated automatically if not set. */
@property (nonatomic, strong, nullable) TutorialECDSAKeyPair *keyPair;

/*!
 @method initWithIssuer:

 @abstract Creates a minter with a generated key pair.

 @param issuer The issuer DID (e.g., @"did:web:localhost:2583").
 @return A new minter instance.
 */
- (instancetype)initWithIssuer:(NSString *)issuer;

/*!
 @method mintAccessTokenForDID:handle:scopes:error:

 @abstract Mints an access token with ES256 signing.

 @param did The subject DID.
 @param handle The subject handle.
 @param scopes The granted scopes (e.g., @[@"atproto_repo"]).
 @param error On failure, contains error details.
 @return The signed JWT string, or nil on failure.
 */
- (nullable NSString *)mintAccessTokenForDID:(NSString *)did
                                      handle:(NSString *)handle
                                      scopes:(NSArray<NSString *> *)scopes
                                       error:(NSError **)error;

/*!
 @method mintRefreshTokenForDID:handle:scopes:error:

 @abstract Mints a refresh token with ES256 signing.

 @param did The subject DID.
 @param handle The subject handle.
 @param scopes The granted scopes (e.g., @[@"atproto_refresh"]).
 @param error On failure, contains error details.
 @return The signed JWT string, or nil on failure.
 */
- (nullable NSString *)mintRefreshTokenForDID:(NSString *)did
                                        handle:(NSString *)handle
                                        scopes:(NSArray<NSString *> *)scopes
                                         error:(NSError **)error;

/*!
 @method mintTokenWithPayload:error:

 @abstract Mints a custom JWT with the given payload claims.

 @param payload The claims dictionary to include in the token.
 @param error On failure, contains error details.
 @return The signed JWT string, or nil on failure.
 */
- (nullable NSString *)mintTokenWithPayload:(NSDictionary *)payload
                                      error:(NSError **)error;

/*!
 @method toJWKS

 @abstract Exports the signing key as a JWK Set for verification.

 @return A dictionary representing the JWKS.
 */
- (NSDictionary *)toJWKS;

@end

NS_ASSUME_NONNULL_END
