#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SessionToken;
@class Session;
@class SessionStore;
@class JWTMinter;

/*!
 @header Session.h
 
 @abstract Session management for ATProto authentication.
 
 @discussion This header defines the session management classes used by the
 PDS for OAuth 2.0 authentication. It includes SessionToken, Session, and
 SessionStore for managing user authentication state.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

extern NSString * const SessionErrorDomain;

/*!
 @enum SessionError
 
 @abstract Error codes for session operations.
 
 @constant SessionErrorInvalidToken The token format is invalid.
 @constant SessionErrorTokenExpired The token has expired.
 @constant SessionErrorInvalidSession The session is malformed.
 @constant SessionErrorSessionNotFound The session was not found.
 @constant SessionErrorInvalidScope The requested scope is invalid.
 @constant SessionErrorRevoked The session has been revoked.
 @constant SessionErrorConcurrencyConflict A concurrent modification occurred.
 */
typedef NS_ENUM(NSInteger, SessionError) {
    SessionErrorInvalidToken = 1000,
    SessionErrorTokenExpired,
    SessionErrorInvalidSession,
    SessionErrorSessionNotFound,
    SessionErrorInvalidScope,
    SessionErrorRevoked,
    SessionErrorConcurrencyConflict
};

/*!
 @class SessionToken
 
 @abstract Represents an OAuth 2.0 token.
 
 @discussion SessionToken encapsulates both access tokens and refresh tokens
 with their associated metadata including expiration and scope.
 */
@interface SessionToken : NSObject

/*! The token value (JWT for access tokens, opaque string for refresh tokens). */
@property (nonatomic, copy) NSString *value;

/*! The date and time when the token was issued. */
@property (nonatomic, strong) NSDate *issuedAt;

/*! The date and time when the token expires. */
@property (nonatomic, strong) NSDate *expiresAt;

/*! The OAuth 2.0 scope associated with this token. */
@property (nonatomic, copy, nullable) NSString *scope;

/*! YES if this is a refresh token, NO for an access token. */
@property (nonatomic, assign) BOOL isRefreshToken;

/*!
 @method tokenWithValue:expiresIn:scope:isRefreshToken:
 
 @abstract Creates a token with specified parameters.
 
 @param value The token value string.
 @param expiresIn Time in seconds until the token expires.
 @param scope The OAuth scope for this token.
 @param isRefreshToken YES if this is a refresh token.
 @return A new SessionToken instance.
 */
+ (nullable instancetype)tokenWithValue:(NSString *)value
                               expiresIn:(NSTimeInterval)expiresIn
                                   scope:(nullable NSString *)scope
                           isRefreshToken:(BOOL)isRefreshToken;

/*!
 @method isExpired
 
 @abstract Checks if the token has expired.
 
 @discussion This method compares the current date against the expiration date.
 A small clock skew tolerance may be applied.
 
 @return YES if the token has expired, NO otherwise.
 */
- (BOOL)isExpired;

/*!
 @method isValid
 
 @abstract Checks if the token is currently valid.
 
 @discussion A token is valid if it has not expired and has a valid format.
 
 @return YES if the token is valid, NO otherwise.
 */
- (BOOL)isValid;

@end

/*!
 @class Session
 
 @abstract Represents an authenticated user session.
 
 @discussion Session contains all information about an authenticated session
 including tokens, user identity, and metadata. It provides methods for
 serializing to OAuth 2.0 token responses.
 
 @code
 // Create a new session
 Session *session = [Session sessionWithDID:@"did:plc:..."
                                    handle:@"alice.test"
                                     scope:@"atproto"];
 
 // Get token response for API
 NSDictionary *response = [session toTokenResponse];
 @endcode
 */
@interface Session : NSObject

/*! Unique identifier for this session. */
@property (nonatomic, copy, readonly) NSString *sessionID;

/*! The user's decentralized identifier. */
@property (nonatomic, copy, readonly) NSString *did;

/*! The user's handle. */
@property (nonatomic, copy, readonly) NSString *handle;

/*! The current access token value. */
@property (nonatomic, copy, readonly) NSString *accessToken;

