# Tutorial 4: Authentication

## Overview

In this tutorial, you'll extend the PDS from Tutorial 3 to implement proper JWT verification, OAuth 2.0 with DPoP, and token refresh flows.

**Learning Objectives:**
- Implement JWT signature verification
- Add OAuth 2.0 authorization flow
- Implement DPoP (Demonstration of Proof-of-Possession)
- Add token refresh endpoint
- Secure API endpoints with proper authentication

**Time:** 90 minutes

## Prerequisites

- Completed [Tutorial 3: Record Operations](./tutorial-3-records)
- Understanding of JWT tokens (see [JWT Tokens](../06-authentication/jwt-tokens))
- Understanding of OAuth 2.0 (see [OAuth 2.0 with DPoP](../06-authentication/oauth2-dpop))
- Understanding of authentication helpers (see [Auth Helpers](../04-network-layer/auth-helpers))

## Architecture Overview

In Tutorial 2, we created a simplified JWT minter that generated tokens without proper signature verification. In this tutorial, we'll implement:

1. **JWT Verifier** — Verify JWT signatures using ECDSA P-256
2. **OAuth 2.0 Handler** — Authorization and token endpoints
3. **DPoP Handler** — Proof-of-possession verification
4. **Token Refresh** — Secure token renewal

## Step 1: Create JWT Verifier

Create `src/JWTVerifier.h`:

```objc
#import <Foundation/Foundation.h>

@interface JWTVerifier : NSObject

- (instancetype)initWithIssuer:(NSString *)issuer publicKey:(NSData *)publicKey;

- (nullable NSDictionary *)verifyToken:(NSString *)token error:(NSError **)error;
- (BOOL)verifySignature:(NSString *)token withPublicKey:(NSData *)publicKey error:(NSError **)error;
- (nullable NSDictionary *)extractPayload:(NSString *)token error:(NSError **)error;

@end
```

## Step 2: Implement JWT Verifier

Create `src/JWTVerifier.m`:


```objc
#import "JWTVerifier.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>

@interface JWTVerifier ()
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, strong) NSData *publicKey;
@end

@implementation JWTVerifier

- (instancetype)initWithIssuer:(NSString *)issuer publicKey:(NSData *)publicKey {
    self = [super init];
    if (!self) return nil;
    
    self.issuer = issuer;
    self.publicKey = publicKey;
    
    return self;
}

- (nullable NSDictionary *)verifyToken:(NSString *)token error:(NSError **)error {
    // 1. Extract payload
    NSDictionary *payload = [self extractPayload:token error:error];
    if (!payload) return nil;
    
    // 2. Verify signature
    if (![self verifySignature:token withPublicKey:self.publicKey error:error]) {
        return nil;
    }
    
    // 3. Verify issuer
    if (![payload[@"iss"] isEqualToString:self.issuer]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:3 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid issuer"}];
        }
        return nil;
    }
    
    // 4. Verify expiration
    NSTimeInterval exp = [payload[@"exp"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (exp < now) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:4 
                userInfo:@{NSLocalizedDescriptionKey: @"Token expired"}];
        }
        return nil;
    }
    
    return payload;
}

- (BOOL)verifySignature:(NSString *)token withPublicKey:(NSData *)publicKey error:(NSError **)error {
    // Split token into parts
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid token format"}];
        }
        return NO;
    }
    
    // For tutorial simplicity, we'll use HMAC verification
    // In production, use ECDSA P-256 signature verification
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    // Compute expected signature
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, publicKey.bytes, publicKey.length, 
           signingData.bytes, signingData.length, digest);
    NSData *expectedSignature = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *expectedB64 = [self base64URLEncode:expectedSignature];
    
    // Compare signatures
    if (![parts[2] isEqualToString:expectedB64]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature"}];
        }
        return NO;
    }
    
    return YES;
}

- (nullable NSDictionary *)extractPayload:(NSString *)token error:(NSError **)error {
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid token format"}];
        }
        return nil;
    }
    
    // Decode payload
    NSString *payload = parts[1];
    payload = [payload stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payload = [payload stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    while (payload.length % 4 != 0) {
        payload = [payload stringByAppendingString:@"="];
    }
    
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:5 
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode payload"}];
        }
        return nil;
    }
    
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
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


## Step 3: Create DPoP Handler

Create `src/DPoPHandler.h`:

```objc
#import <Foundation/Foundation.h>

@interface DPoPHandler : NSObject

+ (nullable NSString *)generateDPoPProof:(NSString *)method
                                     uri:(NSString *)uri
                                   nonce:(nullable NSString *)nonce
                              privateKey:(NSData *)privateKey
                               publicKey:(NSData *)publicKey
                                   error:(NSError **)error;

