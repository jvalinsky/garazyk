/**
 * @file JWT.h
 * @brief Implements JSON Web Token (JWT) handling for ATProto PDS authentication.
 *
 * This header provides classes for JWT creation, parsing, signing, and verification.
 * It defines the JWT header and payload structures, token representation, minting,
 * and validation for secure authentication token handling.
 *
 * @note This implementation supports JWT-based access tokens and refresh tokens
 * as specified in RFC 7519, with extensions for ATProto identity claims.
 * @see Session.h
 * @see OAuth2.h
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class KeyRotationManager;

/**
 * @brief Error domain for JWT-related errors.
 */
extern NSString * const JWTErrorDomain;

/**
 * @brief Error codes for JWT operations.
 */
typedef NS_ENUM(NSInteger, JWTError) {
    /** The token format is invalid or does not contain three parts. */
    JWTErrorInvalidFormat = 1000,
    /** The JWT header is invalid or malformed. */
    JWTErrorInvalidHeader,
    /** The JWT payload is invalid or malformed. */
    JWTErrorInvalidPayload,
    /** The signature verification failed. */
    JWTErrorInvalidSignature,
    /** The token has expired. */
    JWTErrorTokenExpired,
    /** The token is not yet valid (nbf claim in future). */
    JWTErrorTokenNotYetValid,
    /** The issuer claim does not match expected value. */
    JWTErrorInvalidIssuer,
    /** The subject claim does not match expected value. */
    JWTErrorInvalidSubject,
    /** The audience claim does not match expected value. */
    JWTErrorInvalidAudience,
    /** A required claim is missing from the payload. */
    JWTErrorMissingRequiredClaim,
    /** Encoding the token failed. */
    JWTErrorEncodingFailed,
    /** Decoding the token failed. */
    JWTErrorDecodingFailed,
    /** Signature verification failed. */
    JWTErrorVerificationFailed,
    /** Signing the token failed. */
    JWTErrorSigningFailed
};

/**
 * @brief Represents the header portion of a JWT.
 *
 * JWTHeader contains metadata about the token, including the algorithm used
 * for signing, the key identifier, and content type information.
 */
@interface JWTHeader : NSObject

/** The algorithm used to sign the token (e.g., "RS256", "ES256"). */
@property (nonatomic, copy, nullable) NSString *alg;

/** The type of token (typically "JWT"). */
@property (nonatomic, copy, nullable) NSString *typ;

/** The key identifier used for signing. */
@property (nonatomic, copy, nullable) NSString *kid;

/** The content type, if specified. */
@property (nonatomic, copy, nullable) NSString *cty;

/**
 * @brief Creates a header from a dictionary representation.
 *
 * @param dictionary The dictionary containing header parameters.
 * @param error On return, contains an error if parsing fails.
 * @return The parsed header, or nil if parsing failed.
 */
+ (nullable instancetype)headerFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;

/**
 * @brief Converts the header to a dictionary representation.
 *
 * @return A dictionary suitable for JSON encoding.
 */
- (NSDictionary *)toDictionary;

@end

/**
 * @brief Represents the payload portion of a JWT.
 *
 * JWTPayload contains the claims of the token, including standard claims
 * (iss, sub, aud, exp, iat, nbf, jti) and ATProto-specific claims (did, handle, scope).
 */
@interface JWTPayload : NSObject

/** The issuer of the token. */
@property (nonatomic, copy, nullable) NSString *iss;

/** The subject (typically the user's DID). */
@property (nonatomic, copy, nullable) NSString *sub;

/** The intended audience for the token. */
@property (nonatomic, copy, nullable) NSString *aud;

/** The expiration time of the token. */
@property (nonatomic, strong, nullable) NSDate *exp;

/** The time at which the token was issued. */
@property (nonatomic, strong, nullable) NSDate *iat;

/** The time before which the token is not valid. */
@property (nonatomic, strong, nullable) NSDate *nbf;

/** Unique identifier for the token. */
@property (nonatomic, copy, nullable) NSString *jti;

/** The user's Decentralized Identifier. */
@property (nonatomic, copy, nullable) NSString *did;

/** The user's handle. */
@property (nonatomic, copy, nullable) NSString *handle;

/** The OAuth 2.0 scope granted to the token. */
@property (nonatomic, copy, nullable) NSString *scope;

/**
 * @brief Creates a payload from a dictionary representation.
 *
 * @param dictionary The dictionary containing claim values.
 * @param error On return, contains an error if parsing fails.
 * @return The parsed payload, or nil if parsing failed.
 */
+ (nullable instancetype)payloadFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;

/**
 * @brief Converts the payload to a dictionary representation.
 *
 * @return A dictionary suitable for JSON encoding.
 */
- (NSDictionary *)toDictionary;

@end

/**
 * @brief Represents a complete JWT with header, payload, and signature.
 *
 * JWT encapsulates all three parts of a JSON Web Token, providing methods
 * for encoding, accessing components, and generating the signing input.
 */
@interface JWT : NSObject

/** The parsed header object. */
@property (nonatomic, strong, readonly) JWTHeader *header;

/** The parsed payload object. */
@property (nonatomic, strong, readonly) JWTPayload *payload;

/** The raw base64url-encoded header string. */
@property (nonatomic, copy, readonly) NSString *rawHeader;

/** The raw base64url-encoded payload string. */
@property (nonatomic, copy, readonly) NSString *rawPayload;

