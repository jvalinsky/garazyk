// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @header JWT.h
 
 @abstract JWT (JSON Web Token) handling for ATProto authentication.
 
 @discussion This header defines classes for creating, parsing, signing,
 and verifying JWT tokens. It includes JWTHeader, JWTPayload, JWT,
 JWTVerifier, and JWTMinter classes.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

extern NSString * const JWTErrorDomain;

/**
 * @abstract Defines the PDSKeyManager protocol contract.
 */
@protocol PDSKeyManager;
@protocol PDSActorKeyManager;


/*!
 
 @abstract Error codes for JWT operations.
 
 @constant JWTErrorInvalidFormat The token format is invalid.
 @constant JWTErrorInvalidHeader The JWT header is malformed.
 @constant JWTErrorInvalidPayload The JWT payload is malformed.
 @constant JWTErrorInvalidSignature The signature is invalid.
 @constant JWTErrorTokenExpired The token has expired.
 @constant JWTErrorTokenNotYetValid The token is not yet valid.
 @constant JWTErrorInvalidIssuer The issuer claim is invalid.
 @constant JWTErrorInvalidSubject The subject claim is invalid.
 @constant JWTErrorInvalidAudience The audience claim is invalid.
 @constant JWTErrorMissingRequiredClaim A required claim is missing.
 @constant JWTErrorEncodingFailed Base64URL encoding failed.
 @constant JWTErrorDecodingFailed Base64URL decoding failed.
 @constant JWTErrorVerificationFailed Signature verification failed.
 @constant JWTErrorSigningFailed Token signing failed.
 @constant JWTErrorNoPublicKey No public key configured for verification.
 @constant JWTErrorInvalidAlgorithm Signing algorithm not allowed.
 */
/**
 * @abstract Defines JWTError values exposed by this API.
 */
typedef NS_ENUM(NSInteger, JWTError) {
    /** The token does not contain the expected compact JWT parts. */
    JWTErrorInvalidFormat = 1000,
    /** The JWT header is malformed. */
    JWTErrorInvalidHeader,
    /** The JWT payload is malformed. */
    JWTErrorInvalidPayload,
    /** The JWT signature is invalid. */
    JWTErrorInvalidSignature,
    /** The token has expired. */
    JWTErrorTokenExpired,
    /** The token is not valid yet. */
    JWTErrorTokenNotYetValid,
    /** The issuer claim is invalid. */
    JWTErrorInvalidIssuer,
    /** The subject claim is invalid. */
    JWTErrorInvalidSubject,
    /** The audience claim is invalid. */
    JWTErrorInvalidAudience,
    /** The signing algorithm is not allowed. */
    JWTErrorInvalidAlgorithm,
    /** A required claim is missing. */
    JWTErrorMissingRequiredClaim,
    /** Base64URL encoding failed. */
    JWTErrorEncodingFailed,
    /** Base64URL decoding failed. */
    JWTErrorDecodingFailed,
    /** Signature verification failed. */
    JWTErrorVerificationFailed,
    /** Token signing failed. */
    JWTErrorSigningFailed,
    /** No public key is configured for verification. */
    JWTErrorNoPublicKey
};

/*!
 @class JWTHeader
 
 @abstract Represents the header portion of a JWT.
 
 @discussion The JWT header contains metadata about the token including
 the algorithm used for signing and the key identifier.
 */
@interface JWTHeader : NSObject

/*! The signing algorithm (e.g., "RS256", "ES256"). */
@property (nonatomic, copy, nullable) NSString *alg;

/*! The token type (typically "JWT"). */
@property (nonatomic, copy, nullable) NSString *typ;

/*! The key identifier for selecting the signing key. */
@property (nonatomic, copy, nullable) NSString *kid;

/*! The content type for nested tokens. */
@property (nonatomic, copy, nullable) NSString *cty;

/*!
 @method headerFromDictionary:error:
 
 @abstract Creates a header from a dictionary.
 
 @param dictionary The header dictionary.
 @param error On return, contains an error if parsing failed.
 @return A new JWTHeader instance.
 */
+ (nullable instancetype)headerFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;

/*!
 @method toDictionary
 
 @abstract Converts the header to a dictionary.
 
 @return A dictionary representation of the header.
 */
- (NSDictionary *)toDictionary;

