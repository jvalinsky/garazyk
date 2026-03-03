# Account Service

## Overview

The `PDSAccountService` manages account lifecycle operations including creation, authentication, token refresh, and deletion. It coordinates between the database layer and JWT token generation to provide a complete account management interface.

## Responsibilities

- Account creation with email, password, and handle
- User authentication and login
- JWT access and refresh token generation
- Account information retrieval
- Account deletion with password verification
- Email provider integration for verification codes

## Architecture

```
┌─────────────────────────────────────────┐
│   XRPC Account Endpoints                │
│  (com.atproto.server.*)                 │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│   PDSAccountService                     │
│  - createAccount()                      │
│  - login()                              │
│  - refreshAccessToken()                 │
│  - getAccount()                         │
│  - deleteAccount()                      │
└────────────────┬────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────┐  ┌──────▼────────┐
│ JWTMinter    │  │ Account       │
│ (tokens)     │  │ Repository    │
└──────────────┘  └───────────────┘
        │                 │
        └────────┬────────┘
                 │
        ┌────────▼────────────┐
        │ PDSDatabasePool     │
        │ (Account Storage)   │
        └─────────────────────┘
```

## Key Methods

### Account Creation

```objc
- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                          error:(NSError **)error;
```

Creates a new account with the provided credentials. Returns account information including the generated DID and initial tokens.

**Parameters:**
- `email`: User's email address
- `password`: Account password (hashed before storage)
- `handle`: User's handle (e.g., "alice.bsky.social")
- `did`: Optional pre-generated DID; if nil, one is generated automatically
- `error`: Error pointer for failure details

**Returns:** Dictionary with account info or nil on failure

**Implementation pattern (from PDSAccountService.m lines 50-150):**

The service validates the handle, generates cryptographic keys, registers with PLC, and stores the account:

```objc
// Validate Handle
if (![ATProtoHandleValidator validateHandle:handle error:error]) {
    return nil;
}
handle = [ATProtoHandleValidator normalizeHandle:handle];

// Generate signing and rotation keys
Secp256k1KeyPair *userKeyPair = [[Secp256k1 shared] generateKeyPairWithError:error];
if (!userKeyPair) return nil;

Secp256k1KeyPair *rotationKeyPair = [[Secp256k1 shared] generateKeyPairWithError:error];
if (!rotationKeyPair) return nil;

// Register DID with PLC or use provided DID
NSString *resolvedDid;
if (did) {
    resolvedDid = did;
} else {
    resolvedDid = [self _registerDIDWithPLCWithHandle:handle
                                           signingKey:userKeyPair
                                          rotationKey:rotationKeyPair
                                                error:error];
    if (!resolvedDid) return nil;
}

// Generate password hash
NSData *salt = [self generateSalt];
NSData *passwordHash = [self hashPassword:password salt:salt];

// Create and save account
PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
account.email = email;
account.handle = handle;
account.did = resolvedDid;
account.passwordHash = passwordHash;
account.passwordSalt = salt;
account.createdAt = [[NSDate date] timeIntervalSince1970];
account.updatedAt = [[NSDate date] timeIntervalSince1970];

NSError *createError = nil;
if (![_accountRepository saveAccount:account error:&createError]) {
    if (error) *error = createError;
    return nil;
}

// Generate JWT tokens
JWT *jwt = [self.minter mintAccessTokenForDID:resolvedDid handle:handle scopes:@[@"atproto"] error:nil];
NSString *accessToken = [jwt encodedToken];
NSString *refreshToken = [[NSUUID UUID] UUIDString];

// Store tokens
account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
account.refreshJwt = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
[_accountRepository saveAccount:account error:nil];
[_sessionRepository storeRefreshToken:refreshToken forAccountDid:resolvedDid error:nil];

return @{
    @"did": resolvedDid,
    @"handle": handle,
    @"email": email,
    @"accessJwt": accessToken,
    @"refreshJwt": refreshToken
};
```

**Example usage:**
```objc
NSError *error = nil;
NSDictionary *account = [accountService createAccountForEmail:@"user@example.com"
                                                     password:@"secure_password"
                                                      handle:@"alice"
                                                        did:nil
                                                       error:&error];
if (account) {
    NSString *did = account[@"did"];
    NSString *accessToken = account[@"accessJwt"];
}
```