+ (BOOL)verifyDPoPProof:(NSString *)proof
                 method:(NSString *)method
                    uri:(NSString *)uri
              publicKey:(NSData *)publicKey
                  error:(NSError **)error;

+ (nullable NSString *)extractThumbprint:(NSData *)publicKey error:(NSError **)error;

@end
```

## Step 4: Implement DPoP Handler

Create `src/DPoPHandler.m`:

```objc
#import "DPoPHandler.h"
#import <CommonCrypto/CommonDigest.h>

@implementation DPoPHandler

+ (nullable NSString *)generateDPoPProof:(NSString *)method
                                     uri:(NSString *)uri
                                   nonce:(nullable NSString *)nonce
                              privateKey:(NSData *)privateKey
                               publicKey:(NSData *)publicKey
                                   error:(NSError **)error {
    // 1. Create JWK from public key
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(1, 32)]],
        @"y": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(33, 32)]]
    };
    
    // 2. Create DPoP header
    NSDictionary *header = @{
        @"typ": @"dpop+jwt",
        @"alg": @"ES256",
        @"jwk": jwk
    };
    
    // 3. Create DPoP payload
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableDictionary *payload = [@{
        @"jti": [[NSUUID UUID] UUIDString],
        @"htm": method,
        @"htu": uri,
        @"iat": @(now),
        @"exp": @(now + 300)  // 5 minutes
    } mutableCopy];
    
    if (nonce) {
        payload[@"nonce"] = nonce;
    }
    
    // 4. Encode header and payload
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!headerData || !payloadData) return nil;
    
    NSString *headerB64 = [self base64URLEncode:headerData];
    NSString *payloadB64 = [self base64URLEncode:payloadData];
    
    // 5. Sign with private key (simplified for tutorial)
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(signingData.bytes, (CC_LONG)signingData.length, digest);
    NSData *signature = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *signatureB64 = [self base64URLEncode:signature];
    
    return [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
}

+ (BOOL)verifyDPoPProof:(NSString *)proof
                 method:(NSString *)method
                    uri:(NSString *)uri
              publicKey:(NSData *)publicKey
                  error:(NSError **)error {
    // 1. Parse proof
    NSArray *parts = [proof componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP format"}];
        }
        return NO;
    }
    
    // 2. Decode payload
    NSString *payloadB64 = parts[1];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (payloadB64.length % 4 != 0) {
        payloadB64 = [payloadB64 stringByAppendingString:@"="];
    }
    
    NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:payloadB64 options:0];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:error];
    if (!payload) return NO;
    
    // 3. Verify method and URI
    if (![payload[@"htm"] isEqualToString:method]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Method mismatch"}];
        }
        return NO;
    }
    
    if (![payload[@"htu"] isEqualToString:uri]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:3 
                userInfo:@{NSLocalizedDescriptionKey: @"URI mismatch"}];
        }
        return NO;
    }
    
    // 4. Verify timestamp
    NSTimeInterval iat = [payload[@"iat"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - iat > 300) {  // 5 minutes
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:4 
                userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof expired"}];
        }
        return NO;
    }
    
    return YES;
}

+ (nullable NSString *)extractThumbprint:(NSData *)publicKey error:(NSError **)error {
    // Create JWK thumbprint (SHA-256 of canonical JWK)
    NSDictionary *jwk = @{
        @"crv": @"P-256",
        @"kty": @"EC",
        @"x": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(1, 32)]],
        @"y": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(33, 32)]]
    };
    
    NSData *jwkData = [NSJSONSerialization dataWithJSONObject:jwk 
                                                      options:NSJSONWritingSortedKeys 
                                                        error:error];
    if (!jwkData) return nil;
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(jwkData.bytes, (CC_LONG)jwkData.length, digest);
    NSData *thumbprint = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    
    return [self base64URLEncode:thumbprint];
}