@end

/*!
 @class JWTPayload
 
 @abstract Represents the claims portion of a JWT.
 
 @discussion The JWT payload contains the claims about the token subject,
 including standard claims (iss, sub, aud, exp, iat, nbf) and ATProto-specific
 claims (did, handle, scope).
 */
@interface JWTPayload : NSObject

/*! The issuer (who created the token). */
@property (nonatomic, copy, nullable) NSString *iss;

/*! The subject (who the token is about, typically a DID). */
@property (nonatomic, copy, nullable) NSString *sub;

/*! The audience (who the token is intended for). */
@property (nonatomic, copy, nullable) NSString *aud;

/*! Expiration time (Unix timestamp). */
@property (nonatomic, strong, nullable) NSDate *exp;

/*! Issued at time (Unix timestamp). */
@property (nonatomic, strong, nullable) NSDate *iat;

/*! Not before time (Unix timestamp). */
@property (nonatomic, strong, nullable) NSDate *nbf;

/*! Unique token identifier. */
@property (nonatomic, copy, nullable) NSString *jti;

/*! Session identifier (ATProto-specific). */
@property (nonatomic, copy, nullable) NSString *sid;

/*! The DID of the token subject (ATProto-specific). */
@property (nonatomic, copy, nullable) NSString *did;

/*! The handle of the token subject (ATProto-specific). */
@property (nonatomic, copy, nullable) NSString *handle;

/*! The OAuth scope granted (ATProto-specific). */
@property (nonatomic, copy, nullable) NSString *scope;

/*! The lexicon method for Service Auth tokens (ATProto-specific). */
@property (nonatomic, copy, nullable) NSString *lxm;

/*! The token use (typically "access" or "refresh"). */
@property (nonatomic, copy, nullable) NSString *token_use;

/*! Confirmation claim (e.g., for DPoP jkt). */
@property (nonatomic, copy, nullable) NSDictionary *cnf;

/*!
 @method payloadFromDictionary:error:
 
 @abstract Creates a payload from a dictionary.
 
 @param dictionary The claims dictionary.
 @param error On return, contains an error if parsing failed.
 @return A new JWTPayload instance.
 */
+ (nullable instancetype)payloadFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;

/*!
 @method toDictionary
 
 @abstract Converts the payload to a dictionary.
 
 @return A dictionary representation of the payload.
 */
- (NSDictionary *)toDictionary;

@end

/*!
 @class JWT
 
 @abstract Represents a complete JWT token.
 
 @discussion JWT provides methods for parsing, encoding, and accessing
 JWT tokens. It combines header, payload, and signature components.
 
 @code
 // Parse a JWT token
 JWT *jwt = [JWT jwtWithToken:tokenString error:nil];
 
 // Access claims
 NSString *issuer = jwt.payload.iss;
 NSString *subject = jwt.payload.sub;
 
 // Get encoded form
 NSString *encoded = [jwt encodedToken];
 @endcode
 */
/**
 * @abstract Declares the JWT public API.
 */
@interface JWT : NSObject

/*! The decoded header. */
@property (nonatomic, strong, readonly) JWTHeader *header;

/*! The decoded payload. */
@property (nonatomic, strong, readonly) JWTPayload *payload;

/*! The base64URL-encoded header string. */
@property (nonatomic, copy, readonly) NSString *rawHeader;

/*! The base64URL-encoded payload string. */
@property (nonatomic, copy, readonly) NSString *rawPayload;

/*! The raw signature bytes (not base64URL encoded). */
@property (nonatomic, copy, readonly) NSString *signature;

/*! The base64URL-encoded signature. */
@property (nonatomic, copy, readonly) NSString *encodedSignature;

/*!
 @method jwtWithToken:error:
 
 @abstract Parses a JWT token string.
 
 @param token The JWT token string (three base64URL parts separated by dots).
 @param error On return, contains an error if parsing failed.
 @return A new JWT instance, or nil on failure.
 */
+ (nullable instancetype)jwtWithToken:(NSString *)token error:(NSError **)error;

/*!
 @method jwtWithHeader:payload:signature:error:
 
 @abstract Creates a JWT from components.
 
 @param header The JWT header.
 @param payload The JWT payload.
 @param signature The signature (base64URL encoded).
 @param error On return, contains an error if creation failed.
 @return A new JWT instance.
 */
