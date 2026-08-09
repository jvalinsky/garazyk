// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/Crypto/JWT.h"
#import "Video/VideoJWTAuthProvider.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface S16GateTests : XCTestCase
@end

@implementation S16GateTests

#pragma mark - V1/V2: Non-string ATProtoJWT claims must return 401

- (void)testNonStringSubClaimReturns401 {
    // Access token with non-string sub (number instead of DID string).
    // The isKindOfClass guard should return nil, causing "Token missing issuer".
    NSString *header = @"{\"alg\":\"ES256K\",\"typ\":\"at+jwt\"}";
    NSString *payload = @"{\"sub\":12345,\"iss\":\"did:plc:test\",\"exp\":9999999999}";
    NSString *token = [NSString stringWithFormat:@"Bearer %@.%@.fakesig",
                       [self base64UrlEncode:header],
                       [self base64UrlEncode:payload]];

    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc]
        initWithExpectedAudience:@"did:plc:testaud"
                     signingKeyJWK:nil];

    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                               methodString:@"GET"
                                                       path:@"/"
                                                queryString:@""
                                                queryParams:@{}
                                                    version:@"HTTP/1.1"
                                                    headers:@{@"Authorization": token}
                                                       body:nil
                                              remoteAddress:nil];
    ATProtoHttpResponse *res = [[ATProtoHttpResponse alloc] init];

    NSString *did = [provider authenticateRequest:req response:res];

    XCTAssertNil(did, @"Token with non-string sub claim should be rejected");
    XCTAssertEqual(res.statusCode, 401, @"Should return 401 for malformed sub claim");
}

- (void)testNonStringDidFallbackClaimReturns401 {
    // Access token where sub is present but invalid, and did claim is also non-string.
    NSString *header = @"{\"alg\":\"ES256K\",\"typ\":\"at+jwt\"}";
    NSString *payload = @"{\"sub\":\"not-a-did\",\"did\":99999,\"exp\":9999999999}";
    NSString *token = [NSString stringWithFormat:@"Bearer %@.%@.fakesig",
                       [self base64UrlEncode:header],
                       [self base64UrlEncode:payload]];

    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc]
        initWithExpectedAudience:@"did:plc:testaud"
                     signingKeyJWK:nil];

    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                               methodString:@"GET"
                                                       path:@"/"
                                                queryString:@""
                                                queryParams:@{}
                                                    version:@"HTTP/1.1"
                                                    headers:@{@"Authorization": token}
                                                       body:nil
                                              remoteAddress:nil];
    ATProtoHttpResponse *res = [[ATProtoHttpResponse alloc] init];

    NSString *did = [provider authenticateRequest:req response:res];

    // sub "not-a-did" fails hasPrefix:@"did:" → falls back to did claim (99999, non-string) → nil
    XCTAssertNil(did, @"Token with non-string did fallback claim should be rejected");
    XCTAssertEqual(res.statusCode, 401, @"Should return 401 for malformed did claim");
}

- (void)testNonStringIssClaimReturns401 {
    // Service auth token (typ: ATProtoJWT) with non-string iss claim.
    NSString *header = @"{\"alg\":\"ES256K\",\"typ\":\"JWT\"}";
    NSString *payload = @"{\"iss\":[1,2,3],\"sub\":\"did:plc:test\",\"aud\":\"did:plc:aud\",\"exp\":9999999999,\"lxm\":\"com.atproto.test\"}";
    NSString *token = [NSString stringWithFormat:@"Bearer %@.%@.fakesig",
                       [self base64UrlEncode:header],
                       [self base64UrlEncode:payload]];

    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc]
        initWithExpectedAudience:@"did:plc:testaud"
                     signingKeyJWK:nil];

    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                               methodString:@"GET"
                                                       path:@"/"
                                                queryString:@""
                                                queryParams:@{}
                                                    version:@"HTTP/1.1"
                                                    headers:@{@"Authorization": token}
                                                       body:nil
                                              remoteAddress:nil];
    ATProtoHttpResponse *res = [[ATProtoHttpResponse alloc] init];

    NSString *did = [provider authenticateRequest:req response:res];

    // Non-string iss → nil → "Token missing issuer"
    XCTAssertNil(did, @"Token with non-string iss claim should be rejected");
    XCTAssertEqual(res.statusCode, 401, @"Should return 401 for non-string iss");
}

#pragma mark - V3: Missing or non-date exp must return 401