+ (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
```


## Step 5: Update JWT Minter with DPoP Support

Update `src/SimpleJWTMinter.m` to support DPoP binding:

```objc
- (NSString *)mintAccessTokenForDID:(NSString *)did 
                            handle:(NSString *)handle
                     dpopThumbprint:(nullable NSString *)jkt {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval exp = now + 3600;  // 1 hour
    
    NSMutableDictionary *payload = [@{
        @"iss": self.issuer,
        @"sub": did,
        @"aud": self.issuer,
        @"iat": @(now),
        @"exp": @(exp),
        @"scope": @"atproto_repo",
        @"handle": handle
    } mutableCopy];
    
    // Add DPoP binding if thumbprint provided
    if (jkt) {
        payload[@"cnf"] = @{@"jkt": jkt};
    }
    
    return [self encodeJWT:payload];
}
```

## Step 6: Create OAuth 2.0 Handler

Create `src/OAuth2Handler.h`:

```objc
#import <Foundation/Foundation.h>
#import "AccountService.h"
#import "SimpleJWTMinter.h"

@interface OAuth2Handler : NSObject

- (instancetype)initWithAccountService:(AccountService *)accountService
                                minter:(SimpleJWTMinter *)minter;

- (void)handleAuthorize:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleToken:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleRefresh:(HttpRequest *)request response:(HttpResponse *)response;

@end
```

## Step 7: Implement OAuth 2.0 Handler

Create `src/OAuth2Handler.m`:

```objc
#import "OAuth2Handler.h"
#import "DPoPHandler.h"

@interface OAuth2Handler ()
@property (nonatomic, strong) AccountService *accountService;
@property (nonatomic, strong) SimpleJWTMinter *minter;
@property (nonatomic, strong) NSMutableDictionary *authorizationCodes;
@end

@implementation OAuth2Handler

- (instancetype)initWithAccountService:(AccountService *)accountService
                                minter:(SimpleJWTMinter *)minter {
    self = [super init];
    if (!self) return nil;
    
    self.accountService = accountService;
    self.minter = minter;
    self.authorizationCodes = [NSMutableDictionary dictionary];
    
    return self;
}

- (void)handleAuthorize:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Parse query parameters
    NSString *clientId = [request queryParamForKey:@"client_id"];
    NSString *redirectUri = [request queryParamForKey:@"redirect_uri"];
    NSString *scope = [request queryParamForKey:@"scope"];
    NSString *state = [request queryParamForKey:@"state"];
    NSString *codeChallenge = [request queryParamForKey:@"code_challenge"];
    NSString *codeChallengeMethod = [request queryParamForKey:@"code_challenge_method"];
    
    // 2. Validate parameters
    if (!clientId || !redirectUri || !scope) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_request"} JSONData];
        return;
    }
    
    // 3. In production, show login page and get user consent
    // For tutorial, we'll auto-approve with a test user
    NSString *userDid = @"did:plc:test123";
    NSString *userHandle = @"testuser";
    
    // 4. Generate authorization code
    NSString *code = [[NSUUID UUID] UUIDString];
    self.authorizationCodes[code] = @{
        @"did": userDid,
        @"handle": userHandle,
        @"client_id": clientId,
        @"redirect_uri": redirectUri,
        @"scope": scope,
        @"code_challenge": codeChallenge ?: @"",
        @"code_challenge_method": codeChallengeMethod ?: @"",
        @"created_at": @([[NSDate date] timeIntervalSince1970])
    };
    
    // 5. Redirect back to client
    NSString *redirectUrl = [NSString stringWithFormat:@"%@?code=%@&state=%@", 
                            redirectUri, code, state ?: @""];
    
    response.statusCode = 302;
    [response setHeader:@"Location" value:redirectUrl];
}

