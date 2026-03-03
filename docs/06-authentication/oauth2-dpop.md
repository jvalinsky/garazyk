# OAuth 2.0 with DPoP

## Overview

The PDS implements OAuth 2.0 with Demonstration of Proof-of-Possession (DPoP) for secure token-based authentication. DPoP binds access tokens to a specific client's public key, preventing token theft and replay attacks.

## OAuth 2.0 Flow

```
┌─────────────┐                                    ┌──────────────┐
│   Client    │                                    │   PDS        │
└──────┬──────┘                                    └──────┬───────┘
       │                                                  │
       │ 1. Authorization Request                        │
       ├─────────────────────────────────────────────────>│
       │    (client_id, redirect_uri, scope)             │
       │                                                  │
       │ 2. User Login & Consent                         │
       │<─────────────────────────────────────────────────┤
       │    (redirect to login page)                      │
       │                                                  │
       │ 3. Authorization Code                           │
       │<─────────────────────────────────────────────────┤
       │    (code, state)                                 │
       │                                                  │
       │ 4. Token Request                                │
       ├─────────────────────────────────────────────────>│
       │    (code, client_id, client_secret)             │
       │                                                  │
       │ 5. Access Token + Refresh Token                 │
       │<─────────────────────────────────────────────────┤
       │    (access_token, refresh_token, expires_in)    │
       │                                                  │
       │ 6. API Request with DPoP Proof                  │
       ├─────────────────────────────────────────────────>│
       │    (Authorization: DPoP <token>)                 │
       │    (DPoP: <proof>)                               │
       │                                                  │
       │ 7. API Response                                 │
       │<─────────────────────────────────────────────────┤
       │                                                  │
```

## DPoP (Demonstration of Proof-of-Possession)

DPoP proves the client possesses a specific private key:

### DPoP Proof Structure

```json
{
  "typ": "dpop+jwt",
  "alg": "ES256",
  "jwk": {
    "kty": "EC",
    "crv": "P-256",
    "x": "base64url-encoded-x",
    "y": "base64url-encoded-y"
  }
}
.
{
  "jti": "unique-request-id",
  "htm": "POST",
  "htu": "https://pds.example.com/xrpc/com.atproto.repo.createRecord",
  "iat": 1631551600,
  "exp": 1631551660,
  "nonce": "server-provided-nonce"
}
.
<signature>
```

### DPoP Verification

```objc
// 1. Parse DPoP proof
NSDictionary *dpopHeader = [JWT parseHeader:dpopProof];
NSDictionary *dpopPayload = [JWT parsePayload:dpopProof];

// 2. Verify DPoP signature
SecKeyRef dpopKey = [self extractPublicKeyFromJWK:dpopHeader[@"jwk"]];
BOOL dpopValid = [JWT verifySignature:dpopProof withKey:dpopKey];

// 3. Verify DPoP claims
BOOL methodMatches = [dpopPayload[@"htm"] isEqualToString:request.method];
BOOL urlMatches = [dpopPayload[@"htu"] isEqualToString:request.url];
BOOL nonceValid = [self validateNonce:dpopPayload[@"nonce"]];
BOOL timestampValid = [self validateTimestamp:dpopPayload[@"iat"]];

// 4. Extract thumbprint
NSString *thumbprint = [self generateThumbprint:dpopHeader[@"jwk"]];

// 5. Verify access token binding
BOOL thumbprintMatches = [accessTokenPayload[@"cnf"][@"jkt"] isEqualToString:thumbprint];
```

## Implementation

### OAuth 2.0 Handler

The `OAuth2Handler` class manages authorization and token endpoints:

```objc
@interface OAuth2Handler : NSObject

// Authorization endpoint
- (void)handleAuthorizeRequest:(HttpRequest *)request
                      response:(HttpResponse *)response;

// Token endpoint
- (void)handleTokenRequest:(HttpRequest *)request
                  response:(HttpResponse *)response;

// Revocation endpoint
- (void)handleRevokeRequest:(HttpRequest *)request
                   response:(HttpResponse *)response;

// JWKS endpoint for public keys
- (void)handleJWKS:(HttpRequest *)request response:(HttpResponse *)response;

@end
```

**Source:** `ATProtoPDS/Sources/Auth/OAuth2Handler.m`

