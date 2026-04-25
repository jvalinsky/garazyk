// FuzzJWT.m - JWT parsing fuzzer harness
// Target: JWT token parsing and verification

#import <Foundation/Foundation.h>
#import "Auth/JWT.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        NSString *token = [[NSString alloc] initWithBytes:data
                                                   length:size
                                                 encoding:NSUTF8StringEncoding];
        if (!token) {
            token = [[NSString alloc] initWithBytes:data
                                             length:size
                                           encoding:NSASCIIStringEncoding];
        }
        if (!token) {
            return 0;
        }

        NSError *error = nil;

        // Test JWT parsing
        JWT *jwt = [JWT jwtWithToken:token error:&error];
        if (jwt) {
            // Touch all header and payload accessors
            (void)jwt.header;
            (void)jwt.payload;
            (void)jwt.rawHeader;
            (void)jwt.rawPayload;
            (void)jwt.signature;
            (void)jwt.encodedSignature;
            (void)[jwt encodedToken];
            (void)[jwt signingInput];

            // Touch payload claims if present
            if (jwt.payload) {
                (void)jwt.payload.iss;
                (void)jwt.payload.sub;
                (void)jwt.payload.aud;
                (void)jwt.payload.exp;
                (void)jwt.payload.iat;
                (void)jwt.payload.nbf;
                (void)jwt.payload.jti;
                (void)jwt.payload.did;
                (void)jwt.payload.handle;
            }

            // Test JWTVerifier with claims validation
            JWTVerifier *verifier = [[JWTVerifier alloc] init];
            verifier.expectedIssuer = @"";
            verifier.expectedAudience = @"";
            verifier.allowedAlgorithms = @[@"ES256", @"RS256", @"none"];
            NSError *verifyErr = nil;
            [verifier verifyJWT:jwt error:&verifyErr];
        }

        // Test base64URLDecode directly on the token string
        NSError *decodeErr = nil;
        NSData *decoded = [JWT base64URLDecode:token error:&decodeErr];
        (void)decoded;

        // Test base64URLDecode on payload-like strings
        if (size > 0) {
            NSString *base64Str = [[NSString alloc] initWithBytes:data
                                                            length:size
                                                          encoding:NSASCIIStringEncoding];
            if (base64Str) {
                NSData *decoded2 = [JWT base64URLDecode:base64Str error:nil];
                (void)decoded2;
            }
        }
    }
    return 0;
}