/**
 * @abstract Performs the jwtWithHeader operation.
 */
+ (nullable instancetype)jwtWithHeader:(JWTHeader *)header
                               payload:(JWTPayload *)payload
                             signature:(NSString *)signature
                                  error:(NSError **)error;

/*!
 @method base64URLEncodeData:error:
 
 @abstract Base64URL-encodes data.
 
 @param data The data to encode.
 @param error On return, contains an error if encoding failed.
 @return The base64URL-encoded string.
 */
+ (NSString *)base64URLEncodeData:(NSData *)data error:(NSError **)error;

/*!
 @method base64URLDecode:error:
 
 @abstract Base64URL-decodes a string.
 
 @param string The Base64URL string to decode.
 @param error On return, contains an error if decoding failed.
 @return The decoded data.
 */
+ (nullable NSData *)base64URLDecode:(NSString *)string error:(NSError **)error;

/*!
 @method encodedToken
 
 @abstract Returns the complete encoded token.
 
 @return The JWT token string (header.payload.signature).
 */
- (NSString *)encodedToken;

/*!
 @method signingInput
 
 @abstract Returns the signing input (header.payload).
 
 @return The string to be signed.
 */
- (NSString *)signingInput;

@end

/*!
 @class JWTVerifier
 
 @abstract Verifies JWT tokens.
 
 @discussion JWTVerifier validates JWT signatures and claims including
 issuer, audience, and expiration.
 */
@interface JWTVerifier : NSObject

/*! The expected issuer claim value. */
@property (nonatomic, copy) NSString *expectedIssuer;

/*! The expected audience claim value. */
@property (nonatomic, copy) NSString *expectedAudience;

/*! The allowed signing algorithms. */
@property (nonatomic, copy) NSArray<NSString *> *allowedAlgorithms;

/*! Clock offset for time-based validation. */
@property (nonatomic, strong) NSDate *clockOffset;

/*! Public key for verification. */
@property (nonatomic, strong, nullable) NSData *publicKey;

/*! Optional key rotation manager for verifying with multiple keys. */
@property (nonatomic, strong, nullable) id<PDSKeyManager> keyManager;

/*! Whether tokens without subject claims are allowed. */
@property (nonatomic, assign) BOOL allowMissingSubject;

/*!
 @method verifyJWT:error:
 
 @abstract Verifies a JWT's signature and claims.
 
 @param jwt The JWT to verify.
 @param error On return, contains an error if verification failed.
 @return YES if the token is valid, NO otherwise.
 */
- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error;

/*!
 @method validateClaims:ofJWT:error:
 
 @abstract Validates specific claims of a JWT.
 
 @param payload The payload to validate.
 @param jwt The JWT containing the payload.
 @param error On return, contains an error if validation failed.
 @return YES if claims are valid, NO otherwise.
 */
- (BOOL)validateClaims:(JWTPayload *)payload ofJWT:(JWT *)jwt error:(NSError **)error;

@end

/*!
 @class JWTMinter
 
 @abstract Creates and signs JWT tokens.
 
 @discussion JWTMinter handles minting access tokens and refresh tokens
 with proper claims and signatures.
 */
@protocol PDSKeyManager;

@interface JWTMinter : NSObject

/*! The issuer claim for minted tokens. */
@property (nonatomic, copy) NSString *issuer;

/*! The audience claim for minted tokens (e.g., the PDS DID). */
@property (nonatomic, copy, nullable) NSString *audience;

/*! The signing algorithm (e.g., "RS256", "ES256"). */
@property (nonatomic, copy) NSString *signingAlgorithm;

/*! Default expiration time for tokens in seconds. */
@property (nonatomic, assign) NSTimeInterval defaultExpiration;

/*! The private key for signing (PEM format). */
@property (nonatomic, strong, nullable) NSData *privateKey;

/*! The public key for verification. */
@property (nonatomic, strong, nullable) NSData *publicKey;

/*! Optional key rotation manager for signing with rotated keys. */
@property (nonatomic, strong, nullable) id<PDSKeyManager> keyManager;