### Client Validation

Clients are validated against database records or provided client_metadata:

```objc
// In OAuth2Handler.m (ATProtoPDS/Sources/Auth/OAuth2Handler.m)
- (void)validateClient:(NSString *)clientID
            completion:(void (^)(NSDictionary *_Nullable client,
                                 NSError *_Nullable error))completion {
    if (!completion) return;

    if (!clientID) {
        completion(nil, [NSError errorWithDomain:@"OAuth2"
                                            code:400
                                        userInfo:@{
                                          NSLocalizedDescriptionKey :
                                              @"Missing client_id"
                                        }]);
        return;
    }

    // 1. First attempt: Query database for registered client
    NSError *dbError = nil;
    NSDictionary *client = [self.database getClientWithID:clientID error:&dbError];
    if (client) {
        completion(client, nil);
        return;
    }

    // 2. If not in database, check client_metadata in request
    if (self.clientMetadata) {
        NSError *metadataError = nil;
        NSDictionary *validatedClient =
            [self validateClientMetadata:self.clientMetadata error:&metadataError];

        if (validatedClient) {
            NSString *metadataClientID = validatedClient[@"client_id"];
            if (metadataClientID.length == 0 ||
                ![CryptoUtils constantTimeCompare:metadataClientID to:clientID]) {
                completion(nil, [NSError errorWithDomain:@"OAuth2"
                                                    code:400
                                                userInfo:@{
                                                  NSLocalizedDescriptionKey :
                                                      @"client_id does not match client_metadata"
                                                }]);
                return;
            }
            completion(validatedClient, nil);
            return;
        } else {
            completion(nil, metadataError);
            return;
        }
    }

    // 3. Not found in DB and not in request
    completion(nil, [NSError errorWithDomain:@"OAuth2"
                                        code:401
                                    userInfo:@{
                                      NSLocalizedDescriptionKey : @"Invalid client"
                                    }]);
}
```

**Source:** `ATProtoPDS/Sources/Auth/OAuth2Handler.m` lines 50-150

### Client Metadata Validation

Client metadata must be validated for security:

```objc
// In OAuth2Handler.m (ATProtoPDS/Sources/Auth/OAuth2Handler.m)
- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata
                                   error:(NSError **)error {
    if (!metadata || ![metadata isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2"
                                           code:400
                                       userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             @"client_metadata must be a JSON object"
                                       }];
        }
        return nil;
    }

    // 1. Validate client_id is HTTPS URL (required by ATProto spec)
    NSString *clientID = metadata[@"client_id"];
    if (!clientID || ![clientID isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2"
                                           code:400
                                       userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             @"client_id is required in client_metadata"
                                       }];
        }
        return nil;
    }

    if (![clientID hasPrefix:@"https://"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2"
                                           code:400
                                       userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             @"client_id must be an HTTPS URL per ATProto OAuth specification"
                                       }];
        }
        return nil;
    }

    // 2. Validate it's a valid URL
    NSURL *clientIDURL = [NSURL URLWithString:clientID];
    if (!clientIDURL || !clientIDURL.host) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2"
                                           code:400
                                       userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             @"client_id must be a valid HTTPS URL"
                                       }];
        }
        return nil;
    }

    // 3. Validate redirect_uris array
    NSArray *redirectURIs = metadata[@"redirect_uris"];
    if (!redirectURIs || ![redirectURIs isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError
                errorWithDomain:@"OAuth2"
                           code:400
                       userInfo:@{
                         NSLocalizedDescriptionKey :
                             @"redirect_uris array is required in client_metadata"
                       }];
        }
        return nil;
    }

    if (redirectURIs.count == 0) {
        if (error) {
            *error = [NSError
                errorWithDomain:@"OAuth2"
                           code:400
                       userInfo:@{
                         NSLocalizedDescriptionKey :
                             @"redirect_uris array must contain at least one URI"
                       }];
        }
        return nil;
    }

    // 4. Validate each redirect_uri
    for (id redirectURI in redirectURIs) {
        if (![redirectURI isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"OAuth2"
                                               code:400
                                           userInfo:@{
                                             NSLocalizedDescriptionKey :
                                                 @"All redirect_uris must be strings"
                                           }];
            }
            return nil;
        }

        NSString *uriString = (NSString *)redirectURI;
        NSURL *uri = [NSURL URLWithString:uriString];
        if (!uri || !uri.scheme) {
            if (error) {
                *error = [NSError
                    errorWithDomain:@"OAuth2"
                               code:400
                           userInfo:@{
                             NSLocalizedDescriptionKey :
                                 [NSString stringWithFormat:@"Invalid redirect_uri: %@",
                                                            uriString]
                           }];
            }
            return nil;
        }
    }

    return metadata;
}
```

