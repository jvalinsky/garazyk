#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @header Session.h
 
 @abstract Session management for ATProto authentication.
 
 @discussion This header defines the session management classes used by the
 PDS for OAuth 2.0 authentication. It includes SessionToken, Session, and
 SessionStore for managing user authentication state.
 
 @copyright Copyright (c) 2024 Jack Myers
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
                                    handle:@"user.bsky.social"
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
@property (nonatomic, copy, readonly, nullable) NSString *dpopKeyThumbprint;

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
                                  scope:(NSString *)scope;

/*!
 @method initWithDID:handle:scope:
 
 @abstract Initializes a session with identity information.
 
 @param did The user's DID.
 @param handle The user's handle.
 @param scope The OAuth scope for the session.
 @return An initialized Session instance.
 */
- (instancetype)initWithDID:(NSString *)did
                    handle:(NSString *)handle
                     scope:(NSString *)scope;

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

@end

/*!
 @class SessionStore
 
 @abstract Manages storage and lifecycle of sessions.
 
 @discussion SessionStore provides persistent storage for sessions and
 handles creation, retrieval, refresh, and revocation of sessions.
 It implements token minting and validation logic.
 
 @code
 // Create a session for a user
 SessionStore *store = [SessionStore sharedStore];
 Session *session = [store createSessionForDID:@"did:plc:..."
                                       handle:@"user.bsky.social"
                                        scope:@"atproto"
                                      dpopJWK:jwkDict];
 
 // Look up by access token
 Session *found = [store getSessionByAccessToken:token error:nil];
 @endcode
 */
@interface SessionStore : NSObject

/*! Lifetime of access tokens in seconds (default: 3600). */
@property (nonatomic, assign) NSTimeInterval accessTokenLifetime;

/*! Lifetime of refresh tokens in seconds (default: 2592000). */
@property (nonatomic, assign) NSTimeInterval refreshTokenLifetime;

/*! Clock skew tolerance in seconds for token validation. */
@property (nonatomic, assign, readonly) NSTimeInterval clockSkew;

/*!
 @method sharedStore
 
 @abstract Returns the shared session store instance.
 
 @return The singleton SessionStore instance.
 */
+ (instancetype)sharedStore;

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
           newSession:(Session **)newSession
                 error:(NSError **)error;

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