- (void)testMissingExpClaimReturns401 {
    // Access token with valid sub/iss but no exp claim.
    NSString *header = @"{\"alg\":\"ES256K\",\"typ\":\"at+jwt\"}";
    NSString *payload = @"{\"sub\":\"did:plc:user\",\"iss\":\"did:plc:user\"}";
    NSString *token = [NSString stringWithFormat:@"Bearer %@.%@.fakesig",
                       [self base64UrlEncode:header],
                       [self base64UrlEncode:payload]];

    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc]
        initWithExpectedAudience:@"did:plc:testaud"
                     signingKeyJWK:nil];

    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                               methodString:@"GET"
                                                       path:@"/"
                                                queryString:@""
                                                queryParams:@{}
                                                    version:@"HTTP/1.1"
                                                    headers:@{@"Authorization": token}
                                                       body:nil
                                              remoteAddress:nil];
    ATProtoHttpResponse *res = [[ATProtoHttpResponse alloc] init];

    NSString *did = [provider authenticateRequest:req response:res];

    XCTAssertNil(did, @"Token without exp claim should be rejected");
    XCTAssertEqual(res.statusCode, 401, @"Should return 401 for missing exp");
    XCTAssertTrue([res.jsonBody[@"message"] containsString:@"expiration"],
                  @"Error message should mention expiration");
}

- (void)testNonDateExpClaimReturns401 {
    // Access token with a non-date exp (string instead of number).
    NSString *header = @"{\"alg\":\"ES256K\",\"typ\":\"at+jwt\"}";
    NSString *payload = @"{\"sub\":\"did:plc:user\",\"iss\":\"did:plc:user\",\"exp\":\"not-a-timestamp\"}";
    NSString *token = [NSString stringWithFormat:@"Bearer %@.%@.fakesig",
                       [self base64UrlEncode:header],
                       [self base64UrlEncode:payload]];

    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc]
        initWithExpectedAudience:@"did:plc:testaud"
                     signingKeyJWK:nil];

    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                               methodString:@"GET"
                                                       path:@"/"
                                                queryString:@""
                                                queryParams:@{}
                                                    version:@"HTTP/1.1"
                                                    headers:@{@"Authorization": token}
                                                       body:nil
                                              remoteAddress:nil];
    ATProtoHttpResponse *res = [[ATProtoHttpResponse alloc] init];

    NSString *did = [provider authenticateRequest:req response:res];

    // Non-date exp → isKindOfClass fails → nil → treated as missing → rejected
    XCTAssertNil(did, @"Token with non-date exp claim should be rejected");
    XCTAssertEqual(res.statusCode, 401, @"Should return 401 for non-date exp");
}

- (void)testExpiredTokenStillReturns401 {
    // Token with a past exp should be rejected (pre-existing behavior, verify regression-free).
    NSString *header = @"{\"alg\":\"ES256K\",\"typ\":\"at+jwt\"}";
    NSString *payload = @"{\"sub\":\"did:plc:user\",\"iss\":\"did:plc:user\",\"exp\":1}";
    NSString *token = [NSString stringWithFormat:@"Bearer %@.%@.fakesig",
                       [self base64UrlEncode:header],
                       [self base64UrlEncode:payload]];

    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc]
        initWithExpectedAudience:@"did:plc:testaud"
                     signingKeyJWK:nil];

    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                               methodString:@"GET"
                                                       path:@"/"
                                                queryString:@""
                                                queryParams:@{}
                                                    version:@"HTTP/1.1"
                                                    headers:@{@"Authorization": token}
                                                       body:nil
                                              remoteAddress:nil];
    ATProtoHttpResponse *res = [[ATProtoHttpResponse alloc] init];

    NSString *did = [provider authenticateRequest:req response:res];

    XCTAssertNil(did, @"Expired token should be rejected");
    // May return 401 from exp check or from signature verification
    XCTAssertEqual(res.statusCode, 401, @"Should return 401 for expired token");
}

#pragma mark - V2: Non-string scope/lxm guard (no crash)

- (void)testNonStringScopeDoesNotCrash {
    // Service auth token with non-string scope. The guard should return nil
    // and the scope check should be skipped (not crashed).
    NSString *header = @"{\"alg\":\"ES256K\",\"typ\":\"JWT\"}";
    NSString *payload = @"{\"iss\":\"did:plc:test\",\"sub\":\"did:plc:test\",\"aud\":\"did:plc:aud\",\"exp\":9999999999,\"scope\":[1,2,3]}";
    NSString *token = [NSString stringWithFormat:@"Bearer %@.%@.fakesig",
                       [self base64UrlEncode:header],
                       [self base64UrlEncode:payload]];

    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc]
        initWithExpectedAudience:@"did:plc:testaud"
                     signingKeyJWK:nil];

    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                               methodString:@"GET"
                                                       path:@"/"
                                                queryString:@""
                                                queryParams:@{}
                                                    version:@"HTTP/1.1"
                                                    headers:@{@"Authorization": token}
                                                       body:nil
                                              remoteAddress:nil];
    ATProtoHttpResponse *res = [[ATProtoHttpResponse alloc] init];

    // Should not crash — scope guard returns nil, scope check is skipped,
    // token proceeds to signature verification (which fails, returning 401).
    XCTAssertNoThrow([provider authenticateRequest:req response:res],
                     @"Non-string scope claim should not cause a crash");
}

#pragma mark - Helpers

- (NSString *)base64UrlEncode:(NSString *)str {
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
