/**
 * @file Session.h
 * @brief Defines the session management layer for ATProto PDS authentication.
 *
 * This header provides classes for managing user sessions, including session tokens,
 * session objects, and persistent session storage. It handles token lifecycle management,
 * expiration, refresh operations, and session revocation.
 *
 * @note This module integrates with the OAuth2 authentication flow and JWT token handling.
 * @see OAuth2.h
 * @see JWT.h
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief Error domain for session-related errors.
 */
extern NSString * const SessionErrorDomain;

/**
 * @brief Error codes for session operations.
 */
typedef NS_ENUM(NSInteger, SessionError) {
    /** The provided token is invalid or malformed. */
    SessionErrorInvalidToken = 1000,
    /** The token has expired and is no longer valid. */
    SessionErrorTokenExpired,
    /** The session object is invalid or corrupted. */
    SessionErrorInvalidSession,
    /** The requested session was not found. */
    SessionErrorSessionNotFound,
    /** The requested scope is invalid or not permitted. */
    SessionErrorInvalidScope,
    /** The session has been revoked. */
    SessionErrorRevoked,
    /** A concurrent modification conflict occurred. */
    SessionErrorConcurrencyConflict
};

/**
 * @brief Represents an OAuth 2.0 token with associated metadata.
 *
 * SessionToken encapsulates a token's value, issuance time, expiration, and scope.
 * It supports both access tokens and refresh tokens, providing validation methods
 * for token lifecycle management.
 */
@interface SessionToken : NSObject

/** The actual token string value. */
@property (nonatomic, copy) NSString *value;

/** The date and time when the token was issued. */
@property (nonatomic, strong) NSDate *issuedAt;

/** The date and time when the token expires. */
@property (nonatomic, strong) NSDate *expiresAt;

/** The OAuth 2.0 scope associated with this token, or nil if no scope. */
@property (nonatomic, copy, nullable) NSString *scope;

/** YES if this token is a refresh token, NO for an access token. */
@property (nonatomic, assign) BOOL isRefreshToken;

/**
 * @brief Creates a new session token with the specified parameters.
 *
 * @param value The token string value.
 * @param expiresIn The number of seconds until the token expires from the issuance time.
 * @param scope The OAuth 2.0 scope string, or nil.
 * @param isRefreshToken YES if creating a refresh token, NO for access token.
 * @return A new SessionToken instance, or nil if parameters are invalid.
 */
+ (nullable instancetype)tokenWithValue:(NSString *)value
                              expiresIn:(NSTimeInterval)expiresIn
                                  scope:(nullable NSString *)scope
                          isRefreshToken:(BOOL)isRefreshToken;

/**
 * @brief Determines whether the token has expired.
 *
 * @return YES if the current date is after the expiration date, NO otherwise.
 */
- (BOOL)isExpired;

/**
 * @brief Validates the token for general usage.
 *
 * A token is valid if it has not expired and has a non-nil value.
 *
 * @return YES if the token is valid, NO otherwise.
 */
- (BOOL)isValid;

@end

/**
 * @brief Represents a complete user session with tokens and identity information.
 *
 * Session encapsulates a user's authenticated session, including their DID (Decentralized
 * Identifier), handle, access token, refresh token, and associated metadata. It provides
 * methods to serialize session data for OAuth 2.0 token responses.
 */
@interface Session : NSObject

/** Unique identifier for this session. */
@property (nonatomic, copy, readonly) NSString *sessionID;

/** The user's Decentralized Identifier (DID). */
@property (nonatomic, copy, readonly) NSString *did;

/** The user's handle (e.g., @username.example.com). */
@property (nonatomic, copy, readonly) NSString *handle;

/** The OAuth 2.0 access token for API access. */
@property (nonatomic, copy, readonly) NSString *accessToken;

/** The OAuth 2.0 refresh token for obtaining new access tokens, or nil. */
@property (nonatomic, copy, readonly, nullable) NSString *refreshToken;

/** The token type (typically "Bearer" or "DPoP"). */
@property (nonatomic, copy, readonly) NSString *tokenType;

/** The OAuth 2.0 scope granted to this session. */
@property (nonatomic, copy, readonly) NSString *scope;

/** The date and time when the session was created. */
@property (nonatomic, strong, readonly) NSDate *createdAt;

/** The date and time when the access token expires. */
@property (nonatomic, strong, readonly) NSDate *accessTokenExpiresAt;

/** The date and time when the refresh token expires, or nil if no expiration. */
@property (nonatomic, strong, readonly, nullable) NSDate *refreshTokenExpiresAt;

/** The DPoP key thumbprint for DPoP-bound tokens, or nil. */
@property (nonatomic, copy, readonly, nullable) NSString *dpopKeyThumbprint;

/**
 * @brief Creates a new session with the specified identity parameters.
 *
 * @param did The user's Decentralized Identifier.
 * @param handle The user's handle.
 * @param scope The OAuth 2.0 scope to grant.
 * @return A new Session instance, or nil if parameters are invalid.
 */