### Authentication

```objc
- (nullable NSDictionary *)loginWithIdentifier:(NSString *)identifier
                                     password:(NSString *)password
                                        error:(NSError **)error;
```

Authenticates a user by handle or email and password. Returns access and refresh tokens.

**Parameters:**
- `identifier`: User's handle or email
- `password`: Account password
- `error`: Error pointer for failure details

**Returns:** Dictionary with tokens and account info or nil on failure

**Implementation pattern (from PDSAccountService.m lines 200-280):**

The service looks up the account by email or handle, verifies the password, and generates new tokens:

```objc
- (nullable NSDictionary *)loginWithIdentifier:(NSString *)identifier
                                      password:(NSString *)password
                                         error:(NSError **)error {
    if (!identifier) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeMissingParameter
                                       message:@"Missing identifier"];
        }
        return nil;
    }

    // Look up account by email or handle
    NSError *dbError = nil;
    PDSDatabaseAccount *account = nil;
    if ([identifier containsString:@"@"]) {
        account = [_accountRepository accountForEmail:identifier error:&dbError];
    } else {
        account = [_accountRepository accountForHandle:identifier error:&dbError];
    }

    if (dbError) {
        if (error) *error = dbError;
        return nil;
    }

    if (!account) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeNotFound
                                       message:@"Account not found"];
        }
        return nil;
    }

    return [self loginWithAccount:account password:password error:error];
}

- (nullable NSDictionary *)loginWithAccount:(PDSDatabaseAccount *)account
                                   password:(NSString *)password
                                      error:(NSError **)error {
    // Verify password using constant-time comparison
    NSData *passwordHash = [self hashPassword:password salt:account.passwordSalt];
    BOOL isPasswordCorrect = PDSConstantTimeEqualData(passwordHash, account.passwordHash);

    // Also check app passwords if available
    if (!isPasswordCorrect && self.serviceDatabases) {
        NSError *appPasswordError = nil;
        if ([self.serviceDatabases verifyAppPasswordForAccount:account.did 
                                                      password:password 
                                                         error:&appPasswordError]) {
            isPasswordCorrect = YES;
        }
    }

    if (!isPasswordCorrect) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeInvalidCredentials
                                       message:@"Invalid password"];
        }
        return nil;
    }

    // Generate new tokens
    JWT *jwt = [self.minter mintAccessTokenForDID:account.did 
                                           handle:account.handle 
                                           scopes:@[@"atproto"] 
                                            error:nil];
    NSString *accessToken = [jwt encodedToken];
    NSString *refreshToken = [[NSUUID UUID] UUIDString];

    // Store tokens
    account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_accountRepository saveAccount:account error:nil];
    [_sessionRepository storeRefreshToken:refreshToken forAccountDid:account.did error:nil];

    return @{
        @"did": account.did,
        @"handle": account.handle,
        @"email": account.email,
        @"accessJwt": accessToken,
        @"refreshJwt": refreshToken
    };
}
```

**Example usage:**
```objc
NSError *error = nil;
NSDictionary *session = [accountService loginWithIdentifier:@"alice"
                                                   password:@"secure_password"
                                                      error:&error];
if (session) {
    NSString *accessToken = session[@"accessJwt"];
    NSString *refreshToken = session[@"refreshJwt"];
}
```

### Token Refresh

```objc
- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken
                                       error:(NSError **)error;
```

Refreshes an expired access token using a valid refresh token.

**Parameters:**
- `refreshToken`: Valid refresh token from previous login
- `error`: Error pointer for failure details

**Returns:** Dictionary with new access token or nil on failure

**Example:**
```objc
NSError *error = nil;
NSDictionary *newSession = [accountService refreshAccessToken:refreshToken
                                                        error:&error];
if (newSession) {
    NSString *newAccessToken = newSession[@"accessToken"];
}
```

### Account Retrieval

```objc
- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error;
```

Retrieves account information for a specific DID.

**Parameters:**
- `did`: Decentralized identifier
- `error`: Error pointer for failure details

**Returns:** Dictionary with account info or nil if not found

### Account Deletion

```objc
- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error;
```

Deletes an account after password verification.