/*!
 @method signPayload:keyManager:error:
 
 @abstract Signs a payload using a key manager.
 
 @param payload The payload dictionary to sign.
 @param keyManager The key manager to use for signing.
 @param error On return, contains an error if signing failed.
 @return The signed JWT string.
 */
- (NSString *)signPayload:(NSDictionary *)payload keyManager:(id<PDSKeyManager>)keyManager error:(NSError **)error;

/*!
 @method signPayload:actorKeyManager:error:
 
 @abstract Signs a payload using an actor key manager.
 
 @param payload The payload dictionary to sign.
 @param keyManager The actor key manager to use for signing.
 @param error On return, contains an error if signing failed.
 @return The signed JWT string.
 */
- (NSString *)signPayload:(NSDictionary *)payload actorKeyManager:(id<PDSActorKeyManager>)keyManager error:(NSError **)error;


/*!
 @method signPayload:error:
 
 @abstract Signs a payload and returns a JWT string.
 
 @param payload The payload dictionary to sign.
 @param error On return, contains an error if signing failed.
 @return The signed JWT string.
 */
- (NSString *)signPayload:(NSDictionary *)payload error:(NSError **)error;

/*!
 @method mintAccessTokenForDID:handle:scopes:error:
 
 @abstract Mints an access token for a user.
 
 @param did The user's DID.
 @param handle The user's handle.
 @param scopes The granted scopes.
 @param error On return, contains an error if minting failed.
 @return A new access token JWT.
 */
/**
 * @abstract Performs the mintAccessTokenForDID operation.
 */
- (JWT *)mintAccessTokenForDID:(NSString *)did
                        handle:(NSString *)handle
                        scopes:(NSArray<NSString *> *)scopes
                     sessionID:(nullable NSString *)sid
             dpopKeyThumbprint:(nullable NSString *)jkt
                           error:(NSError **)error;

/*!
 @method mintAccessTokenForDID:handle:scopes:error:

 @abstract Mints an access token without a DPoP key thumbprint.
 */
- (JWT *)mintAccessTokenForDID:(NSString *)did
                        handle:(NSString *)handle
                        scopes:(NSArray<NSString *> *)scopes
                           error:(NSError **)error;

/*!
 @method mintRefreshTokenForDID:handle:scopes:error:
 
 @abstract Mints a refresh token for a user.
 
 @param did The user's DID.
 @param handle The user's handle.
 @param scopes The granted scopes.
 @param error On return, contains an error if minting failed.
 @return A new refresh token JWT.
 */
/**
 * @abstract Performs the mintRefreshTokenForDID operation.
 */
- (JWT *)mintRefreshTokenForDID:(NSString *)did
                         handle:(NSString *)handle
                         scopes:(NSArray<NSString *> *)scopes
                           error:(NSError **)error;

/*!
 @method mintServiceAuthJWTForDID:aud:lxm:actorKeyManager:error:
 
 @abstract Mints a service-to-service auth JWT per AT Protocol spec.
 
 @discussion Creates a short-lived JWT signed with the user's repo signing
 key. Per the AT Protocol XRPC spec, service auth JWTs must have:
 - iss: user's DID (the requesting account)
 - aud: target service DID (optionally with service fragment)
 - lxm: lexicon method NSID
 - iat: issued-at timestamp
 - exp: expiration (iat + 60 seconds)
 - jti: random 16-hex nonce for replay prevention
 - Header: { typ: "JWT", alg: "ES256K" }
 
 @param userDID The DID of the requesting user (becomes iss claim).
 @param audienceDID The DID of the target service (becomes aud claim).
 @param methodNSID The lexicon method NSID (becomes lxm claim).
 @param actorKeyManager The user's signing key manager for ES256K signing.
 @param error On return, contains an error if minting failed.
 @return The signed JWT string, or nil on failure.
 */
/**
 * @abstract Performs the mintServiceAuthJWTForDID operation.
 */
- (nullable NSString *)mintServiceAuthJWTForDID:(NSString *)userDID
                                            aud:(NSString *)audienceDID
                                            lxm:(NSString *)methodNSID
                                actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager
                                           error:(NSError **)error;

/*!
 @method toJWKS
 
 @abstract Exports the configured keys as a JWK Set.
 
 @return A dictionary representing the JWKS.
 */
- (NSDictionary *)toJWKS;

@end

NS_ASSUME_NONNULL_END
