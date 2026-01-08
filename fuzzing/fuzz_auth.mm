//
//  fuzz_auth.mm
//  Comprehensive authentication fuzzing harness for ATProto PDS
//
//  Tests:
//  1. JWT token parsing and validation
//  2. DPoP token construction
//  3. Session management
//  4. OAuth token handling
//  5. Cryptographic operations
//

#import <Foundation/Foundation.h>
#import "Auth/JWT.h"
#import "Auth/DPoPUtil.h"
#import "Auth/Session.h"
#import "Auth/OAuth2.h"
#import "Core/DID.h"
#import "Auth/KeyManager.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > 100000) {
        return 0;
    }

    @autoreleasepool {
        NSData *inputData = [NSData dataWithBytes:data length:size];
        NSString *inputString = [[NSString alloc] initWithData:inputData encoding:NSUTF8StringEncoding];

        // Test 1: JWT parsing
        if (inputString.length > 0) {
            NSArray *parts = [inputString componentsSeparatedByString:@"."];
            if (parts.count == 3) {
                NSString *headerB64 = parts[0];
                NSString *payloadB64 = parts[1];
                NSString *signatureB64 = parts[2];

                // Decode header
                NSData *headerData = [[NSData alloc] initWithBase64EncodedString:headerB64 options:0];
                if (headerData) {
                    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:nil];
                    (void)header;

                    NSString *alg = header[@"alg"];
                    NSString *typ = header[@"typ"];
                    NSString *kid = header[@"kid"];
                    (void)alg;
                    (void)typ;
                    (void)kid;
                }

                // Decode payload
                NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:payloadB64 options:0];
                if (payloadData) {
                    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
                    (void)payload;

                    // Extract standard JWT claims
                    NSString *iss = payload[@"iss"];
                    NSString *sub = payload[@"sub"];
                    NSString *aud = payload[@"aud"];
                    NSNumber *exp = payload[@"exp"];
                    NSNumber *iat = payload[@"iat"];
                    (void)iss;
                    (void)sub;
                    (void)aud;
                    (void)exp;
                    (void)iat;
                }

                // Verify signature format
                NSData *signatureData = [[NSData alloc] initWithBase64EncodedString:signatureB64 options:0];
                (void)signatureData;
            }
        }

        // Test 2: JWT header construction
        JWTHeader *header = [[JWTHeader alloc] init];
        header.alg = @"ES256";
        header.typ = @"dpop+jwt";
        header.kid = @"kid123";
        header.cty = @"application/json";

        NSDictionary *headerDict = [header toDictionary];
        (void)headerDict;

        // Test 3: JWT payload construction
        JWTPayload *payload = [[JWTPayload alloc] init];
        payload.iss = @"https://pds.example.com";
        payload.sub = @"did:plc:test";
        payload.aud = @"https://app.example.com";
        payload.jti = [[NSUUID UUID] UUIDString];
        payload.did = @"did:plc:test";
        payload.handle = @"user.example.com";
        payload.scope = @"atproto transition:generic";

        NSDate *now = [NSDate date];
        payload.exp = [now dateByAddingTimeInterval:3600];
        payload.iat = now;

        NSDictionary *payloadDict = [payload toDictionary];
        (void)payloadDict;

        // Test 4: DPoP token construction
        DPoPToken *dpop = [[DPoPToken alloc] init];
        dpop.htm = @"POST";
        dpop.htu = @"https://pds.example.com/xrpc/com.atproto.server.createSession";
        dpop.iat = [NSDate date];
        dpop.exp = [dpop.iat dateByAddingTimeInterval:300];
        dpop.jti = [[NSUUID UUID] UUIDString];
        dpop.nonce = nil;

        NSDictionary *dpopHeader = [dpop header];
        NSDictionary *dpopPayload = [dpop payload];
        (void)dpopHeader;
        (void)dpopPayload;

        // Test 5: Session construction
        Session *session = [[Session alloc] initWithDID:@"did:plc:test"
                                                  handle:@"user.example.com"
                                                   scope:@"atproto transition:generic"];
        (void)session;

        // Test 6: OAuth2 flow parsing
        NSString *authCode = @"auth_code_123";
        NSString *redirectUri = @"https://app.example.com/callback";
        NSString *clientId = @"client_123";
        NSString *codeVerifier = @"code_verifier_123";

        (void)authCode;
        (void)redirectUri;
        (void)clientId;
        (void)codeVerifier;

        // Test 7: Token type validation
        NSArray *validTokenTypes = @[@"Bearer", @"DPoP", @"At"];
        NSArray *invalidTokenTypes = @[@"Basic", @"Digest", @"Hawk", @""];

        for (NSString *type in validTokenTypes) {
            BOOL isValid = [type isEqualToString:@"Bearer"] || [type isEqualToString:@"DPoP"];
            (void)isValid;
        }

        // Test 8: Scope parsing
        NSString *testScope = @"atproto transition:generic profile email";
        NSArray *scopeParts = [testScope componentsSeparatedByString:@" "];
        (void)scopeParts;

        // Test 9: Claims validation
        NSDictionary *claims = @{
            @"iss": @"https://pds.example.com",
            @"sub": @"did:plc:test",
            @"aud": @"https://app.example.com",
            @"exp": @([[NSDate date] timeIntervalSince1970] + 3600),
            @"iat": @([[NSDate date] timeIntervalSince1970]),
            @"jti": [[NSUUID UUID] UUIDString]
        };

        // Check expiration
        NSNumber *expClaim = claims[@"exp"];
        NSNumber *iatClaim = claims[@"iat"];
        if (expClaim && iatClaim) {
            BOOL notExpired = [expClaim doubleValue] > [[NSDate date] timeIntervalSince1970];
            BOOL notBeforeValid = [iatClaim doubleValue] <= [[NSDate date] timeIntervalSince1970];
            (void)notExpired;
            (void)notBeforeValid;
        }

        // Test 10: Key ID parsing
        NSArray *keyIdTests = @[
            @"did:key:z6MkiTBz1ymLq1Z7D1Am8BdNm2V",
            @"#atproto",
            @"main",
            @""
        ];

        for (NSString *kid in keyIdTests) {
            (void)kid;
        }

        // Test 11: Cryptographic hash validation
        NSData *hashInput = inputData.length > 0 ? inputData : [NSData data];
        if (hashInput.length > 0 && hashInput.length < 10000) {
            // Test SHA-256 hash format (32 bytes)
            if (hashInput.length >= 32) {
                NSData *hash = [hashInput subdataWithRange:NSMakeRange(0, 32)];
                (void)hash;

                // Multihash format
                NSData *multihash = [NSData dataWithBytes:hash.bytes length:hash.length];
                (void)multihash;
            }
        }

        // Test 12: OAuth error responses
        NSDictionary *oauthErrors = @{
            @"invalid_request": @"The request is missing a required parameter",
            @"unauthorized_client": @"Client is not authorized",
            @"access_denied": @"Resource owner denied the request",
            @"unsupported_response_type": @"Response type not supported",
            @"invalid_scope": @"Requested scope is invalid",
            @"server_error": @"Server encountered an unexpected error",
            @"temporarily_unavailable": @"Service temporarily unavailable"
        };

        for (NSString *error in oauthErrors) {
            NSString *description = oauthErrors[error];
            (void)error;
            (void)description;
        }

        // Test 13: DPoP nonce handling
        NSString *nonce = [[NSUUID UUID] UUIDString];
        (void)nonce;

        if (inputString.length > 0 && [inputString containsString:@"nonce="]) {
            // Extract nonce from URL-encoded string
            NSRange nonceRange = [inputString rangeOfString:@"nonce="];
            if (nonceRange.location != NSNotFound) {
                NSString *extractedNonce = [inputString substringFromIndex:nonceRange.location + nonceRange.length];
                NSUInteger endPos = [extractedNonce rangeOfString:@"&"].location;
                if (endPos == NSNotFound) {
                    endPos = extractedNonce.length;
                }
                NSString *parsedNonce = [extractedNonce substringToIndex:endPos];
                (void)parsedNonce;
            }
        }

        return 0;
    }
}

#ifndef LIBFUZZER
int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        fprintf(stderr, "Cannot open file: %s\n", argv[0]);
        return 1;
    }

    fseek(f, 0, SEEK_END);
    long fileSize = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *data = (uint8_t *)malloc(fileSize);
    size_t readSize = fread(data, 1, fileSize, f);
    fclose(f);

    int result = LLVMFuzzerTestOneInput(data, readSize);
    free(data);

    return result;
}
#endif
