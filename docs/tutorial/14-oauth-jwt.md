# Chapter 14: OAuth 2.1 & JWT Authentication

AT Protocol uses OAuth 2.1 with PKCE for client authentication and JWTs for session tokens. This chapter covers implementing the authentication flow.

## JWT Structure

```
header.payload.signature
   │       │        │
   ▼       ▼        ▼
base64   base64   base64
(JSON)   (JSON)   (bytes)
```

## JWT Classes

```objc
// JWT.h
@interface JWTHeader : NSObject
@property (nonatomic, copy) NSString *alg;   // "ES256K" for secp256k1
@property (nonatomic, copy) NSString *typ;   // "JWT"
@property (nonatomic, copy) NSString *kid;   // Key identifier
@end

@interface JWTPayload : NSObject
@property (nonatomic, copy) NSString *iss;   // Issuer (PDS DID)
@property (nonatomic, copy) NSString *sub;   // Subject (user DID)
@property (nonatomic, copy) NSString *aud;   // Audience
@property (nonatomic, strong) NSDate *exp;   // Expiration
@property (nonatomic, strong) NSDate *iat;   // Issued at
@property (nonatomic, copy) NSString *scope; // OAuth scopes
@end

@interface JWT : NSObject
@property (nonatomic, strong, readonly) JWTHeader *header;
@property (nonatomic, strong, readonly) JWTPayload *payload;

+ (nullable instancetype)jwtWithToken:(NSString *)token error:(NSError **)error;
- (NSString *)encodedToken;
- (NSString *)signingInput;
@end
```

## Base64URL Encoding

```objc
+ (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    
    // Convert to URL-safe
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    
    // Remove padding
    base64 = [base64 stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@"="]];
    
    return base64;
}

+ (NSData *)base64URLDecode:(NSString *)string {
    // Restore standard base64
    NSMutableString *base64 = [string mutableCopy];
    [base64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
    
    // Add padding
    while (base64.length % 4 != 0) {
        [base64 appendString:@"="];
    }
    
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}
```

## JWT Minting

```objc
@interface JWTMinter : NSObject
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, strong) NSData *privateKey;
@property (nonatomic, assign) NSTimeInterval defaultExpiration;

- (JWT *)mintAccessTokenForDID:(NSString *)did 
                        handle:(NSString *)handle 
                        scopes:(NSArray<NSString *> *)scopes 
                         error:(NSError **)error;
@end

@implementation JWTMinter

- (JWT *)mintAccessTokenForDID:(NSString *)did 
                        handle:(NSString *)handle 
                        scopes:(NSArray<NSString *> *)scopes 
                         error:(NSError **)error {
    // Build header
    JWTHeader *header = [[JWTHeader alloc] init];
    header.alg = @"ES256K";
    header.typ = @"JWT";
    
    // Build payload
    JWTPayload *payload = [[JWTPayload alloc] init];
    payload.iss = self.issuer;
    payload.sub = did;
    payload.iat = [NSDate date];
    payload.exp = [NSDate dateWithTimeIntervalSinceNow:self.defaultExpiration];
    payload.scope = [scopes componentsJoinedByString:@" "];
    
    // Create signing input
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:[header toDictionary] 
                                                          options:0 error:nil];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:[payload toDictionary] 
                                                           options:0 error:nil];
    
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@",
        [JWT base64URLEncode:headerData],
        [JWT base64URLEncode:payloadData]];
    
    // Sign with secp256k1
    NSData *hash = [CID rawSha256:[signingInput dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *signature = [[Secp256k1 shared] signHash:hash 
                                      withPrivateKey:self.privateKey 
                                               error:error];
    if (!signature) return nil;
    
    NSString *encodedSig = [JWT base64URLEncode:signature];
    
    return [JWT jwtWithHeader:header payload:payload signature:encodedSig error:error];
}

@end
```

## JWT Verification

```objc
@interface JWTVerifier : NSObject
@property (nonatomic, copy) NSString *expectedIssuer;
@property (nonatomic, strong) NSData *publicKey;

- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error;
@end

@implementation JWTVerifier

- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error {
    // 1. Check expiration
    if ([jwt.payload.exp compare:[NSDate date]] == NSOrderedAscending) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorTokenExpired
                                     userInfo:@{NSLocalizedDescriptionKey: @"Token expired"}];
        }
        return NO;
    }
    
    // 2. Check issuer
    if (![jwt.payload.iss isEqualToString:self.expectedIssuer]) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidIssuer
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid issuer"}];
        }
        return NO;
    }
    
    // 3. Verify signature
    NSString *signingInput = [jwt signingInput];
    NSData *hash = [CID rawSha256:[signingInput dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *signature = [JWT base64URLDecode:jwt.encodedSignature];
    
    BOOL valid = [[Secp256k1 shared] verifySignature:signature 
                                             forHash:hash 
                                       withPublicKey:self.publicKey 
                                               error:error];
    if (!valid) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature"}];
        }
        return NO;
    }
    
    return YES;
}

@end
```

## OAuth 2.1 Authorization Flow

```objc
// 1. Client initiates authorization
// GET /oauth/authorize?client_id=...&redirect_uri=...&code_challenge=...

// 2. User authenticates and consents
// Redirect to redirect_uri with authorization code

// 3. Client exchanges code for tokens
// POST /oauth/token
- (void)handleTokenRequest:(HttpRequest *)req response:(HttpResponse *)resp {
    NSDictionary *body = [req formBody];
    NSString *grantType = body[@"grant_type"];
    
    if ([grantType isEqualToString:@"authorization_code"]) {
        [self handleAuthorizationCodeGrant:body response:resp];
    } else if ([grantType isEqualToString:@"refresh_token"]) {
        [self handleRefreshTokenGrant:body response:resp];
    } else {
        resp.statusCode = 400;
        [resp setJsonBody:@{@"error": @"unsupported_grant_type"}];
    }
}

- (void)handleAuthorizationCodeGrant:(NSDictionary *)body 
                            response:(HttpResponse *)resp {
    NSString *code = body[@"code"];
    NSString *codeVerifier = body[@"code_verifier"];
    
    // Validate code and PKCE verifier
    AuthorizationCode *authCode = [self.database getAuthorizationCode:code];
    if (!authCode || ![self verifyPKCE:codeVerifier challenge:authCode.codeChallenge]) {
        resp.statusCode = 400;
        [resp setJsonBody:@{@"error": @"invalid_grant"}];
        return;
    }
    
    // Mint tokens
    NSError *error = nil;
    JWT *accessToken = [self.jwtMinter mintAccessTokenForDID:authCode.did 
                                                      handle:authCode.handle 
                                                      scopes:authCode.scopes 
                                                       error:&error];
    JWT *refreshToken = [self.jwtMinter mintRefreshTokenForDID:authCode.did 
                                                        handle:authCode.handle 
                                                        scopes:authCode.scopes 
                                                         error:&error];
    
    resp.statusCode = 200;
    [resp setJsonBody:@{
        @"access_token": [accessToken encodedToken],
        @"refresh_token": [refreshToken encodedToken],
        @"token_type": @"Bearer",
        @"expires_in": @3600,
        @"scope": [authCode.scopes componentsJoinedByString:@" "]
    }];
}
```

## Summary

In this chapter, you learned:

- ✅ JWT structure and base64URL encoding
- ✅ Minting access and refresh tokens
- ✅ Signature verification with secp256k1
- ✅ OAuth 2.1 authorization code flow
- ✅ PKCE verification

---

**Files Referenced in This Chapter:**
- [JWT.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Auth/JWT.h)
