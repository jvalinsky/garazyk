#import <Foundation/Foundation.h>
#import "TutorialJWTMinter.h"
#import "TutorialJWTVerifier.h"
#import "TutorialECDSAUtils.h"
#import "TutorialDPoPHandler.h"
#import "TutorialOAuth2Handler.h"
#import "TutorialBase64URL.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <CommonCrypto/CommonDigest.h>
#else
#import <openssl/sha.h>
#endif

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"Tutorial 4: Authentication (ES256)");
        NSLog(@"====================================\n");

        NSError *error = nil;

        // ============================================================
        // 1. ES256 Key Generation and JWT Signing
        // ============================================================
        NSLog(@"1. ES256 Key Generation & JWT Signing");
        NSLog(@"------------------------------------");

        TutorialECDSAKeyPair *keyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
        if (!keyPair) {
            NSLog(@"Failed to generate key pair: %@", error);
            return 1;
        }
        NSLog(@"Generated EC P-256 key pair");
        NSLog(@"  Key ID: %@", keyPair.keyID);
        NSLog(@"  JWK Thumbprint: %@...", [keyPair.thumbprint substringToIndex:MIN(20, keyPair.thumbprint.length)]);

        TutorialJWTMinter *minter = [[TutorialJWTMinter alloc] initWithIssuer:@"did:web:localhost:2583"];
        NSLog(@"  JWT Minter initialized with ES256 signing\n");

        // ============================================================
        // 2. JWT Verification
        // ============================================================
        NSLog(@"2. JWT Verification");
        NSLog(@"--------------------");

        NSString *accessToken = [minter mintAccessTokenForDID:@"did:web:localhost:~alice"
                                                        handle:@"alice"
                                                        scopes:@[@"atproto_repo"]
                                                         error:&error];
        if (!accessToken) {
            NSLog(@"Failed to mint access token: %@", error);
            return 1;
        }
        NSLog(@"Minted access token: %@...", [accessToken substringToIndex:MIN(50, accessToken.length)]);

        TutorialJWTVerifier *verifier = [[TutorialJWTVerifier alloc] initWithIssuer:@"did:web:localhost:2583"
                                                                             keyPair:minter.keyPair];
        NSDictionary *verified = [verifier verifyToken:accessToken error:&error];
        if (verified) {
            NSLog(@"Token verified successfully");
            NSLog(@"  Subject: %@", verified[@"sub"]);
            NSLog(@"  Scope: %@\n", verified[@"scope"]);
        } else {
            NSLog(@"Token verification failed: %@\n", error.localizedDescription);
        }

        // Verify that tampered tokens are rejected
        NSString *tamperedToken = [accessToken stringByReplacingOccurrencesOfString:@"alice"
                                                                        withString:@"bob"
                                                                           options:NSLiteralSearch
                                                                             range:NSMakeRange(0, accessToken.length)];
        NSDictionary *tamperedResult = [verifier verifyToken:tamperedToken error:&error];
        if (!tamperedResult) {
            NSLog(@"Tampered token correctly rejected\n");
        }

        // ============================================================
        // 3. OAuth 2.0 Authorization Flow with PKCE
        // ============================================================
        NSLog(@"3. OAuth 2.0 Authorization Flow (PKCE)");
        NSLog(@"---------------------------------------");

        TutorialOAuth2Handler *oauth = [[TutorialOAuth2Handler alloc] initWithMinter:minter];

        // Generate PKCE code verifier and challenge
        NSString *codeVerifier = @"dBjftJeZ4CVP-mB92K29uhjUix2fO8N7s5-3mO0a0E4"; // Example PKCE verifier
        NSData *verifierData = [codeVerifier dataUsingEncoding:NSUTF8StringEncoding];
        unsigned char verifierDigest[32];
#if defined(__APPLE__) && !defined(GNUSTEP)
        CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, verifierDigest);
#else
        SHA256(verifierData.bytes, verifierData.length, verifierDigest);
