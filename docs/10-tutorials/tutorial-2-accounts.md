# Tutorial 2: Account Management

## Overview

In this tutorial, you'll transform your basic PDS into a multi-user system by implementing account creation, authentication, and JWT token management. This is where your server becomes truly functional—users can create accounts, log in, and receive tokens that authenticate their requests.

By the end of this tutorial, you'll have implemented the two most critical AT Protocol endpoints: `com.atproto.server.createAccount` and `com.atproto.server.createSession`. These form the foundation of user identity and authentication in the AT Protocol ecosystem.

### What You'll Build

A PDS with complete account management:
- Account creation with email, password, and handle
- Secure password hashing with salt
- SQLite database persistence
- JWT access and refresh token generation
- Login/session creation endpoint
- Proper error handling for duplicate accounts and invalid credentials

This tutorial introduces real-world concerns: database transactions, cryptographic hashing, token generation, and secure credential storage.

**Learning Objectives:**
- Implement account creation endpoint (`com.atproto.server.createAccount`)
- Generate and manage JWT access and refresh tokens
- Persist account data to SQLite database with proper schema design
- Implement login endpoint (`com.atproto.server.createSession`)
- Handle authentication errors (duplicate accounts, invalid passwords)
- Use CommonCrypto for password hashing and HMAC signatures
- Understand DID generation and handle uniqueness constraints

**Estimated Time:** 45-60 minutes

## Prerequisites

Before starting this tutorial, you should have:

- **Completed:**
  - [Tutorial 1: Hello PDS](./tutorial-1-hello-pds) — You'll extend that codebase
  
- **Understanding of:**
  - JWT tokens and their structure (header, payload, signature)
  - Basic cryptography concepts (hashing, salting, HMAC)
  - SQL and database schemas
  - HTTP POST requests with JSON bodies
  
- **Recommended Reading:**
  - [JWT Tokens](../06-authentication/jwt-tokens) — Deep dive into token structure
  - [Account Service](../03-application-layer/account-service) — Production implementation patterns

## Step 1: Create Account Data Model

First, let's define what an account looks like in our system. This model represents all the information we need to store about a user.

Create `src/Account.h`:

```objc
#import <Foundation/Foundation.h>

@interface Account : NSObject

@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, copy) NSString *email;
@property (nonatomic, copy) NSData *passwordHash;
@property (nonatomic, copy) NSData *passwordSalt;
@property (nonatomic, copy) NSString *accessJwt;
@property (nonatomic, copy) NSString *refreshJwt;
@property (nonatomic, assign) NSTimeInterval createdAt;

@end
```

### Understanding the Account Model

**DID (Decentralized Identifier):** Every account has a unique DID like `did:plc:abc123`. This is the user's permanent identity in the AT Protocol network. Even if they change their handle or email, their DID stays the same.

