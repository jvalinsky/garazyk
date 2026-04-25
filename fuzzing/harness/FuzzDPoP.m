// FuzzDPoP.m - DPoP proof verification fuzzer harness
// Target: DPoP token verification and JWT parsing

#import <Foundation/Foundation.h>
#import "Auth/DPoPUtil.h"
#import "Auth/JWT.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        NSString *proof = [[NSString alloc] initWithBytes:data
                                                   length:size
                                                 encoding:NSUTF8StringEncoding];
        if (!proof) {
            proof = [[NSString alloc] initWithBytes:data
                                             length:size
                                           encoding:NSASCIIStringEncoding];
        }
        if (!proof) {
            return 0;
        }

#if defined(__APPLE__) && !defined(GNUSTEP)
        NSError *error = nil;
        // Exercise the verification path (no public key means structural parse only on macOS)
        [DPoPUtil verifyDPoP:proof
               withPublicKey:NULL
                      method:@"POST"
                         uri:@"https://example.com/xrpc/com.atproto.server.createSession"
                       nonce:nil
                       error:&error];

        // Also try with different nonce and method
        [DPoPUtil verifyDPoP:proof
               withPublicKey:NULL
                      method:@"GET"
                         uri:@"https://example.com/xrpc/com.atproto.server.getSession"
                       nonce:@"test-nonce"
                       error:&error];
#endif

        // DPoP proof is a JWT — parse it to exercise JWT header/payload extraction
        NSError *jwtError = nil;
        JWT *jwt = [JWT jwtWithToken:proof error:&jwtError];
        if (jwt) {
            (void)jwt.header;
            (void)jwt.payload;
            (void)jwt.rawHeader;
            (void)jwt.rawPayload;
        }
    }
    return 0;
}