/** The raw signature bytes. */
@property (nonatomic, copy, readonly) NSString *signature;

/** The base64url-encoded signature string. */
@property (nonatomic, copy, readonly) NSString *encodedSignature;

/**
 * @brief Parses a JWT from its encoded string representation.
 *
 * @param token The base64url-encoded JWT string.
 * @param error On return, contains an error if parsing fails.
 * @return The parsed JWT, or nil if parsing failed.
 */
+ (nullable instancetype)jwtWithToken:(NSString *)token error:(NSError **)error;

/**
 * @brief Constructs a JWT from its components.
 *
 * @param header The JWT header.
 * @param payload The JWT payload.
 * @param signature The signature string.
 * @param error On return, contains an error if construction fails.
 * @return The constructed JWT, or nil if construction failed.
 */
+ (nullable instancetype)jwtWithHeader:(JWTHeader *)header
                               payload:(JWTPayload *)payload
                             signature:(NSString *)signature
                                  error:(NSError **)error;

/**
 * @brief Base64url-encodes data according to JWT specification.
 *
 * @param data The data to encode.
 * @param error On return, contains an error if encoding fails.
 * @return The base64url-encoded string, or nil on failure.
 */
+ (NSString *)base64URLEncodeData:(NSData *)data error:(NSError **)error;

/**
 * @brief Returns the complete encoded JWT string.
 *
 * @return The fully encoded JWT in base64url format.
 */
- (NSString *)encodedToken;

/**
 * @brief Generates the signing input for this token.
 *
 * The signing input is the concatenation of the encoded header and payload,
 * separated by a period character.
 *
 * @return The signing input string.
 */
- (NSString *)signingInput;

@end

/**
 * @brief Verifies and validates JWT tokens.
 *
 * JWTVerifier provides methods to verify JWT signatures and validate claims
 * against expected values, including issuer, audience, and time-based checks.
 */
@interface JWTVerifier : NSObject

/** The expected issuer claim value. */
@property (nonatomic, copy) NSString *expectedIssuer;

/** The expected audience claim value. */
@property (nonatomic, copy) NSString *expectedAudience;

/** Allowed signing algorithms. */
@property (nonatomic, copy) NSArray<NSString *> *allowedAlgorithms;

/** Clock offset for time-based validation adjustments. */
@property (nonatomic, strong) NSDate *clockOffset;

/** Public key for signature verification. */
@property (nonatomic, strong, nullable) NSData *publicKey;

/** Optional key rotation manager for verifying with multiple keys. */
@property (nonatomic, strong, nullable) KeyRotationManager *keyRotationManager;

/** Whether to allow tokens without subject claims. */
@property (nonatomic, assign) BOOL allowMissingSubject;

/**
 * @brief Verifies the signature of a JWT.
 *
 * @param jwt The JWT to verify.
 * @param error On return, contains an error if verification fails.
 * @return YES if the signature is valid, NO otherwise.
 */
- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error;

/**
 * @brief Validates the claims of a JWT payload.
 *
 * @param payload The payload to validate.
 * @param jwt The original JWT for context.
 * @param error On return, contains an error if validation fails.
 * @return YES if all claims are valid, NO otherwise.
 */
- (BOOL)validateClaims:(JWTPayload *)payload ofJWT:(JWT *)jwt error:(NSError **)error;

@end

/**
 * @brief Creates (mints) new JWT tokens.
 *
 * JWTMinter provides methods for signing and issuing JWTs with specified
 * payloads, supporting both access tokens and refresh tokens with ATProto
 * identity claims.
 */
@interface JWTMinter : NSObject

/** The issuer claim to include in minted tokens. */
@property (nonatomic, copy) NSString *issuer;

/** The signing algorithm to use (e.g., "RS256", "ES256"). */
@property (nonatomic, copy) NSString *signingAlgorithm;

/** Default expiration time in seconds for minted tokens. */
@property (nonatomic, assign) NSTimeInterval defaultExpiration;

/** The private key material for signing. */
@property (nonatomic, strong, nullable) NSData *privateKey;

/**
 * @brief Signs a payload dictionary as a JWT.
 *
 * @param payload The payload dictionary to sign.
 * @param error On return, contains an error if signing fails.
 * @return The encoded JWT string, or nil on failure.
 */
- (NSString *)signPayload:(NSDictionary *)payload error:(NSError **)error;

/**
 * @brief Mints an access token JWT for the specified user.
 *
 * @param did The user's Decentralized Identifier.
 * @param handle The user's handle.
 * @param scopes The granted scopes.
 * @param error On return, contains an error if minting fails.
 * @return The minted JWT access token, or nil on failure.
 */
- (JWT *)mintAccessTokenForDID:(NSString *)did
                        handle:(NSString *)handle
                        scopes:(NSArray<NSString *> *)scopes
                          error:(NSError **)error;

/**
 * @brief Mints a refresh token JWT for the specified user.
 *
 * @param did The user's Decentralized Identifier.
 * @param handle The user's handle.
 * @param scopes The granted scopes.
 * @param error On return, contains an error if minting fails.
 * @return The minted JWT refresh token, or nil on failure.
 */
- (JWT *)mintRefreshTokenForDID:(NSString *)did
                         handle:(NSString *)handle
                         scopes:(NSArray<NSString *> *)scopes
                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