**Source:** `ATProtoPDS/Sources/Auth/OAuth2Handler.m` lines 200-350

## DPoP Utilities

### Generating DPoP Proofs

The `DPoPUtil` class handles DPoP proof generation and verification:

```objc
// In DPoPUtil.m (ATProtoPDS/Sources/Auth/DPoPUtil.m)
+ (nullable DPoPToken *)createDPoPForMethod:(NSString *)htm
                                         uri:(NSString *)htu
                                       nonce:(nullable NSString *)nonce
                                         key:(SecKeyRef)privateKey
                                       error:(NSError **)error {
    // 1. Validate URI
    NSURL *url = [NSURL URLWithString:htu];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.dpop"
                                         code:-17
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP URI"}];
        }
        return nil;
    }

    // 2. Extract public key from private key for JWK
    NSDictionary *jwk = [AuthCryptoJWK publicJWKFromKey:privateKey error:error];
    if (!jwk) return nil;
    
    // 3. Create DPoP token with claims
    NSString *canonicalHTU = [AuthCryptoDPoP canonicalHTUFromURL:url];
    DPoPToken *token = [[DPoPToken alloc] init];
    token.htm = htm;
    token.htu = canonicalHTU;
    token.iat = [NSDate date];
    token.jti = [[NSUUID UUID] UUIDString];
    token.nonce = nonce;
    token.exp = [NSDate dateWithTimeIntervalSinceNow:300];  // 5 minute expiration

    // 4. Build JWT header with JWK
    NSDictionary *header = @{
        @"typ": @"dpop+jwt",
        @"alg": @"ES256",
        @"jwk": jwk
    };
    
    // 5. Encode header and payload
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:[token payload] options:0 error:error];
    if (!headerData || !payloadData) return nil;

    NSString *headerB64 = [AuthCryptoBase64URL encode:headerData];
    NSString *payloadB64 = [AuthCryptoBase64URL encode:payloadData];
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    // 6. Sign with private key
    CFErrorRef signError = NULL;
    NSData *derSignature = CFBridgingRelease(SecKeyCreateSignature(privateKey,
                                                                 kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                                 (__bridge CFDataRef)signingData,
                                                                 &signError));
    if (!derSignature) {
        if (error) *error = CFBridgingRelease(signError);
        return nil;
    }

    // 7. Convert DER signature to raw format
    NSData *rawSignature = [AuthCryptoECDSA rawSignatureFromDER:derSignature expectedSize:32 error:error];
    if (!rawSignature) return nil;

    // 8. Combine into complete JWT
    token.jwt = [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, [AuthCryptoBase64URL encode:rawSignature]];
    return token;
}
```

**Source:** `ATProtoPDS/Sources/Auth/DPoPUtil.m` lines 50-110

### Verifying DPoP Proofs

DPoP proofs are verified to ensure they match the request method and URI:

```objc
// In DPoPUtil.m (ATProtoPDS/Sources/Auth/DPoPUtil.m)
+ (BOOL)verifyDPoP:(NSString *)dpopJwt
     withPublicKey:(nullable SecKeyRef)publicKey
              method:(NSString *)htm
                 uri:(NSString *)htu
              nonce:(nullable NSString *)nonce
               error:(NSError **)error {
    // 1. Validate URI
    NSURL *url = [NSURL URLWithString:htu];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.dpop"
                                         code:-17
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP URI"}];
        }
        return NO;
    }

    // 2. Verify DPoP proof structure and signature
    NSString *thumbprint = nil;
    BOOL valid = [AuthCryptoDPoP verifyProof:dpopJwt
                                      method:htm
                                         url:url
                                       nonce:nonce
                                requireNonce:NO
                              nonceValidator:nil
                               replayChecker:nil
                               outThumbprint:&thumbprint
                                       error:error];
    if (!valid) return NO;

    // 3. If public key provided, verify it matches the one in DPoP header
    if (publicKey) {
        NSString *expectedThumbprint = [AuthCryptoJWK thumbprintForKey:publicKey error:error];
        if (!expectedThumbprint || ![thumbprint isEqualToString:expectedThumbprint]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.pds.dpop"
                                             code:-14
                                         userInfo:@{NSLocalizedDescriptionKey: @"Public key mismatch"}];
            }
            return NO;
        }
    }

    return YES;
}
```

