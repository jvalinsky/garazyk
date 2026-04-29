/*!
 @file TutorialJWTVerifier.h

 @abstract ES256 JWT token verification for tutorial examples.

 @discussion Verifies JWT tokens signed with ES256 (ECDSA P-256 with SHA-256).
 This is the educational version of the production JWTVerifier in
 Garazyk/Sources/Auth/JWT.h and AuthVerifier in
 Garazyk/Sources/Auth/Verifier/AuthVerifier.h.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class TutorialECDSAKeyPair;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class TutorialJWTVerifier

 @abstract Verifies ES256 JWT tokens.
 */
@interface TutorialJWTVerifier : NSObject

/*! The expected issuer claim. */
@property (nonatomic, copy) NSString *expectedIssuer;

/*! The signing key pair used for verification. */
@property (nonatomic, strong, nullable) TutorialECDSAKeyPair *keyPair;

/*!
 @method initWithIssuer:keyPair:

 @abstract Creates a verifier with a known key pair.

 @param issuer The expected issuer DID.
 @param keyPair The key pair whose public key is used for verification.
 @return A new verifier instance.
 */
- (instancetype)initWithIssuer:(NSString *)issuer
                       keyPair:(TutorialECDSAKeyPair *)keyPair;

/*!
 @method verifyToken:error:

 @abstract Verifies a JWT token's signature and claims.

 @param token The JWT token string (header.payload.signature).
 @param error On failure, contains error details.
 @return The verified payload dictionary, or nil if verification failed.
 */
- (nullable NSDictionary *)verifyToken:(NSString *)token
                                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