**Parameters:**
- `did`: Account DID to delete
- `password`: Password for verification
- `error`: Error pointer for failure details

**Returns:** YES on success, NO on failure

## Integration Points

### With JWT Minter

The service uses `JWTMinter` to generate access and refresh tokens:

```objc
@property (nonatomic, strong, nullable) JWTMinter *minter;
```

Tokens are signed with the PDS's private key and include claims for:
- `sub` (subject): User's DID
- `aud` (audience): PDS identifier
- `exp` (expiration): Token lifetime
- `iat` (issued at): Creation timestamp

### With Database Pool

Account data is persisted through `PDSDatabasePool`:

```objc
@property (nonatomic, strong) PDSDatabasePool *databasePool;
```

Each account has:
- Email address (unique)
- Handle (unique)
- Password hash (bcrypt or similar)
- DID (unique)
- Creation timestamp
- Account status (active/suspended)

### With Email Provider

Optional email provider for verification:

```objc
@property (nonatomic, strong, nullable) id<PDSEmailProvider> emailProvider;
```

Used for:
- Email verification during signup
- Password reset flows
- Account recovery

## Error Handling

Common error scenarios:

| Error | Cause | Handling |
|-------|-------|----------|
| Invalid email | Malformed email address | Validate format before submission |
| Duplicate handle | Handle already taken | Suggest alternatives |
| Weak password | Password doesn't meet requirements | Enforce password policy |
| Invalid credentials | Wrong password or handle | Reject login attempt |
| Account not found | DID doesn't exist | Return 404 error |
| Account suspended | Account has been disabled | Notify user |

## Best Practices

1. **Password Security**
   - Never store plaintext passwords
   - Use bcrypt or similar with appropriate cost factor
   - Implement rate limiting on login attempts

2. **Token Management**
   - Keep access tokens short-lived (15-60 minutes)
   - Use longer-lived refresh tokens (days/weeks)
   - Implement token rotation on refresh
   - Revoke tokens on logout

3. **Account Creation**
   - Validate email format
   - Enforce password complexity requirements
   - Verify email ownership before activation
   - Generate unique DIDs

4. **Concurrency**
   - Use database transactions for account creation
   - Prevent race conditions on handle/email uniqueness
   - Serialize token generation

## Common Patterns

### Creating an Account with Email Verification

```objc
// 1. Create account
NSError *error = nil;
NSDictionary *account = [accountService createAccountForEmail:@"user@example.com"
                                                     password:@"password"
                                                      handle:@"alice"
                                                        did:nil
                                                       error:&error];

// 2. Send verification email
if (account && emailProvider) {
    NSString *verificationCode = [self generateVerificationCode];
    [emailProvider sendVerificationEmail:@"user@example.com"
                                   code:verificationCode];
}

// 3. Verify email (in separate request)
// User clicks link or enters code
[self verifyEmailForDid:account[@"did"] code:verificationCode];
```

### Implementing Login with Token Refresh

```objc
// 1. Initial login
NSError *error = nil;
NSDictionary *session = [accountService loginWithIdentifier:@"alice"
                                                   password:@"password"
                                                      error:&error];

// 2. Store tokens securely
NSString *accessToken = session[@"accessToken"];
NSString *refreshToken = session[@"refreshToken"];
[self storeTokensSecurely:accessToken refresh:refreshToken];

// 3. When access token expires, refresh it
NSDictionary *newSession = [accountService refreshAccessToken:refreshToken
                                                        error:&error];
if (newSession) {
    [self storeTokensSecurely:newSession[@"accessToken"]
                     refresh:newSession[@"refreshToken"]];
}
```

### Handling Account Deletion

```objc
// 1. Verify password
NSError *error = nil;
NSDictionary *session = [accountService loginWithIdentifier:@"alice"
                                                   password:@"password"
                                                      error:&error];

// 2. Delete account
if (session) {
    BOOL deleted = [accountService deleteAccount:session[@"did"]
                                        password:@"password"
                                           error:&error];
    if (deleted) {
        // Clear local tokens and data
        [self clearLocalData];
    }
}
```

## See Also

- [JWT Tokens](../06-authentication/jwt-tokens)
- [Services Overview](./services-overview)
- [PDSApplication](./pds-application)