+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope;

/**
 * @brief Initializes a new session with the specified identity parameters.
 *
 * @param did The user's Decentralized Identifier.
 * @param handle The user's handle.
 * @param scope The OAuth 2.0 scope to grant.
 * @return The initialized session instance.
 */
- (instancetype)initWithDID:(NSString *)did
                    handle:(NSString *)handle
                     scope:(NSString *)scope;

/**
 * @brief Converts the session to an OAuth 2.0 token response dictionary.
 *
 * @return A dictionary suitable for JSON encoding in a token response.
 */
- (NSDictionary *)toTokenResponse;

/**
 * @brief Converts the session to a Bearer token response format.
 *
 * @return A dictionary suitable for a standard Bearer token response.
 */
- (NSDictionary *)toBearerTokenResponse;

@end

/**
 * @brief Persistent storage for session management and token lifecycle.
 *
 * SessionStore provides a thread-safe interface for creating, retrieving, refreshing,
 * and revoking user sessions. It manages token lifetimes and enforces security policies
 * such as clock skew tolerance for time-sensitive validation.
 */
@interface SessionStore : NSObject

/** The lifetime in seconds for access tokens issued by this store. */
@property (nonatomic, assign) NSTimeInterval accessTokenLifetime;

/** The lifetime in seconds for refresh tokens issued by this store. */
@property (nonatomic, assign) NSTimeInterval refreshTokenLifetime;

/**
 * @brief Creates a new session for the specified user.
 *
 * @param did The user's Decentralized Identifier.
 * @param handle The user's handle.
 * @param scope The OAuth 2.0 scope to grant.
 * @param dpopJWK Optional DPoP JWK for DPoP-bound tokens.
 * @return The newly created session, or nil if creation failed.
 */
- (nullable Session *)createSessionForDID:(NSString *)did
                                   handle:(NSString *)handle
                                    scope:(NSString *)scope
                                  dpopJWK:(nullable NSDictionary *)dpopJWK;

/**
 * @brief Retrieves a session by its access token.
 *
 * @param accessToken The access token to look up.
 * @param error On return, contains an error if the operation fails.
 * @return The session associated with the token, or nil if not found.
 */
- (nullable Session *)getSessionByAccessToken:(NSString *)accessToken error:(NSError **)error;

/**
 * @brief Retrieves a session by its refresh token.
 *
 * @param refreshToken The refresh token to look up.
 * @param error On return, contains an error if the operation fails.
 * @return The session associated with the token, or nil if not found.
 */
- (nullable Session *)getSessionByRefreshToken:(NSString *)refreshToken error:(NSError **)error;

/**
 * @brief Retrieves a session by its unique identifier.
 *
 * @param sessionID The session identifier to look up.
 * @param error On return, contains an error if the operation fails.
 * @return The session with the given ID, or nil if not found.
 */
- (nullable Session *)getSessionByID:(NSString *)sessionID error:(NSError **)error;

/**
 * @brief Revokes a session by its identifier.
 *
 * @param sessionID The session to revoke.
 * @param error On return, contains an error if the operation fails.
 * @return YES if the session was successfully revoked, NO otherwise.
 */
- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error;

/**
 * @brief Refreshes an existing session with new tokens.
 *
 * @param sessionID The session to refresh.
 * @param newScope Optional new scope to request.
 * @param dpopJWK Optional new DPoP key for the refreshed session.
 * @param newSession On return, contains the new session if successful.
 * @param error On return, contains an error if the operation fails.
 * @return YES if the session was successfully refreshed, NO otherwise.
 */
- (BOOL)refreshSession:(NSString *)sessionID
                  scope:(nullable NSString *)newScope
                dpopJWK:(nullable NSDictionary *)dpopJWK
            newSession:(Session **)newSession
                  error:(NSError **)error;

/**
 * @brief Retrieves all sessions for a specific user.
 *
 * @param did The user's Decentralized Identifier.
 * @param error On return, contains an error if the operation fails.
 * @return An array of all active sessions for the user, or nil on error.
 */
- (NSArray<Session *> *)getSessionsForDID:(NSString *)did error:(NSError **)error;

/**
 * @brief Retrieves all active sessions in the store.
 *
 * @param error On return, contains an error if the operation fails.
 * @return An array of all active sessions, or nil on error.
 */
- (NSArray<Session *> *)allActiveSessions:(NSError **)error;

/**
 * @brief The allowed clock skew in seconds for time-sensitive validations.
 *
 * @return The current clock skew tolerance.
 */
- (NSTimeInterval)clockSkew;

/**
 * @brief Sets the allowed clock skew for time-sensitive validations.
 *
 * @param clockSkew The clock skew tolerance in seconds.
 */
- (void)setClockSkew:(NSTimeInterval)clockSkew;

@end

NS_ASSUME_NONNULL_END
