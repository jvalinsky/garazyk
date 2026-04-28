## Before/After Examples

### Example 1: Method Documentation

**Before (LLM-generated):**
```objc
/**
 * Okay so this method is gonna create an access token for the user,
 * right? First it takes the DID and handle, then it figures out what
 * scopes they need. I made it so that it uses the JWTMinter internally
 * which is pretty cool because it handles all the JWT signing stuff.
 * The token will be valid for the default expiration time which is set
 * in the minter configuration. You can also pass in custom scopes if you
 * want! ✨
 *
 * @param did The user's DID
 * @param handle The user's handle
 * @param scopes The scopes you want (optional)
 * @param error Just in case something goes wrong
 * @return The access token JWT or nil if there was an error
 */
- (JWT *)mintAccessTokenForDID:(NSString *)did
                        handle:(NSString *)handle
                        scopes:(NSArray<NSString *> *)scopes
                          error:(NSError **)error;
```

**After (HeaderDoc-compliant):**
```objc
/*!
 @method mintAccessTokenForDID:handle:scopes:error:

 @abstract Mints an access token for a user.

 @discussion Creates a signed JWT access token with the provided
 identity claims. Uses JWTMinter for cryptographic signing.
 The token includes standard claims (iss, sub, aud, exp, iat)
 plus ATProto-specific claims (did, handle, scope).

 @param did The user's DID (required, valid DID format).
 @param handle The user's handle (required, normalized format).
 @param scopes The granted scopes (optional, defaults to all allowed).
 @param error On return, contains an error if minting failed.
 @return A new access token JWT, or nil on failure.

 @see JWTMinter
 @see mintRefreshTokenForDID:handle:scopes:error:
 */
- (nullable JWT *)mintAccessTokenForDID:(NSString *)did
                                 handle:(NSString *)handle
                                 scopes:(nullable NSArray<NSString *> *)scopes
                                   error:(NSError **)error;
```

### Example 2: Class Documentation

**Before (LLM-generated):**
```objc
/**
 * 🔐 This powerful OAuth2Server class handles all the authorization
 * stuff for the PDS! It seamlessly manages the whole OAuth flow with
 * DPoP which is this really cool security feature that binds tokens
 * to keys. Let me walk you through what it does...
 *
 * First there's the authorization request handling which creates
 * those fancy URLs to redirect users to. Then we handle the token
 * endpoint which is where clients swap their codes for tokens.
 * There's also refresh logic so users don't have to log in all
 * the time! 🎉
 */
@interface OAuth2Server : NSObject
```

**After (HeaderDoc-compliant):**
```objc
/*!
 @class OAuth2Server

 @abstract OAuth 2.0 authorization server implementation.

 @discussion OAuth2Server handles all authorization server operations
 including:
 - Authorization request processing and URL generation
 - Token issuance with DPoP proof-of-possession binding
 - Token refresh using refresh tokens
 - Session management and lifecycle

 Integrates with JWTMinter for JWT operations, KeyManager for key
 storage and rotation, and identity services for DID/handle resolution.

 @code
 OAuth2Server *server = [[OAuth2Server alloc] init];
 server.issuer = @"https://pds.example.com";
 server.authorizationEndpoint = @"https://pds.example.com/oauth/authorize";
 server.tokenEndpoint = @"https://pds.example.com/oauth/token";

 [server handleAuthorizationRequest:request completion:^(URL, code, error) {
     // Redirect user to URL with code
 }];
 @endcode

 @see JWTMinter
 @see KeyManager
 @see DIDResolver
 */
@interface OAuth2Server : NSObject
```

### Example 3: Property Documentation

**Before (LLM-generated):**
```objc
@property (nonatomic, strong) NSDate *clockOffset; // Clock offset for validation
@property (nonatomic, strong, nullable) KeyRotationManager *keyRotationManager; // Optional key rotation manager for verifying with multiple keys
```

**After (HeaderDoc-compliant):**
```objc
/*! Clock offset in seconds for time-based claim validation. */
@property (nonatomic, strong) NSDate *clockOffset;

/*! Optional key manager for verifying with rotated keys. */
@property (nonatomic, strong, nullable) KeyRotationManager *keyRotationManager;
```
