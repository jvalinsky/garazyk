#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonHMAC.h>
#import "JWTVerifier.h"
#import "DPoPHandler.h"
#import "OAuth2Handler.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"Tutorial 4: Authentication Example");
        NSLog(@"====================================");
        
        // 1. JWT Verification Example
        NSLog(@"\n1. JWT Verification");
        NSLog(@"-------------------");
        
        NSString *issuer = @"did:web:localhost:2583";
        NSString *secret = @"tutorial-secret-key";
        NSData *secretData = [secret dataUsingEncoding:NSUTF8StringEncoding];
        
        JWTVerifier *verifier = [[JWTVerifier alloc] initWithIssuer:issuer publicKey:secretData];
        
        // Create a sample token
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSDictionary *payload = @{
            @"iss": issuer,
            @"sub": @"did:plc:user123",
            @"iat": @(now),
            @"exp": @(now + 3600),
            @"scope": @"atproto_repo"
        };
        
        NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
        NSString *payloadB64 = [payloadData base64EncodedStringWithOptions:0];
        payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
        payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
        
        NSDictionary *header = @{@"alg": @"HS256", @"typ": @"JWT"};
        NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
        NSString *headerB64 = [headerData base64EncodedStringWithOptions:0];
        headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
        headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
        
        NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
        NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
        
        unsigned char digest[32];
        CCHmac(kCCHmacAlgSHA256, secretData.bytes, secretData.length, 
               signingData.bytes, signingData.length, digest);
        NSData *signature = [NSData dataWithBytes:digest length:32];
        NSString *signatureB64 = [signature base64EncodedStringWithOptions:0];
        signatureB64 = [signatureB64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
        signatureB64 = [signatureB64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        signatureB64 = [signatureB64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
        
        NSString *token = [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
        
        NSLog(@"Generated token: %@...", [token substringToIndex:MIN(50, token.length)]);
        
        NSError *error = nil;
        NSDictionary *verified = [verifier verifyToken:token error:&error];
        
        if (verified) {
            NSLog(@"✓ Token verified successfully");
            NSLog(@"  Subject: %@", verified[@"sub"]);
            NSLog(@"  Scope: %@", verified[@"scope"]);
        } else {
            NSLog(@"✗ Token verification failed: %@", error.localizedDescription);
        }
        
        // 2. OAuth 2.0 Flow Example
        NSLog(@"\n2. OAuth 2.0 Authorization Flow");
        NSLog(@"--------------------------------");
        
        OAuth2Handler *oauth = [[OAuth2Handler alloc] init];
        
        // Step 1: Authorization request
        NSDictionary *authParams = @{
            @"client_id": @"https://example.com",
            @"redirect_uri": @"https://example.com/callback",
            @"scope": @"atproto_repo",
            @"state": @"random123"
        };
        
        __block NSString *authCode = nil;
        
        [oauth handleAuthorize:authParams completion:^(NSString *redirectURL, NSError *error) {
            if (redirectURL) {
                NSLog(@"✓ Authorization granted");
                NSLog(@"  Redirect: %@", redirectURL);
                
                // Extract code from redirect URL
                NSURLComponents *components = [NSURLComponents componentsWithString:redirectURL];
                for (NSURLQueryItem *item in components.queryItems) {
                    if ([item.name isEqualToString:@"code"]) {
                        authCode = item.value;
                    }
                }
            } else {
                NSLog(@"✗ Authorization failed: %@", error.localizedDescription);
            }
        }];
        
        // Step 2: Token exchange
        if (authCode) {
            NSDictionary *tokenParams = @{
                @"grant_type": @"authorization_code",
                @"code": authCode,
                @"client_id": @"https://example.com",
                @"redirect_uri": @"https://example.com/callback"
            };
            
            [oauth handleToken:tokenParams completion:^(NSDictionary *result, NSError *error) {
                if (result) {
                    NSLog(@"✓ Tokens issued");
                    NSLog(@"  Access token: %@...", [result[@"access_token"] substringToIndex:MIN(50, [result[@"access_token"] length])]);
                    NSLog(@"  Token type: %@", result[@"token_type"]);
                    NSLog(@"  Expires in: %@ seconds", result[@"expires_in"]);
                } else {
                    NSLog(@"✗ Token exchange failed: %@", error.localizedDescription);
                }
            }];
        }
        
        // 3. DPoP Example
        NSLog(@"\n3. DPoP Proof-of-Possession");
        NSLog(@"----------------------------");
        
        // Generate a mock ECDSA P-256 key pair (65 bytes: 0x04 || x || y)
        NSMutableData *publicKey = [NSMutableData dataWithCapacity:65];
        uint8_t prefix = 0x04;
        [publicKey appendBytes:&prefix length:1];
        
        // Mock x coordinate (32 bytes)
        uint8_t xBytes[32];
        for (int i = 0; i < 32; i++) xBytes[i] = i;
        [publicKey appendBytes:xBytes length:32];
        
        // Mock y coordinate (32 bytes)
        uint8_t yBytes[32];
        for (int i = 0; i < 32; i++) yBytes[i] = i + 32;
        [publicKey appendBytes:yBytes length:32];
        
        NSData *privateKey = [NSData dataWithBytes:xBytes length:32];
        
        NSString *dpopProof = [DPoPHandler generateDPoPProof:@"POST"
                                                         uri:@"https://pds.example.com/xrpc/com.atproto.repo.createRecord"
                                                       nonce:nil
                                                  privateKey:privateKey
                                                   publicKey:publicKey
                                                       error:&error];
        
        if (dpopProof) {
            NSLog(@"✓ DPoP proof generated");
            NSLog(@"  Proof: %@...", [dpopProof substringToIndex:MIN(50, dpopProof.length)]);
            
            // Verify DPoP proof
            BOOL valid = [DPoPHandler verifyDPoPProof:dpopProof
                                               method:@"POST"
                                                  uri:@"https://pds.example.com/xrpc/com.atproto.repo.createRecord"
                                            publicKey:publicKey
                                                error:&error];
            
            if (valid) {
                NSLog(@"✓ DPoP proof verified");
            } else {
                NSLog(@"✗ DPoP verification failed: %@", error.localizedDescription);
            }
            
            // Extract thumbprint
            NSString *thumbprint = [DPoPHandler extractThumbprint:publicKey error:&error];
            if (thumbprint) {
                NSLog(@"✓ Key thumbprint: %@...", [thumbprint substringToIndex:MIN(20, thumbprint.length)]);
            }
        } else {
            NSLog(@"✗ DPoP proof generation failed: %@", error.localizedDescription);
        }
        
        NSLog(@"\n====================================");
        NSLog(@"Tutorial completed successfully!");
        NSLog(@"See docs/10-tutorials/tutorial-4-auth.md for full implementation");
    }
    
    return 0;
}