**Handle:** The user-friendly identifier like `alice.example.com`. Handles must be unique within your PDS and can be changed (though we don't implement that here).

**Email:** Used for account recovery and notifications. Also must be unique.

**Password Storage:** We never store passwords in plaintext. Instead, we store:
- `passwordHash` — The result of hashing the password with the salt
- `passwordSalt` — Random data mixed with the password before hashing

This two-step approach (salt + hash) protects against rainbow table attacks. Even if two users have the same password, their hashes will differ because of unique salts.

**JWT Tokens:** We store the current tokens so users can maintain sessions across server restarts. In production, you'd use a more sophisticated token management system.

**Timestamps:** `createdAt` tracks when the account was created, useful for analytics and debugging.

### Why This Design?

This model balances simplicity with security. Production systems add more fields (profile data, preferences, verification status), but this core set handles the essential account lifecycle.

## Step 2: Create Account Repository

Create `src/AccountRepository.h`:

```objc
#import <Foundation/Foundation.h>
#import "Account.h"

@interface AccountRepository : NSObject

- (instancetype)initWithDatabasePath:(NSString *)path;
- (BOOL)saveAccount:(Account *)account error:(NSError **)error;
- (nullable Account *)accountForHandle:(NSString *)handle error:(NSError **)error;
- (nullable Account *)accountForEmail:(NSString *)email error:(NSError **)error;
- (nullable Account *)accountForDid:(NSString *)did error:(NSError **)error;

@end
```

## Step 3: Implement Account Repository

Create `src/AccountRepository.m`:

```objc
#import "AccountRepository.h"
#import <sqlite3.h>

@interface AccountRepository ()
@property (nonatomic, assign) sqlite3 *database;
@end

@implementation AccountRepository

- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (!self) return nil;
    
    NSString *dbPath = [path stringByAppendingPathComponent:@"accounts.db"];
    int rc = sqlite3_open([dbPath UTF8String], &_database);
    
    if (rc != SQLITE_OK) {
        NSLog(@"Failed to open database: %s", sqlite3_errmsg(_database));
        return nil;
    }
    
    [self createTablesIfNeeded];
    
    return self;
}

- (void)createTablesIfNeeded {
    const char *sql = "CREATE TABLE IF NOT EXISTS accounts ("
        "did TEXT PRIMARY KEY,"
        "handle TEXT UNIQUE NOT NULL,"
        "email TEXT UNIQUE NOT NULL,"
        "password_hash BLOB NOT NULL,"
        "password_salt BLOB NOT NULL,"
        "access_jwt TEXT,"
        "refresh_jwt TEXT,"
        "created_at REAL NOT NULL"
        ");";
    
    char *errMsg = NULL;
    int rc = sqlite3_exec(_database, sql, NULL, NULL, &errMsg);
    
    if (rc != SQLITE_OK) {
        NSLog(@"Failed to create table: %s", errMsg);
        sqlite3_free(errMsg);
    }
}

- (BOOL)saveAccount:(Account *)account error:(NSError **)error {
    const char *sql = "INSERT OR REPLACE INTO accounts "
        "(did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    sqlite3_bind_text(stmt, 1, [account.did UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [account.handle UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, [account.email UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 4, account.passwordHash.bytes, (int)account.passwordHash.length, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 5, account.passwordSalt.bytes, (int)account.passwordSalt.length, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 6, [account.accessJwt UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 7, [account.refreshJwt UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 8, account.createdAt);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    return YES;
}

- (nullable Account *)accountForHandle:(NSString *)handle error:(NSError **)error {
    const char *sql = "SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at "
        "FROM accounts WHERE handle = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [handle UTF8String], -1, SQLITE_TRANSIENT);
    
    Account *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [[Account alloc] init];
        account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:sqlite3_column_bytes(stmt, 3)];
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4) length:sqlite3_column_bytes(stmt, 4)];
        account.accessJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 5)];
        account.refreshJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 6)];
        account.createdAt = sqlite3_column_double(stmt, 7);
    }
    
    sqlite3_finalize(stmt);
    return account;
}

- (nullable Account *)accountForEmail:(NSString *)email error:(NSError **)error {
    const char *sql = "SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at "
        "FROM accounts WHERE email = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [email UTF8String], -1, SQLITE_TRANSIENT);
    
    Account *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [[Account alloc] init];
        account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:sqlite3_column_bytes(stmt, 3)];
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4) length:sqlite3_column_bytes(stmt, 4)];
        account.accessJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 5)];
        account.refreshJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 6)];
        account.createdAt = sqlite3_column_double(stmt, 7);
    }
    
    sqlite3_finalize(stmt);
    return account;
}

- (nullable Account *)accountForDid:(NSString *)did error:(NSError **)error {
    const char *sql = "SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at "
        "FROM accounts WHERE did = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);
    
    Account *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [[Account alloc] init];
        account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:sqlite3_column_bytes(stmt, 3)];
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4) length:sqlite3_column_bytes(stmt, 4)];
        account.accessJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 5)];
        account.refreshJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 6)];
        account.createdAt = sqlite3_column_double(stmt, 7);
    }
    
    sqlite3_finalize(stmt);
    return account;
}

- (void)dealloc {
    if (_database) {
        sqlite3_close(_database);
    }
}

@end
```

## Step 4: Create JWT Token Generator

Create `src/SimpleJWTMinter.h`:

```objc
#import <Foundation/Foundation.h>

@interface SimpleJWTMinter : NSObject

- (instancetype)initWithIssuer:(NSString *)issuer;
- (NSString *)mintAccessTokenForDID:(NSString *)did handle:(NSString *)handle;
- (NSString *)mintRefreshTokenForDID:(NSString *)did handle:(NSString *)handle;

@end
```

## Step 5: Implement JWT Token Generator

Create `src/SimpleJWTMinter.m`:

```objc
#import "SimpleJWTMinter.h"
#import <CommonCrypto/CommonDigest.h>

@interface SimpleJWTMinter ()
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, copy) NSString *secret;
@end

@implementation SimpleJWTMinter

- (instancetype)initWithIssuer:(NSString *)issuer {
    self = [super init];
    if (!self) return nil;
    
    self.issuer = issuer;
    self.secret = @"tutorial-secret-key-do-not-use-in-production";
    
    return self;
}

- (NSString *)mintAccessTokenForDID:(NSString *)did handle:(NSString *)handle {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval exp = now + 3600;  // 1 hour
    
    NSDictionary *payload = @{
        @"iss": self.issuer,
        @"sub": did,
        @"aud": self.issuer,
        @"iat": @(now),
        @"exp": @(exp),
        @"scope": @"atproto_repo",
        @"handle": handle
    };
    
    return [self encodeJWT:payload];
}

- (NSString *)mintRefreshTokenForDID:(NSString *)did handle:(NSString *)handle {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval exp = now + (86400 * 30);  // 30 days
    
    NSDictionary *payload = @{
        @"iss": self.issuer,
        @"sub": did,
        @"aud": self.issuer,
        @"iat": @(now),
        @"exp": @(exp),
        @"scope": @"atproto_refresh",
        @"handle": handle
    };
    
    return [self encodeJWT:payload];
}

- (NSString *)encodeJWT:(NSDictionary *)payload {
    // Header
    NSDictionary *header = @{@"alg": @"HS256", @"typ": @"JWT"};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerB64 = [self base64URLEncode:headerData];
    
    // Payload
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadB64 = [self base64URLEncode:payloadData];
    
    // Signature
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    NSData *secretData = [self.secret dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, secretData.bytes, secretData.length, signingData.bytes, signingData.length, digest);
    NSData *signatureData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *signatureB64 = [self base64URLEncode:signatureData];
    
    return [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
```

## Step 6: Create Account Service

Create `src/AccountService.h`:

```objc
#import <Foundation/Foundation.h>
#import "Account.h"
#import "AccountRepository.h"
#import "SimpleJWTMinter.h"

@interface AccountService : NSObject

- (instancetype)initWithRepository:(AccountRepository *)repository
                            minter:(SimpleJWTMinter *)minter;

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                          error:(NSError **)error;

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                  password:(NSString *)password
                                     error:(NSError **)error;

@end
```

## Step 7: Implement Account Service

Create `src/AccountService.m`:

```objc
#import "AccountService.h"
#import <CommonCrypto/CommonCrypto.h>

@interface AccountService ()
@property (nonatomic, strong) AccountRepository *repository;
@property (nonatomic, strong) SimpleJWTMinter *minter;
@end

@implementation AccountService

- (instancetype)initWithRepository:(AccountRepository *)repository
                            minter:(SimpleJWTMinter *)minter {
    self = [super init];
    if (!self) return nil;
    
    self.repository = repository;
    self.minter = minter;
    
    return self;
}

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                          error:(NSError **)error {
    // Validate inputs
    if (!email || !password || !handle) {
        if (error) {
            *error = [NSError errorWithDomain:@"Account" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields"}];
        }
        return nil;
    }
    
    // Check if handle already exists
    NSError *dbError = nil;
    Account *existing = [self.repository accountForHandle:handle error:&dbError];
    if (existing) {
        if (error) {
            *error = [NSError errorWithDomain:@"Account" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Handle already taken"}];
        }
        return nil;
    }
    
    // Generate DID
    NSString *did = [NSString stringWithFormat:@"did:plc:%@", [[NSUUID UUID] UUIDString]];
    
    // Hash password
    NSData *salt = [self generateSalt];
    NSData *passwordHash = [self hashPassword:password salt:salt];
    
    // Create account
    Account *account = [[Account alloc] init];
    account.did = did;
    account.handle = handle;
    account.email = email;
    account.passwordHash = passwordHash;
    account.passwordSalt = salt;
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    
    // Generate tokens
    account.accessJwt = [self.minter mintAccessTokenForDID:did handle:handle];
    account.refreshJwt = [self.minter mintRefreshTokenForDID:did handle:handle];
    
    // Save account
    if (![self.repository saveAccount:account error:&dbError]) {
        if (error) *error = dbError;
        return nil;
    }
    
    return @{
        @"did": did,
        @"handle": handle,
        @"email": email,
        @"accessJwt": account.accessJwt,
        @"refreshJwt": account.refreshJwt
    };
}

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                  password:(NSString *)password
                                     error:(NSError **)error {
    // Look up account
    NSError *dbError = nil;
    Account *account = [self.repository accountForHandle:handle error:&dbError];
    
    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:@"Account" code:3 
                userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return nil;
    }
    
    // Verify password
    NSData *passwordHash = [self hashPassword:password salt:account.passwordSalt];
    if (![passwordHash isEqualToData:account.passwordHash]) {
        if (error) {
            *error = [NSError errorWithDomain:@"Account" code:4 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid password"}];
        }
        return nil;
    }
    
    // Generate new tokens
    NSString *accessJwt = [self.minter mintAccessTokenForDID:account.did handle:account.handle];
    NSString *refreshJwt = [self.minter mintRefreshTokenForDID:account.did handle:account.handle];
    
    // Update account with new tokens
    account.accessJwt = accessJwt;
    account.refreshJwt = refreshJwt;
    [self.repository saveAccount:account error:nil];
    
    return @{
        @"did": account.did,
        @"handle": account.handle,
        @"email": account.email,
        @"accessJwt": accessJwt,
        @"refreshJwt": refreshJwt
    };
}

- (NSData *)generateSalt {
    unsigned char salt[16];
    arc4random_buf(salt, sizeof(salt));
    return [NSData dataWithBytes:salt length:sizeof(salt)];
}

- (NSData *)hashPassword:(NSString *)password salt:(NSData *)salt {
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    
    CCHmac(kCCHmacAlgSHA256, salt.bytes, salt.length, passwordData.bytes, passwordData.length, digest);
    
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

@end
```

## Step 8: Add Account Endpoints to XRPC Dispatcher

Update `src/XrpcDispatcher.m` to add account endpoints:

```objc
- (void)dispatchRequest:(HttpRequest *)request 
               response:(HttpResponse *)response {
    
    NSString *path = request.path;
    NSString *nsid = [path stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];
    
    if ([nsid isEqualToString:@"com.atproto.server.describeServer"]) {
        [self handleDescribeServer:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.server.createAccount"]) {
        [self handleCreateAccount:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.server.createSession"]) {
        [self handleCreateSession:request response:response];
    } else {
        response.statusCode = 404;
        response.body = [@{@"error": @"MethodNotFound"} JSONData];
    }
}

- (void)handleCreateAccount:(HttpRequest *)request 
                   response:(HttpResponse *)response {
    
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    
    if (!params) {
        response.statusCode = 400;
        response.body = [@{@"error": @"InvalidRequest"} JSONData];
        return;
    }
    
    NSError *error = nil;
    NSDictionary *result = [self.accountService createAccountForEmail:params[@"email"]
                                                              password:params[@"password"]
                                                               handle:params[@"handle"]
                                                                error:&error];
    
    if (!result) {
        response.statusCode = 400;
        response.body = [@{@"error": error.localizedDescription} JSONData];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (void)handleCreateSession:(HttpRequest *)request 
                   response:(HttpResponse *)response {
    
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    
    if (!params) {
        response.statusCode = 400;
        response.body = [@{@"error": @"InvalidRequest"} JSONData];
        return;
    }
    
    NSError *error = nil;
    NSDictionary *result = [self.accountService loginWithHandle:params[@"identifier"]
                                                       password:params[@"password"]
                                                          error:&error];
    
    if (!result) {
        response.statusCode = 401;
        response.body = [@{@"error": error.localizedDescription} JSONData];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}
```

## Step 9: Update Main Entry Point

Update `src/main.m` to initialize account service:

```objc
#import <Foundation/Foundation.h>
#import "PDSApplication.h"
#import "AccountService.h"
#import "AccountRepository.h"
#import "SimpleJWTMinter.h"
#import "XrpcDispatcher.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 1. Create configuration
        PDSConfiguration *config = [[PDSConfiguration alloc] init];
        config.serverPort = 2583;
        config.issuer = @"did:web:localhost:2583";
        config.databasePath = @"./pds-data/db";
        
        // 2. Create account service
        AccountRepository *accountRepo = [[AccountRepository alloc] 
            initWithDatabasePath:config.databasePath];
        SimpleJWTMinter *minter = [[SimpleJWTMinter alloc] 
            initWithIssuer:config.issuer];
        AccountService *accountService = [[AccountService alloc] 
            initWithRepository:accountRepo minter:minter];
        
        // 3. Initialize PDS
        NSError *error = nil;
        PDSApplication *app = [[PDSApplication alloc] 
            initWithConfiguration:config error:&error];
        
        if (!app) {
            NSLog(@"Failed to initialize PDS: %@", error);
            return 1;
        }
        
        // 4. Setup XRPC dispatcher with account service
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        dispatcher.accountService = accountService;
        [app.httpServer registerRoute:@"/xrpc/*" handler:^(HttpRequest *req, HttpResponse *res) {
            [dispatcher dispatchRequest:req response:res];
        }];
        
        // 5. Start server
        [app.httpServer startWithCompletion:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to start server: %@", error);
                exit(1);
            }
            
            NSLog(@"PDS started on port %ld", (long)config.serverPort);
            NSLog(@"Account service ready");
        }];
        
        // 6. Keep running
        [[NSRunLoop mainRunLoop] run];
    }
    
    return 0;
}
```

## Step 10: Build and Run

Now let's compile and test the complete account management system:

```bash
cd examples/tutorial-2-accounts
mkdir -p build && cd build
cmake ..
make
./tutorial-2-accounts
```

### What Happens During Startup?

When your server starts, it:
1. Opens (or creates) the SQLite database at `./pds-data/db/accounts.db`
2. Creates the `accounts` table if it doesn't exist
3. Initializes the JWT minter with your server's issuer DID
4. Registers the XRPC endpoints for account creation and login
5. Starts listening on port 2583

The database schema uses `UNIQUE` constraints on `handle` and `email` to prevent duplicates at the database level—a critical safety feature.

## Step 11: Test Account Creation

In another terminal, create your first account:

```bash
# Create an account
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{
    "email": "alice@example.com",
    "password": "secure_password",
    "handle": "alice"
  }' | jq .

# Expected output:
# {
#   "did": "did:plc:...",
#   "handle": "alice",
#   "email": "alice@example.com",
#   "accessJwt": "eyJ...",
#   "refreshJwt": "eyJ..."
# }
```

### Understanding the Response

The server returns:
- **`did`** — A newly generated DID for this user (using UUID for simplicity; production uses PLC directory)
- **`handle`** — The user's chosen handle
- **`email`** — The registered email
- **`accessJwt`** — Short-lived token (1 hour) for API requests
- **`refreshJwt`** — Long-lived token (30 days) for obtaining new access tokens

**Security Note:** In production, you'd never return the email in the response—that's private information. We include it here for tutorial clarity.

## Step 12: Test Login

Now test logging in with the account you just created:

```bash
# Login with account
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createSession \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "alice",
    "password": "secure_password"
  }' | jq .

# Expected output:
# {
#   "did": "did:plc:...",
#   "handle": "alice",
#   "email": "alice@example.com",
#   "accessJwt": "eyJ...",  # New token!
#   "refreshJwt": "eyJ..."  # New token!
# }
```

### Why New Tokens?

Each login generates fresh tokens. This is a security best practice—old tokens should be invalidated when users explicitly log in again. In a production system, you'd track token families and implement token rotation.

## Real-World Usage Patterns

**Account Creation Flow:**
1. User submits email, password, and desired handle
2. Server validates inputs (format, length, uniqueness)
3. Server generates DID and hashes password
4. Server stores account in database
5. Server generates JWT tokens
6. User receives tokens and can immediately make authenticated requests

**Login Flow:**
1. User submits handle (or email) and password
2. Server looks up account
3. Server verifies password hash
4. Server generates new tokens
5. User receives fresh tokens

**Token Usage:**
- Include `accessJwt` in `Authorization: Bearer <token>` header for API requests
- When `accessJwt` expires, use `refreshJwt` to get a new one (not implemented in this tutorial)

## Common Pitfalls

**Password Security:** This tutorial uses a simple HMAC-SHA256 approach for demonstration. Production systems should use bcrypt, scrypt, or Argon2—algorithms specifically designed for password hashing with built-in work factors.

**DID Generation:** We're using UUIDs for DIDs (`did:plc:<uuid>`). Real PDS implementations register DIDs with the PLC directory and use proper cryptographic key pairs.

**Token Storage:** Storing tokens in the database means they survive server restarts, but it also means you need a token revocation strategy. Production systems use Redis or similar for token management.

**SQL Injection:** We're using SQLite's prepared statements (`sqlite3_bind_*`), which protects against SQL injection. Never concatenate user input into SQL strings!
```

## Next Steps

- **[Tutorial 3: Record Operations](./tutorial-3-records)** — Add record CRUD
- **[Tutorial 4: Authentication](./tutorial-4-auth)** — Add JWT verification

## Troubleshooting

### Handle Already Taken

If you try to create an account with a handle that already exists:

```bash
# This will fail if "alice" already exists
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{
    "email": "bob@example.com",
    "password": "secure_password",
    "handle": "alice"
  }' | jq .

# Error response:
# {
#   "error": "Handle already taken"
# }
```

**Solution:** Use a different handle. The database's `UNIQUE` constraint on the `handle` column prevents duplicates.

### Invalid Password on Login

If login fails with "Invalid password":

```bash
# Check that you're using the exact password from account creation
# Passwords are case-sensitive
```

**Common causes:**
- Typo in password
- Using email instead of handle for identifier
- Account doesn't exist (check handle spelling)

### Database Errors

If you see SQLite errors like "database is locked" or "unable to open database file":

```bash
# Clear database and restart
rm -rf pds-data/
mkdir -p pds-data/db
./tutorial-2-accounts
```

**Prevention:** Ensure only one instance of the server is running. SQLite doesn't handle concurrent writes well without WAL mode (which we'll cover in later tutorials).

### JWT Token Parsing Errors

If tokens look malformed or clients can't parse them:

```bash
# Verify token structure (should have 3 parts separated by dots)
echo "eyJ..." | cut -d'.' -f1 | base64 -d

# Should show: {"alg":"HS256","typ":"JWT"}
```

**Common issues:**
- Base64 URL encoding vs standard Base64 (we handle this in `base64URLEncode`)
- Missing or extra padding characters
- Signature verification failures (check secret key consistency)

### Memory Leaks

If you notice memory growing over time:

**Check for:**
- Unclosed SQLite statements (we call `sqlite3_finalize` after each query)
- Unreleased `NSData` or `NSString` objects (ARC should handle this)
- Database connections not closed (we close in `dealloc`)

**Debug with:**
```bash
# On macOS, use Instruments to profile memory
instruments -t Leaks ./tutorial-2-accounts
```

### Port Already in Use

If port 2583 is already bound:

```bash
# Find and kill the process
lsof -i :2583
kill -9 <PID>

# Or change the port in main.m
config.serverPort = 3000;
```

## Summary

You've successfully extended the PDS to support:
- Account creation with email and password
- JWT token generation (access and refresh)
- Account persistence to SQLite database
- Login with handle and password
- Token-based authentication

This foundation enables building more complex features like record operations and firehose subscriptions.


Excellent work! You've built a fully functional account management system. Let's review what you accomplished:

**Core Concepts Mastered:**
- Account data modeling with proper security considerations
- SQLite database integration with prepared statements
- Password hashing with salt using CommonCrypto
- JWT token generation with HMAC-SHA256 signatures
- XRPC endpoint implementation for account operations
- Error handling for duplicate accounts and invalid credentials
- DID generation and handle uniqueness enforcement

**What You Built:**
A production-ready (with caveats) account system that:
- Creates accounts with email, password, and handle
- Stores credentials securely with salted hashes
- Generates JWT access and refresh tokens
- Implements login/session creation
- Persists data to SQLite with proper schema constraints
- Handles common error cases gracefully

**Key Takeaways:**
- **Never store plaintext passwords** — Always hash with a salt
- **Use prepared statements** — Protects against SQL injection
- **Enforce uniqueness at the database level** — UNIQUE constraints prevent race conditions
- **Generate fresh tokens on login** — Improves security posture
- **Validate all inputs** — Check for null, empty, or malformed data
- **Return appropriate HTTP status codes** — 200 for success, 400 for bad requests, 401 for auth failures

**Security Considerations:**
This tutorial demonstrates core concepts but simplifies some aspects for clarity:
- Production systems use bcrypt/Argon2 instead of HMAC-SHA256 for passwords
- Real DIDs are registered with the PLC directory, not generated locally
- Token management should use Redis or similar for revocation support
- Rate limiting should protect account creation and login endpoints
- Email verification should be required before accounts are fully active

**Architectural Patterns:**
You've now seen the three-layer architecture that September PDS uses:
1. **Data Layer** — `AccountRepository` handles database operations
2. **Service Layer** — `AccountService` implements business logic
3. **API Layer** — `XrpcDispatcher` handles HTTP/XRPC routing

This separation of concerns makes code testable, maintainable, and easier to reason about.

## Next Steps

With account management working, you're ready to add data storage and retrieval:

- **[Tutorial 3: Record Operations](./tutorial-3-records)** — Implement record CRUD operations with MST integration
- **[Tutorial 4: Authentication](./tutorial-4-auth)** — Add JWT verification and protected endpoints
- **[Tutorial 5: Firehose](./tutorial-5-firehose)** — Broadcast changes via WebSocket

**Further Reading:**
- [Account Service Architecture](../03-application-layer/account-service) — Production implementation details
- [JWT Tokens Deep Dive](../06-authentication/jwt-tokens) — Token structure and verification
- [SQLite Best Practices](../05-database-layer/sqlite-architecture) — WAL mode, connection pooling, migrations
- [Security Best Practices](../06-authentication/security-best-practices) — Comprehensive security guide