/*! The refresh token for obtaining new access tokens. */
@property (nonatomic, copy, readonly, nullable) NSString *refreshToken;

/*! The token type (typically "DPoP" for ATProto). */
@property (nonatomic, copy, readonly) NSString *tokenType;

/*! The OAuth scope for this session. */
@property (nonatomic, copy, readonly) NSString *scope;

/*! The date when the session was created. */
@property (nonatomic, strong, readonly) NSDate *createdAt;

/*! The date when the access token expires. */
@property (nonatomic, strong, readonly) NSDate *accessTokenExpiresAt;

/*! The date when the refresh token expires, if applicable. */
@property (nonatomic, strong, readonly, nullable) NSDate *refreshTokenExpiresAt;

/*! Thumbprint of the DPoP key used for this session. */
@property (nonatomic, copy, readwrite, nullable) NSString *dpopKeyThumbprint;

/*! Minter used for creating access tokens. */
@property (nonatomic, strong, nullable) JWTMinter *minter;

/*!
 @method sessionWithDID:handle:scope:
  
 @abstract Creates a new session with the specified identity.
  
 @param did The user's DID.
 @param handle The user's handle.
 @param scope The OAuth scope for the session.
 @return A new Session instance.
 */
+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope
                      dpopKeyThumbprint:(nullable NSString *)jkt;

+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope;

/*!
 @method sessionWithDID:handle:scope:minter:
 
 @abstract Creates a new session with the specified identity and minter.
 
 @param did The user's DID.
 @param handle The user's handle.
 @param scope The OAuth scope for the session.
 @param minter The JWT minter to use for access tokens.
 @return A new Session instance.
 */
+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope
                                 minter:(nullable JWTMinter *)minter
                      dpopKeyThumbprint:(nullable NSString *)jkt;

+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope
                                 minter:(nullable JWTMinter *)minter;

/*!
 @method initWithDID:handle:scope:
  
 @abstract Initializes a session with identity information.
  
 @param did The user's DID.
 @param handle The user's handle.
 @param scope The OAuth scope for the session.
 @param jkt The DPoP key thumbprint.
 @return An initialized Session instance.
 */
- (instancetype)initWithDID:(NSString *)did
                    handle:(NSString *)handle
                     scope:(NSString *)scope
         dpopKeyThumbprint:(nullable NSString *)jkt;

- (instancetype)initWithDID:(NSString *)did
                     handle:(NSString *)handle
                      scope:(NSString *)scope;

/*!
 @method initWithDID:handle:scope:minter:
 
 @abstract Initializes a session with identity information and a minter.
 
 @param did The user's DID.
 @param handle The user's handle.
 @param scope The OAuth scope for the session.
 @param minter The JWT minter to use for access tokens.
 @param jkt The DPoP key thumbprint.
 @return An initialized Session instance.
 */
- (instancetype)initWithDID:(NSString *)did
                    handle:(NSString *)handle
                     scope:(NSString *)scope
                    minter:(nullable JWTMinter *)minter
         dpopKeyThumbprint:(nullable NSString *)jkt;

- (instancetype)initWithDID:(NSString *)did
                     handle:(NSString *)handle
                      scope:(NSString *)scope
                     minter:(nullable JWTMinter *)minter;

/*!
 @method toTokenResponse
 
 @abstract Converts the session to an OAuth token response dictionary.
 
 @return A dictionary suitable for the token endpoint response.
 */
- (NSDictionary *)toTokenResponse;

/*!
 @method toBearerTokenResponse
 
 @abstract Converts the session to a bearer token response.
 
 @discussion This method returns a response formatted for legacy clients
 that don't support DPoP.
 
 @return A dictionary for bearer token response.
 */
- (NSDictionary *)toBearerTokenResponse;

 /*!
  @method refreshAccessToken
 
  @abstract Generates a new access token for the session.
 
  @return The new access token value.
  */
 - (NSString *)refreshAccessToken;

/*!
 @method isAccessTokenValid

 @abstract Returns YES if the access token is currently valid (not expired).
 */
- (BOOL)isAccessTokenValid;

/*!
 @method isRefreshTokenValid

 @abstract Returns YES if the refresh token is currently valid (not expired).
 */