#endif
        NSString *codeChallenge = [TutorialBase64URL encode:[NSData dataWithBytes:verifierDigest length:32]];
        NSLog(@"Generated PKCE code challenge (S256)");

        // Step 1: Authorization request
        NSDictionary *authParams = @{
            @"client_id": @"https://example.com",
            @"redirect_uri": @"https://example.com/callback",
            @"scope": @"atproto_repo",
            @"state": @"random123",
            @"code_challenge": codeChallenge,
            @"code_challenge_method": @"S256"
        };

        __block NSString *authCode = nil;
        [oauth handleAuthorize:authParams completion:^(NSString *redirectURL, NSError *error) {
            if (redirectURL) {
                NSLog(@"Authorization granted");
                NSLog(@"  Redirect: %@", redirectURL);

                NSURLComponents *components = [NSURLComponents componentsWithString:redirectURL];
                for (NSURLQueryItem *item in components.queryItems) {
                    if ([item.name isEqualToString:@"code"]) {
                        authCode = item.value;
                    }
                }
            } else {
                NSLog(@"Authorization failed: %@", error.localizedDescription);
            }
        }];

        // Step 2: Token exchange with PKCE verifier
        if (authCode) {
            NSDictionary *tokenParams = @{
                @"grant_type": @"authorization_code",
                @"code": authCode,
                @"client_id": @"https://example.com",
                @"redirect_uri": @"https://example.com/callback",
                @"code_verifier": codeVerifier
            };

            [oauth handleToken:tokenParams completion:^(NSDictionary *result, NSError *error) {
                if (result) {
                    NSLog(@"Tokens issued (ES256-signed)");
                    NSLog(@"  Access token: %@...", [result[@"access_token"] substringToIndex:MIN(50, [result[@"access_token"] length])]);
                    NSLog(@"  Token type: %@", result[@"token_type"]);
                    NSLog(@"  Expires in: %@ seconds", result[@"expires_in"]);
                } else {
                    NSLog(@"Token exchange failed: %@", error.localizedDescription);
                }
            }];
        }

        // Step 3: Refresh token
        NSDictionary *refreshParams = @{
            @"grant_type": @"refresh_token",
            @"refresh_token": @"dummy-refresh-token"
        };

        [oauth handleToken:refreshParams completion:^(NSDictionary *result, NSError *error) {
            if (result) {
                NSLog(@"Refresh token exchanged");
                NSLog(@"  New access token: %@...\n", [result[@"access_token"] substringToIndex:MIN(50, [result[@"access_token"] length])]);
            } else {
                NSLog(@"Refresh failed: %@\n", error.localizedDescription);
            }
        }];

        // ============================================================
        // 4. DPoP Proof-of-Possession
        // ============================================================
        NSLog(@"4. DPoP Proof-of-Possession");
        NSLog(@"---------------------------");

        // Generate a separate DPoP key pair (client-side key)
        TutorialECDSAKeyPair *dpopKeyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
        if (!dpopKeyPair) {
            NSLog(@"Failed to generate DPoP key pair: %@", error);
            return 1;
        }

        NSString *dpopProof = [TutorialDPoPHandler generateDPoPProof:@"POST"
                                                                  uri:@"https://pds.example.com/xrpc/com.atproto.repo.createRecord"
                                                                nonce:@"server-nonce-123"
                                                              keyPair:dpopKeyPair
                                                                error:&error];
        if (dpopProof) {
            NSLog(@"DPoP proof generated (ES256-signed)");
            NSLog(@"  Proof: %@...", [dpopProof substringToIndex:MIN(50, dpopProof.length)]);

            // Verify DPoP proof
            BOOL valid = [TutorialDPoPHandler verifyDPoPProof:dpopProof
                                                        method:@"POST"
                                                           uri:@"https://pds.example.com/xrpc/com.atproto.repo.createRecord"
                                                    publicJWK:dpopKeyPair.publicJWK
                                                         nonce:@"server-nonce-123"
                                             allowedClockSkew:30
                                                         error:&error];

            if (valid) {
                NSLog(@"DPoP proof verified");
            } else {
                NSLog(@"DPoP verification failed: %@", error.localizedDescription);
            }

            // Show JWK thumbprint for key binding
            NSLog(@"  JWK Thumbprint: %@", dpopKeyPair.thumbprint);

            // Verify that wrong method is rejected
            BOOL wrongMethod = [TutorialDPoPHandler verifyDPoPProof:dpopProof
                                                              method:@"GET"
                                                                 uri:@"https://pds.example.com/xrpc/com.atproto.repo.createRecord"
                                                          publicJWK:dpopKeyPair.publicJWK
                                                               nonce:@"server-nonce-123"
                                                   allowedClockSkew:30
                                                               error:nil];
            if (!wrongMethod) {
                NSLog(@"Wrong HTTP method correctly rejected\n");
            }
        } else {
            NSLog(@"DPoP proof generation failed: %@\n", error.localizedDescription);
        }

        NSLog(@"====================================");
        NSLog(@"Tutorial completed!");
        NSLog(@"Key concepts demonstrated:");
        NSLog(@"  - EC P-256 key generation (Security.framework / OpenSSL)");
        NSLog(@"  - ES256 JWT signing and verification");
        NSLog(@"  - OAuth 2.0 authorization code flow with PKCE (S256)");
        NSLog(@"  - DPoP proof-of-possession with real ECDSA signatures");
        NSLog(@"  - JWK thumbprint for key binding");
    }

    return 0;
}