**Source:** `ATProtoPDS/Sources/Auth/DPoPUtil.m` lines 112-160

## Nonce Management

DPoP nonces prevent replay attacks:

```objc
@interface PDSNonceManager : NSObject

+ (NSString *)generateNonce;

+ (BOOL)validateNonce:(NSString *)nonce error:(NSError **)error;

+ (void)invalidateNonce:(NSString *)nonce;

@end
```

### Nonce Challenge

If DPoP verification fails due to missing nonce:

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: DPoP error="use_dpop_nonce"
DPoP-Nonce: server-generated-nonce
```

Client must retry with nonce in DPoP proof.

## Token Structure

### Access Token Claims

```json
{
  "sub": "did:plc:user123",
  "aud": "did:web:pds.example.com",
  "exp": 1631555200,
  "iat": 1631551600,
  "cnf": {
    "jkt": "thumbprint-of-client-key"
  }
}
```

### Refresh Token Claims

```json
{
  "sub": "did:plc:user123",
  "aud": "did:web:pds.example.com",
  "exp": 1640000000,
  "iat": 1631551600,
  "type": "refresh"
}
```

## Best Practices

1. **Token Security**
   - Use short-lived access tokens (15-60 minutes)
   - Use longer-lived refresh tokens (days/weeks)
   - Rotate refresh tokens on use
   - Revoke tokens on logout

2. **DPoP Handling**
   - Verify DPoP proof on every request
   - Validate method and URL
   - Check timestamp freshness
   - Implement nonce challenge

3. **Client Registration**
   - Validate redirect URIs
   - Store client secrets securely
   - Implement client authentication
   - Track client usage

4. **Error Handling**
   - Return appropriate error codes
   - Include error descriptions
   - Set DPoP-Nonce header on 401
   - Log authentication failures

## Common Patterns

### OAuth 2.0 Authorization Code Flow

```objc
// 1. User clicks "Login with PDS"
// 2. Redirect to authorization endpoint
NSString *authUrl = [NSString stringWithFormat:
    @"https://pds.example.com/oauth/authorize?client_id=%@&redirect_uri=%@&scope=%@&state=%@",
    clientId, redirectUri, scope, state];

// 3. User logs in and grants permission
// 4. Redirect back with authorization code
// 5. Exchange code for tokens
NSString *tokenUrl = @"https://pds.example.com/oauth/token";
NSDictionary *tokenRequest = @{
    @"grant_type": @"authorization_code",
    @"code": authorizationCode,
    @"client_id": clientId,
    @"client_secret": clientSecret
};

// 6. Store tokens securely
[self storeAccessToken:accessToken];
[self storeRefreshToken:refreshToken];
```

### Using DPoP with API Requests

```objc
// 1. Generate DPoP proof
NSString *dpopProof = [DPoPUtil generateDPoPProof:@"POST"
                                             uri:apiUrl
                                        clientKey:clientKey
                                           nonce:nil
                                           error:&error];

// 2. Make API request
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:apiUrl]];
[request setHTTPMethod:@"POST"];
[request setValue:[NSString stringWithFormat:@"DPoP %@", accessToken]
   forHTTPHeaderField:@"Authorization"];
[request setValue:dpopProof forHTTPHeaderField:@"DPoP"];

// 3. Handle response
NSURLResponse *response = nil;
NSError *error = nil;
NSData *data = [NSURLConnection sendSynchronousRequest:request
                                     returningResponse:&response
                                                 error:&error];
```

## See Also

- [JWT Tokens](./jwt-tokens.md)
- [Key Rotation](./key-rotation.md)
- [TOTP and WebAuthn](./totp-webauthn.md)
- [Auth Helpers](../04-network-layer/auth-helpers.md)