- (BOOL)isRefreshTokenValid;

 @end



/*!
 @protocol PDSSessionStorage

 @abstract Protocol for session storage backends.

 @discussion Defines the contract for session persistence operations.
 Implementations provide different storage backends for OAuth 2.0 sessions:

 <b>Implementations:</b>
 - PDSMemorySessionStorage: In-memory storage (testing/development)
 - PDSSQLiteSessionStorage: SQLite-backed persistent storage (production)

 <b>Thread Safety:</b> All methods must be thread-safe. Implementations
 should handle concurrent access from multiple threads.

 <b>Security:</b> Sessions contain sensitive tokens. Implementations should
 consider encryption at rest for production deployments.

 @see Session
 @see SessionStore
 */
@protocol PDSSessionStorage <NSObject>

/*!
 @method saveSession:error:

 @abstract Persists a session to storage.

 @param session The session to save.
 @param error On return, contains an error if the save failed.
 @return YES if saved successfully, NO otherwise.
 */
- (BOOL)saveSession:(Session *)session error:(NSError **)error;

/*!
 @method getSessionByAccessToken:error:

 @abstract Retrieves a session by its access token.

 @param token The access token to search for.
 @param error On return, contains an error if the lookup failed.
 @return The session, or nil if not found.
 */
- (nullable Session *)getSessionByAccessToken:(NSString *)token error:(NSError **)error;

/*!
 @method getSessionByRefreshToken:error:

 @abstract Retrieves a session by its refresh token.

 @param token The refresh token to search for.
 @param error On return, contains an error if the lookup failed.
 @return The session, or nil if not found.
 */
- (nullable Session *)getSessionByRefreshToken:(NSString *)token error:(NSError **)error;

/*!
 @method getSessionByID:error:

 @abstract Retrieves a session by its unique identifier.

 @param sessionID The session identifier.
 @param error On return, contains an error if the lookup failed.
 @return The session, or nil if not found.
 */
- (nullable Session *)getSessionByID:(NSString *)sessionID error:(NSError **)error;

/*!
 @method revokeSessionByID:error:

 @abstract Marks a session as revoked.

 @param sessionID The session identifier to revoke.
 @param error On return, contains an error if the revocation failed.
 @return YES if revoked successfully, NO otherwise.
 */
- (BOOL)revokeSessionByID:(NSString *)sessionID error:(NSError **)error;

/*!
 @method getSessionsForDID:error:

 @abstract Retrieves all sessions for a given DID.

 @param did The DID to search for.
 @param error On return, contains an error if the lookup failed.
 @return An array of sessions for the DID.
 */
- (NSArray<Session *> *)getSessionsForDID:(NSString *)did error:(NSError **)error;

/*!
 @method allActiveSessions:

 @abstract Retrieves all active (non-revoked) sessions.

 @param error On return, contains an error if the lookup failed.
 @return An array of all active sessions.
 */
- (NSArray<Session *> *)allActiveSessions:(NSError **)error;

@end

/*!
 @class PDSMemorySessionStorage
 @abstract In-memory implementation of session storage.
 */
@interface PDSMemorySessionStorage : NSObject <PDSSessionStorage>
@end

/*!
 @class PDSSQLiteSessionStorage
 @abstract SQLite-backed implementation of session storage.
 */
@interface PDSSQLiteSessionStorage : NSObject <PDSSessionStorage>
- (instancetype)initWithPath:(NSString *)path;
@end

/*!
 @class SessionStore
 @abstract Manages storage and lifecycle of sessions.
 */
@interface SessionStore : NSObject

/*! Lifetime of access tokens in seconds (default: 3600). */
@property (nonatomic, assign) NSTimeInterval accessTokenLifetime;

/*! Lifetime of refresh tokens in seconds (default: 2592000). */
@property (nonatomic, assign) NSTimeInterval refreshTokenLifetime;

/*! Clock skew tolerance in seconds for token validation. */
@property (nonatomic, assign, readonly) NSTimeInterval clockSkew;

/*! Minter used for creating access tokens. */
@property (nonatomic, strong, nullable) JWTMinter *minter;