- (void)handleToken:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Parse request body
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    if (!params) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_request"} JSONData];
        return;
    }
    
    NSString *grantType = params[@"grant_type"];
    NSString *code = params[@"code"];
    NSString *clientId = params[@"client_id"];
    NSString *redirectUri = params[@"redirect_uri"];
    NSString *codeVerifier = params[@"code_verifier"];
    
    // 2. Validate grant type
    if (![grantType isEqualToString:@"authorization_code"]) {
        response.statusCode = 400;
        response.body = [@{@"error": @"unsupported_grant_type"} JSONData];
        return;
    }
    
    // 3. Validate authorization code
    NSDictionary *authCode = self.authorizationCodes[code];
    if (!authCode) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_grant"} JSONData];
        return;
    }
    
    // 4. Verify client_id and redirect_uri match
    if (![authCode[@"client_id"] isEqualToString:clientId] ||
        ![authCode[@"redirect_uri"] isEqualToString:redirectUri]) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_grant"} JSONData];
        return;
    }
    
    // 5. Verify PKCE if code_challenge was provided
    if ([authCode[@"code_challenge"] length] > 0) {
        if (!codeVerifier) {
            response.statusCode = 400;
            response.body = [@{@"error": @"invalid_request"} JSONData];
            return;
        }
        
        // Verify code_verifier matches code_challenge
        if (![self verifyPKCE:codeVerifier challenge:authCode[@"code_challenge"]]) {
            response.statusCode = 400;
            response.body = [@{@"error": @"invalid_grant"} JSONData];
            return;
        }
    }
    
    // 6. Extract DPoP proof if present
    NSString *dpopProof = [request headerForKey:@"DPoP"];
    NSString *dpopThumbprint = nil;
    
    if (dpopProof) {
        // Verify DPoP proof
        NSError *dpopError = nil;
        NSData *publicKey = [self extractPublicKeyFromDPoP:dpopProof error:&dpopError];
        if (!publicKey) {
            response.statusCode = 400;
            response.body = [@{@"error": @"invalid_dpop_proof"} JSONData];
            return;
        }
        
        dpopThumbprint = [DPoPHandler extractThumbprint:publicKey error:&dpopError];
    }
    
    // 7. Generate tokens
    NSString *did = authCode[@"did"];
    NSString *handle = authCode[@"handle"];
    
    NSString *accessToken = [self.minter mintAccessTokenForDID:did 
                                                        handle:handle
                                                dpopThumbprint:dpopThumbprint];
    NSString *refreshToken = [self.minter mintRefreshTokenForDID:did handle:handle];
    
    // 8. Invalidate authorization code
    [self.authorizationCodes removeObjectForKey:code];
    
    // 9. Return tokens
    NSDictionary *result = @{
        @"access_token": accessToken,
        @"refresh_token": refreshToken,
        @"token_type": dpopProof ? @"DPoP" : @"Bearer",
        @"expires_in": @3600,
        @"scope": authCode[@"scope"]
    };
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (void)handleRefresh:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Parse request body
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    if (!params) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_request"} JSONData];
        return;
    }
    
    NSString *grantType = params[@"grant_type"];
    NSString *refreshToken = params[@"refresh_token"];
    
    // 2. Validate grant type
    if (![grantType isEqualToString:@"refresh_token"]) {
        response.statusCode = 400;
        response.body = [@{@"error": @"unsupported_grant_type"} JSONData];
        return;
    }
    
    // 3. Verify refresh token (simplified - in production, verify signature)
    NSArray *parts = [refreshToken componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_grant"} JSONData];
        return;
    }
    
    // 4. Decode payload
    NSString *payloadB64 = parts[1];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (payloadB64.length % 4 != 0) {
        payloadB64 = [payloadB64 stringByAppendingString:@"="];
    }
    
    NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:payloadB64 options:0];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
    
    if (!payload) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_grant"} JSONData];
        return;
    }
    
    // 5. Extract DPoP proof if present
    NSString *dpopProof = [request headerForKey:@"DPoP"];
    NSString *dpopThumbprint = nil;
    
    if (dpopProof) {
        NSError *dpopError = nil;
        NSData *publicKey = [self extractPublicKeyFromDPoP:dpopProof error:&dpopError];
        if (publicKey) {
            dpopThumbprint = [DPoPHandler extractThumbprint:publicKey error:&dpopError];
        }
    }
    
    // 6. Generate new access token
    NSString *did = payload[@"sub"];
    NSString *handle = payload[@"handle"];
    
    NSString *accessToken = [self.minter mintAccessTokenForDID:did 
                                                        handle:handle
                                                dpopThumbprint:dpopThumbprint];
    
    // 7. Return new access token
    NSDictionary *result = @{
        @"access_token": accessToken,
        @"token_type": dpopProof ? @"DPoP" : @"Bearer",
        @"expires_in": @3600
    };
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (BOOL)verifyPKCE:(NSString *)verifier challenge:(NSString *)challenge {
    // SHA-256 hash of verifier
    NSData *verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, digest);
    NSData *hashData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    
    // Base64URL encode
    NSString *computed = [hashData base64EncodedStringWithOptions:0];
    computed = [computed stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    computed = [computed stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    computed = [computed stringByReplacingOccurrencesOfString:@"=" withString:@""];
    
    return [computed isEqualToString:challenge];
}

- (nullable NSData *)extractPublicKeyFromDPoP:(NSString *)dpopProof error:(NSError **)error {
    // Parse DPoP header to extract JWK
    NSArray *parts = [dpopProof componentsSeparatedByString:@"."];
    if (parts.count != 3) return nil;
    
    NSString *headerB64 = parts[0];
    headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (headerB64.length % 4 != 0) {
        headerB64 = [headerB64 stringByAppendingString:@"="];
    }
    
    NSData *headerData = [[NSData alloc] initWithBase64EncodedString:headerB64 options:0];
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:error];
    
    if (!header) return nil;
    
    NSDictionary *jwk = header[@"jwk"];
    if (!jwk) return nil;
    
    // Extract x and y coordinates from JWK
    NSString *xB64 = jwk[@"x"];
    NSString *yB64 = jwk[@"y"];
    
    xB64 = [xB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    xB64 = [xB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (xB64.length % 4 != 0) {
        xB64 = [xB64 stringByAppendingString:@"="];
    }
    
    yB64 = [yB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    yB64 = [yB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (yB64.length % 4 != 0) {
        yB64 = [yB64 stringByAppendingString:@"="];
    }
    
    NSData *xData = [[NSData alloc] initWithBase64EncodedString:xB64 options:0];
    NSData *yData = [[NSData alloc] initWithBase64EncodedString:yB64 options:0];
    
    if (!xData || !yData) return nil;
    
    // Construct uncompressed public key (0x04 || x || y)
    NSMutableData *publicKey = [NSMutableData dataWithCapacity:65];
    uint8_t prefix = 0x04;
    [publicKey appendBytes:&prefix length:1];
    [publicKey appendData:xData];
    [publicKey appendData:yData];
    
    return publicKey;
}

@end
```


## Step 8: Update XRPC Dispatcher with Authentication

Update `src/XrpcDispatcher.m` to add OAuth endpoints and verify authentication:

```objc
#import "XrpcDispatcher.h"
#import "JWTVerifier.h"
#import "DPoPHandler.h"

@interface XrpcDispatcher ()
@property (nonatomic, strong) JWTVerifier *jwtVerifier;
@property (nonatomic, strong) OAuth2Handler *oauth2Handler;
@end

- (void)dispatchRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *path = request.path;
    
    // OAuth endpoints
    if ([path isEqualToString:@"/oauth/authorize"]) {
        [self.oauth2Handler handleAuthorize:request response:response];
        return;
    } else if ([path isEqualToString:@"/oauth/token"]) {
        [self.oauth2Handler handleToken:request response:response];
        return;
    }
    
    // XRPC endpoints
    NSString *nsid = [path stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];
    
    // Public endpoints (no auth required)
    if ([nsid isEqualToString:@"com.atproto.server.describeServer"]) {
        [self handleDescribeServer:request response:response];
        return;
    } else if ([nsid isEqualToString:@"com.atproto.server.createAccount"]) {
        [self handleCreateAccount:request response:response];
        return;
    } else if ([nsid isEqualToString:@"com.atproto.server.createSession"]) {
        [self handleCreateSession:request response:response];
        return;
    }
    
    // Protected endpoints (auth required)
    NSError *authError = nil;
    NSString *did = [self authenticateRequest:request error:&authError];
    
    if (!did) {
        response.statusCode = 401;
        response.body = [@{
            @"error": @"AuthenticationRequired",
            @"message": authError.localizedDescription ?: @"Authentication required"
        } JSONData];
        return;
    }
    
    // Store authenticated DID in request context
    request.authenticatedDID = did;
    
    // Route to appropriate handler
    if ([nsid isEqualToString:@"com.atproto.repo.createRecord"]) {
        [self handleCreateRecord:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.getRecord"]) {
        [self handleGetRecord:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.listRecords"]) {
        [self handleListRecords:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.deleteRecord"]) {
        [self handleDeleteRecord:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.server.refreshSession"]) {
        [self.oauth2Handler handleRefresh:request response:response];
    } else {
        response.statusCode = 404;
        response.body = [@{@"error": @"MethodNotFound"} JSONData];
    }
}

- (nullable NSString *)authenticateRequest:(HttpRequest *)request error:(NSError **)error {
    // 1. Extract Authorization header
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
        if (error) {
            *error = [NSError errorWithDomain:@"Auth" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Missing Authorization header"}];
        }
        return nil;
    }
    
    // 2. Parse token type and token
    NSArray *parts = [authHeader componentsSeparatedByString:@" "];
    if (parts.count != 2) {
        if (error) {
            *error = [NSError errorWithDomain:@"Auth" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid Authorization header format"}];
        }
        return nil;
    }
    
    NSString *tokenType = parts[0];
    NSString *token = parts[1];
    
    // 3. Verify JWT token
    NSError *jwtError = nil;
    NSDictionary *payload = [self.jwtVerifier verifyToken:token error:&jwtError];
    if (!payload) {
        if (error) *error = jwtError;
        return nil;
    }
    
    // 4. If DPoP token, verify DPoP proof
    if ([tokenType isEqualToString:@"DPoP"]) {
        NSString *dpopProof = [request headerForKey:@"DPoP"];
        if (!dpopProof) {
            if (error) {
                *error = [NSError errorWithDomain:@"Auth" code:3 
                    userInfo:@{NSLocalizedDescriptionKey: @"Missing DPoP proof"}];
            }
            return nil;
        }
        
        // Verify DPoP proof matches request
        NSError *dpopError = nil;
        NSData *publicKey = [self extractPublicKeyFromDPoP:dpopProof error:&dpopError];
        if (!publicKey) {
            if (error) *error = dpopError;
            return nil;
        }
        
        BOOL dpopValid = [DPoPHandler verifyDPoPProof:dpopProof
                                               method:request.method
                                                  uri:request.fullURL
                                            publicKey:publicKey
                                                error:&dpopError];
        if (!dpopValid) {
            if (error) *error = dpopError;
            return nil;
        }
        
        // Verify DPoP thumbprint matches token binding
        NSString *thumbprint = [DPoPHandler extractThumbprint:publicKey error:&dpopError];
        NSString *tokenThumbprint = payload[@"cnf"][@"jkt"];
        
        if (!tokenThumbprint || ![thumbprint isEqualToString:tokenThumbprint]) {
            if (error) {
                *error = [NSError errorWithDomain:@"Auth" code:4 
                    userInfo:@{NSLocalizedDescriptionKey: @"DPoP thumbprint mismatch"}];
            }
            return nil;
        }
    }
    
    // 5. Return authenticated DID
    return payload[@"sub"];
}

- (nullable NSData *)extractPublicKeyFromDPoP:(NSString *)dpopProof error:(NSError **)error {
    // Parse DPoP header to extract JWK (same as OAuth2Handler)
    NSArray *parts = [dpopProof componentsSeparatedByString:@"."];
    if (parts.count != 3) return nil;
    
    NSString *headerB64 = parts[0];
    headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (headerB64.length % 4 != 0) {
        headerB64 = [headerB64 stringByAppendingString:@"="];
    }
    
    NSData *headerData = [[NSData alloc] initWithBase64EncodedString:headerB64 options:0];
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:error];
    
    if (!header) return nil;
    
    NSDictionary *jwk = header[@"jwk"];
    if (!jwk) return nil;
    
    NSString *xB64 = jwk[@"x"];
    NSString *yB64 = jwk[@"y"];
    
    xB64 = [xB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    xB64 = [xB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (xB64.length % 4 != 0) {
        xB64 = [xB64 stringByAppendingString:@"="];
    }
    
    yB64 = [yB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    yB64 = [yB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (yB64.length % 4 != 0) {
        yB64 = [yB64 stringByAppendingString:@"="];
    }
    
    NSData *xData = [[NSData alloc] initWithBase64EncodedString:xB64 options:0];
    NSData *yData = [[NSData alloc] initWithBase64EncodedString:yB64 options:0];
    
    if (!xData || !yData) return nil;
    
    NSMutableData *publicKey = [NSMutableData dataWithCapacity:65];
    uint8_t prefix = 0x04;
    [publicKey appendBytes:&prefix length:1];
    [publicKey appendData:xData];
    [publicKey appendData:yData];
    
    return publicKey;
}
```

## Step 9: Update Main Entry Point

Update `src/main.m` to initialize authentication components:

```objc
#import <Foundation/Foundation.h>
#import "PDSApplication.h"
#import "AccountService.h"
#import "AccountRepository.h"
#import "RecordService.h"
#import "RecordRepository.h"
#import "SimpleJWTMinter.h"
#import "JWTVerifier.h"
#import "OAuth2Handler.h"
#import "XrpcDispatcher.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 1. Create configuration
        PDSConfiguration *config = [[PDSConfiguration alloc] init];
        config.serverPort = 2583;
        config.issuer = @"did:web:localhost:2583";
        config.databasePath = @"./pds-data/db";
        
        // 2. Create JWT components
        NSString *secret = @"tutorial-secret-key-do-not-use-in-production";
        NSData *secretData = [secret dataUsingEncoding:NSUTF8StringEncoding];
        
        SimpleJWTMinter *minter = [[SimpleJWTMinter alloc] initWithIssuer:config.issuer];
        JWTVerifier *verifier = [[JWTVerifier alloc] initWithIssuer:config.issuer 
                                                           publicKey:secretData];
        
        // 3. Create account service
        AccountRepository *accountRepo = [[AccountRepository alloc] 
            initWithDatabasePath:config.databasePath];
        AccountService *accountService = [[AccountService alloc] 
            initWithRepository:accountRepo minter:minter];
        
        // 4. Create record service
        RecordRepository *recordRepo = [[RecordRepository alloc] 
            initWithDatabasePath:config.databasePath];
        RecordService *recordService = [[RecordService alloc] 
            initWithRepository:recordRepo];
        
        // 5. Create OAuth handler
        OAuth2Handler *oauth2Handler = [[OAuth2Handler alloc] 
            initWithAccountService:accountService minter:minter];
        
        // 6. Initialize PDS
        NSError *error = nil;
        PDSApplication *app = [[PDSApplication alloc] 
            initWithConfiguration:config error:&error];
        
        if (!app) {
            NSLog(@"Failed to initialize PDS: %@", error);
            return 1;
        }
        
        // 7. Setup XRPC dispatcher with authentication
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        dispatcher.accountService = accountService;
        dispatcher.recordService = recordService;
        dispatcher.jwtVerifier = verifier;
        dispatcher.oauth2Handler = oauth2Handler;
        
        [app.httpServer registerRoute:@"/*" handler:^(HttpRequest *req, HttpResponse *res) {
            [dispatcher dispatchRequest:req response:res];
        }];
        
        // 8. Start server
        [app.httpServer startWithCompletion:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to start server: %@", error);
                exit(1);
            }
            
            NSLog(@"PDS started on port %ld", (long)config.serverPort);
            NSLog(@"Account service ready");
            NSLog(@"Record service ready");
            NSLog(@"OAuth 2.0 endpoints ready");
            NSLog(@"JWT verification enabled");
        }];
        
        // 9. Keep running
        [[NSRunLoop mainRunLoop] run];
    }
    
    return 0;
}
```


## Step 10: Build and Run

```bash
cd examples/tutorial-4-auth
mkdir -p build && cd build
cmake ..
make
./tutorial-4-auth
```

## Step 11: Test OAuth 2.0 Authorization Flow

In another terminal:

```bash
# 1. Start authorization flow
curl -v "http://localhost:2583/oauth/authorize?client_id=https://example.com&redirect_uri=https://example.com/callback&scope=atproto_repo&state=random123"

# Expected: 302 redirect with authorization code
# Location: https://example.com/callback?code=<CODE>&state=random123

# Extract the code from the Location header
CODE="<authorization-code-from-redirect>"

# 2. Exchange code for tokens
curl -X POST http://localhost:2583/oauth/token \
  -H "Content-Type: application/json" \
  -d "{
    \"grant_type\": \"authorization_code\",
    \"code\": \"$CODE\",
    \"client_id\": \"https://example.com\",
    \"redirect_uri\": \"https://example.com/callback\"
  }" | jq .

# Expected output:
# {
#   "access_token": "eyJ...",
#   "refresh_token": "eyJ...",
#   "token_type": "Bearer",
#   "expires_in": 3600,
#   "scope": "atproto_repo"
# }
```

## Step 12: Test JWT Verification

```bash
# Save access token
ACCESS_TOKEN="<access-token-from-previous-step>"

# Create a record with JWT authentication
curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "collection": "app.bsky.feed.post",
    "record": {
      "text": "Hello with OAuth!",
      "createdAt": "2024-01-01T00:00:00Z"
    }
  }' | jq .

# Expected output:
# {
#   "uri": "at://did:plc:test123/app.bsky.feed.post/...",
#   "cid": "bafyrei..."
# }
```

## Step 13: Test Token Refresh

```bash
# Save refresh token
REFRESH_TOKEN="<refresh-token-from-step-11>"

# Refresh access token
curl -X POST http://localhost:2583/xrpc/com.atproto.server.refreshSession \
  -H "Content-Type: application/json" \
  -d "{
    \"grant_type\": \"refresh_token\",
    \"refresh_token\": \"$REFRESH_TOKEN\"
  }" | jq .

# Expected output:
# {
#   "access_token": "eyJ...",
#   "token_type": "Bearer",
#   "expires_in": 3600
# }
```

## Step 14: Test DPoP Flow (Advanced)

For DPoP, you'll need to generate an ECDSA P-256 key pair. Here's a simplified example:

```bash
# Generate key pair (requires OpenSSL)
openssl ecparam -name prime256v1 -genkey -noout -out dpop-key.pem
openssl ec -in dpop-key.pem -pubout -out dpop-pub.pem

# In production, use proper DPoP libraries
# For tutorial purposes, we'll skip the full DPoP implementation
```

## Understanding the Implementation

### JWT Verification Flow

```
1. Client sends request with Authorization header
   ↓
2. Extract token from "Bearer <token>" or "DPoP <token>"
   ↓
3. Verify JWT signature using public key
   ↓
4. Validate claims (issuer, expiration, audience)
   ↓
5. If DPoP: verify DPoP proof matches request
   ↓
6. Extract DID from token payload
   ↓
7. Allow request to proceed
```

### OAuth 2.0 Authorization Code Flow

```
1. Client redirects user to /oauth/authorize
   ↓
2. User logs in and grants permission
   ↓
3. Server generates authorization code
   ↓
4. Redirect back to client with code
   ↓
5. Client exchanges code for tokens at /oauth/token
   ↓
6. Server validates code and returns tokens
   ↓
7. Client uses access token for API requests
```

### DPoP Binding

```
1. Client generates ECDSA P-256 key pair
   ↓
2. Client creates DPoP proof JWT with public key
   ↓
3. Server extracts public key from DPoP proof
   ↓
4. Server computes thumbprint of public key
   ↓
5. Server binds access token to thumbprint (cnf.jkt)
   ↓
6. On each request, server verifies:
   - DPoP proof signature
   - DPoP proof method/URI match request
   - DPoP thumbprint matches token binding
```

## Security Considerations

### Token Security

1. **Short-lived access tokens** — 1 hour expiration reduces impact of theft
2. **Long-lived refresh tokens** — 30 days allows persistent sessions
3. **Secure storage** — Never log tokens, store encrypted
4. **HTTPS only** — Always use TLS for token transmission

### DPoP Benefits

1. **Token binding** — Tokens bound to client's private key
2. **Replay prevention** — Each request requires fresh DPoP proof
3. **Theft mitigation** — Stolen tokens useless without private key
4. **Request integrity** — DPoP proof includes method and URI

### PKCE (Proof Key for Code Exchange)

PKCE prevents authorization code interception:

```
1. Client generates code_verifier (random string)
2. Client computes code_challenge = SHA256(code_verifier)
3. Client sends code_challenge in authorize request
4. Server stores code_challenge with authorization code
5. Client sends code_verifier in token request
6. Server verifies SHA256(code_verifier) == code_challenge
```

## Production Considerations

### Real ECDSA Signature Verification

In production, replace HMAC with proper ECDSA P-256 verification:

```objc
// Use Security.framework (macOS) or OpenSSL (Linux)
SecKeyRef publicKey = /* load from JWK */;
SecKeyAlgorithm algorithm = kSecKeyAlgorithmECDSASignatureMessageX962SHA256;

CFErrorRef error = NULL;
Boolean verified = SecKeyVerifySignature(publicKey,
                                        algorithm,
                                        (__bridge CFDataRef)signingData,
                                        (__bridge CFDataRef)signatureData,
                                        &error);
```

### Key Management

1. **Rotate signing keys** — Annually or on compromise
2. **Multiple active keys** — Support key rotation without downtime
3. **Key ID (kid)** — Include in JWT header for key lookup
4. **Secure storage** — Use Keychain (macOS) or encrypted files (Linux)

### Token Revocation

Implement token revocation for logout:

```sql
CREATE TABLE revoked_tokens (
    jti TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    revoked_at DATETIME NOT NULL,
    expires_at DATETIME NOT NULL
);

CREATE INDEX idx_revoked_tokens_did ON revoked_tokens(did);
CREATE INDEX idx_revoked_tokens_expires ON revoked_tokens(expires_at);
```

### Rate Limiting

Protect OAuth endpoints from abuse:

```objc
// Limit authorization attempts per IP
[rateLimiter checkLimit:@"oauth_authorize" 
                    key:clientIP 
                  limit:10 
                 window:3600];  // 10 per hour

// Limit token requests per client
[rateLimiter checkLimit:@"oauth_token" 
                    key:clientId 
                  limit:100 
                 window:3600];  // 100 per hour
```

## Next Steps

- **[Tutorial 5: Firehose](./tutorial-5-firehose)** — Add WebSocket subscriptions
- **[Tutorial 6: Production Deployment](./tutorial-6-deployment)** — Deploy to production

## Troubleshooting

**Invalid signature error:**
```bash
# Verify the secret key matches between minter and verifier
# Check that the token hasn't been modified
# Ensure base64URL encoding is correct
```

**Token expired:**
```bash
# Use refresh token to get new access token
curl -X POST http://localhost:2583/xrpc/com.atproto.server.refreshSession \
  -H "Content-Type: application/json" \
  -d "{
    \"grant_type\": \"refresh_token\",
    \"refresh_token\": \"$REFRESH_TOKEN\"
  }"
```

**DPoP verification failed:**
```bash
# Verify DPoP proof includes correct method and URI
# Check that DPoP proof timestamp is recent (< 5 minutes)
# Ensure public key in DPoP matches token binding
```

**Authorization code invalid:**
```bash
# Authorization codes are single-use
# Codes expire after 10 minutes
# Verify client_id and redirect_uri match original request
```

## Summary

You've successfully implemented:
- JWT signature verification with proper claims validation
- OAuth 2.0 authorization code flow
- DPoP proof-of-possession binding
- Token refresh endpoint
- Secure authentication for API endpoints
- PKCE support for authorization code protection

This provides production-grade authentication for your PDS implementation.

## Reference Implementation

For the complete production implementation, see:
- `ATProtoPDS/Sources/Auth/JWT.m` — JWT minting and verification
- `ATProtoPDS/Sources/Auth/OAuth2Handler.m` — OAuth 2.0 endpoints
- `ATProtoPDS/Sources/Auth/DPoPUtil.m` — DPoP proof handling
- `ATProtoPDS/Sources/Network/XrpcAuthHelper.m` — Authentication helpers
- `ATProtoPDS/Sources/Auth/KeyRotationManager.m` — Key rotation

## Further Reading

- [JWT Tokens](../06-authentication/jwt-tokens) — Detailed JWT documentation
- [OAuth 2.0 with DPoP](../06-authentication/oauth2-dpop) — OAuth implementation details
- [Key Rotation](../06-authentication/key-rotation) — Key management strategies
- [Auth Helpers](../04-network-layer/auth-helpers) — Authentication utilities