/*!
 @method sharedStore
 
 @abstract Returns the shared session store instance.
 
 @return The singleton SessionStore instance.
 */
+ (instancetype)sharedStore;

/*!
 @method initWithDatabasePath:
 
 @abstract Creates a session store backed by a SQLite database at the given path.
 
 @discussion Sessions are persisted to disk and survive process restarts.
 Pass nil or use init for an in-memory store (legacy behavior).
 
 @param path File path for the SQLite database, or nil for in-memory.
 @return An initialized SessionStore instance.
 */
- (instancetype)initWithDatabasePath:(nullable NSString *)path;

/*!
 @method createSessionForDID:handle:scope:dpopJWK:
 
 @abstract Creates a new authenticated session.
 
 @param did The user's DID.
 @param handle The user's handle.
 @param scope The OAuth scope for the session.
 @param dpopJWK Optional DPoP key for proof-of-possession.
 @param error On return, contains an error if session creation failed.
 @return The new Session, or nil on failure.
 */
- (nullable Session *)createSessionForDID:(NSString *)did
                                   handle:(NSString *)handle
                                    scope:(NSString *)scope
                                  dpopJWK:(nullable NSDictionary *)dpopJWK
                                    error:(NSError **)error;

/*!
 @method getSessionByAccessToken:error:
 
 @abstract Retrieves a session by its access token.
 
 @param accessToken The access token to look up.
 @param error On return, contains an error if the lookup failed.
 @return The Session, or nil if not found.
 */
- (nullable Session *)getSessionByAccessToken:(NSString *)accessToken error:(NSError **)error;

/*!
 @method getSessionByRefreshToken:error:
 
 @abstract Retrieves a session by its refresh token.
 
 @param refreshToken The refresh token to look up.
 @param error On return, contains an error if the lookup failed.
 @return The Session, or nil if not found.
 */
- (nullable Session *)getSessionByRefreshToken:(NSString *)refreshToken error:(NSError **)error;

/*!
 @method getSessionByID:error:
 
 @abstract Retrieves a session by its ID.
 
 @param sessionID The session ID to look up.
 @param error On return, contains an error if the lookup failed.
 @return The Session, or nil if not found.
 */
- (nullable Session *)getSessionByID:(NSString *)sessionID error:(NSError **)error;

/*!
 @method revokeSession:error:
 
 @abstract Revokes a session and invalidates its tokens.
 
 @param sessionID The ID of the session to revoke.
 @param error On return, contains an error if revocation failed.
 @return YES if the session was revoked, NO otherwise.
 */
- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error;

/*!
 @method refreshSession:scope:dpopJWK:newSession:error:
 
 @abstract Refreshes a session with new tokens.
 
 @param sessionID The ID of the session to refresh.
 @param newScope Optional new scope for the session.
 @param dpopJWK Optional new DPoP key.
 @param newSession On return, contains the new session if successful.
 @param error On return, contains an error if refresh failed.
 @return YES if the session was refreshed, NO otherwise.
 */
- (BOOL)refreshSession:(NSString *)sessionID
                  scope:(nullable NSString *)newScope
                dpopJWK:(nullable NSDictionary *)dpopJWK
            newSession:(Session * _Nullable * _Nullable)newSession
                  error:(NSError ** _Nullable)error;

/*!
 @method getSessionsForDID:error:
 
 @abstract Retrieves all active sessions for a user.
 
 @param did The user's DID.
 @param error On return, contains an error if retrieval failed.
 @return An array of the user's active sessions.
 */
- (NSArray<Session *> *)getSessionsForDID:(NSString *)did error:(NSError **)error;

/*!
 @method allActiveSessions:
 
 @abstract Retrieves all active sessions in the system.
 
 @param error On return, contains an error if retrieval failed.
 @return An array of all active sessions.
 */
- (NSArray<Session *> *)allActiveSessions:(NSError **)error;

/*!
 @method setClockSkew:
 
 @abstract Sets the clock skew tolerance for token validation.
 
 @param clockSkew Maximum acceptable clock difference in seconds.
 */
- (void)setClockSkew:(NSTimeInterval)clockSkew;

@end

NS_ASSUME_NONNULL_END
