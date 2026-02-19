#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Auth/DPoPUtil.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcMethodRegistry.h"

@interface XrpcMethodRegistryTests : XCTestCase
@end

static NSData *xrpcTestDataFromHexString(NSString *hex, NSUInteger expectedLength) {
    if (![hex isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *normalized = [[hex stringByReplacingOccurrencesOfString:@":" withString:@""] lowercaseString];
    if (normalized.length != expectedLength * 2) {
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithCapacity:expectedLength];
    for (NSUInteger i = 0; i < normalized.length; i += 2) {
        unsigned int value = 0;
        NSString *byteString = [normalized substringWithRange:NSMakeRange(i, 2)];
        NSScanner *scanner = [NSScanner scannerWithString:byteString];
        if (![scanner scanHexInt:&value]) {
            return nil;
        }
        uint8_t byte = (uint8_t)(value & 0xFF);
        [data appendBytes:&byte length:1];
    }
    return data.length == expectedLength ? data : nil;
}

static SecKeyRef xrpcCreateFixedP256PrivateKey(NSError **error) {
    NSData *xData = xrpcTestDataFromHexString(@"44073c1c6da8c2c9736c011ff13a2b3602a1d819e687582bdf87262ad1b12f50", 32);
    NSData *yData = xrpcTestDataFromHexString(@"79720e75ce2eaae05079972dd065b2eb437d9af5c9a974d3ce186525494bdc3c", 32);
    NSData *dData = xrpcTestDataFromHexString(@"8d12e99fb324f3c1bafed77fa91968a36c252590f0e55fef10f9bfb027b59504", 32);
    if (!xData || !yData || !dData) {
        if (error) {
            *error = [NSError errorWithDomain:@"XrpcMethodRegistryTests"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode fixed P-256 key bytes"}];
        }
        return NULL;
    }

    NSMutableData *privateKeyData = [NSMutableData dataWithCapacity:97];
    uint8_t prefix = 0x04;
    [privateKeyData appendBytes:&prefix length:1];
    [privateKeyData appendData:xData];
    [privateKeyData appendData:yData];
    [privateKeyData appendData:dData];

    NSDictionary *attributes = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
        (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPrivate,
        (id)kSecAttrKeySizeInBits: @256
    };

    CFErrorRef keyErrorRef = NULL;
    SecKeyRef privateKey = SecKeyCreateWithData((__bridge CFDataRef)privateKeyData, (__bridge CFDictionaryRef)attributes, &keyErrorRef);
    if (privateKey == NULL && error) {
        *error = keyErrorRef ? CFBridgingRelease(keyErrorRef) : nil;
    } else if (keyErrorRef) {
        CFRelease(keyErrorRef);
    }
    return privateKey;
}

@implementation XrpcMethodRegistryTests

- (void)testPublicKeyBytesFromMultibaseDecodesBase58 {
    NSError *error = nil;
    NSString *key = @"zQ3shZc2QzApp2oymGvQbzP8eKheVshBHbU4ZYjeXqwSKEn6N";
    NSData *bytes = [XrpcMethodRegistry publicKeyBytesFromMultibase:key error:&error];

    XCTAssertNotNil(bytes, @"Decoded bytes should exist for a valid base58 publicKeyMultibase");
    XCTAssertNil(error, @"No error should be produced for valid input");
    XCTAssertGreaterThan(bytes.length, 0, @"Result must not be empty");
}

- (void)testExtractDIDFromAuthHeaderDPoPNonceChallengeAndRetry {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    SecKeyRef privateKey = NULL;
    @try {
        PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        PDSController *controller = app.legacyController;
        XCTAssertNotNil(controller);
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];

        NSError *error = nil;
        NSDictionary *account = [controller createAccountForEmail:@"nonce@example.com"
                                                         password:@"password"
                                                           handle:@"nonce.user"
                                                              did:nil
                                                            error:&error];
        XCTAssertNotNil(account);
        XCTAssertNil(error);

        NSString *did = account[@"did"];
        NSString *handle = @"nonce.user";
        XCTAssertNotNil(did);

        NSError *keyError = nil;
        privateKey = xrpcCreateFixedP256PrivateKey(&keyError);
        if (privateKey == NULL) {
            XCTSkip(@"Skipping DPoP nonce flow test: key import unavailable (%@)", keyError);
        }

        NSString *path = @"/xrpc/com.atproto.server.getSession";
        NSString *dpopURLString = @"http://localhost:2583/xrpc/com.atproto.server.getSession";
        NSURL *dpopURL = [NSURL URLWithString:dpopURLString];

        DPoPToken *initialProof = [DPoPUtil createDPoPForMethod:@"GET"
                                                             uri:dpopURLString
                                                          nonce:nil
                                                            key:privateKey
                                                          error:&error];
        XCTAssertNotNil(initialProof);
        XCTAssertNil(error);

        NSString *thumbprint = nil;
        BOOL initialProofValid = [OAuth2DPoPProof verifyProof:initialProof.jwt
                                                       method:@"GET"
                                                          url:dpopURL
                                                        nonce:nil
                                                 requireNonce:NO
                                                outThumbprint:&thumbprint
                                                        error:&error];
        XCTAssertTrue(initialProofValid);
        XCTAssertNil(error);
        XCTAssertTrue(thumbprint.length > 0);

        JWT *accessToken = [controller.jwtMinter mintAccessTokenForDID:did
                                                                 handle:handle
                                                                 scopes:@[@"com.atproto.access"]
                                                       dpopKeyThumbprint:thumbprint
                                                                  error:&error];
        XCTAssertNotNil(accessToken);
        XCTAssertNil(error);
        NSString *authorization = [NSString stringWithFormat:@"DPoP %@", [accessToken encodedToken]];

        HttpRequest *firstRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                            methodString:@"GET"
                                                                    path:path
                                                             queryString:@""
                                                             queryParams:@{}
                                                                 version:@"1.1"
                                                                 headers:@{
                                                                     @"authorization": authorization,
                                                                     @"host": @"localhost:2583",
                                                                     @"dpop": initialProof.jwt
                                                                 }
                                                                    body:[NSData data]
                                                            remoteAddress:@"127.0.0.1"];
        HttpResponse *firstResponse = [[HttpResponse alloc] init];
        [dispatcher handleRequest:firstRequest response:firstResponse];
        XCTAssertEqual(firstResponse.statusCode, HttpStatusUnauthorized);
        NSString *challengeNonce = firstResponse.headers[@"DPoP-Nonce"];
        XCTAssertTrue(challengeNonce.length > 0);
        XCTAssertEqualObjects(firstResponse.headers[@"WWW-Authenticate"], @"DPoP error=\"use_dpop_nonce\"");

        DPoPToken *retryProof = [DPoPUtil createDPoPForMethod:@"GET"
                                                           uri:dpopURLString
                                                        nonce:challengeNonce
                                                          key:privateKey
                                                        error:&error];
        XCTAssertNotNil(retryProof);
        XCTAssertNil(error);

        HttpRequest *secondRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                             methodString:@"GET"
                                                                     path:path
                                                              queryString:@""
                                                              queryParams:@{}
                                                                  version:@"1.1"
                                                                  headers:@{
                                                                      @"authorization": authorization,
                                                                      @"host": @"localhost:2583",
                                                                      @"dpop": retryProof.jwt,
                                                                      @"dpop-nonce": challengeNonce
                                                                  }
                                                                     body:[NSData data]
                                                             remoteAddress:@"127.0.0.1"];
        HttpResponse *secondResponse = [[HttpResponse alloc] init];
        [dispatcher handleRequest:secondRequest response:secondResponse];
        XCTAssertEqual(secondResponse.statusCode, HttpStatusOK);
        XCTAssertEqualObjects(secondResponse.jsonBody[@"did"], did);
        XCTAssertNil(secondResponse.headers[@"DPoP-Nonce"]);

        HttpRequest *replayRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                             methodString:@"GET"
                                                                     path:path
                                                              queryString:@""
                                                              queryParams:@{}
                                                                  version:@"1.1"
                                                                  headers:@{
                                                                      @"authorization": authorization,
                                                                      @"host": @"localhost:2583",
                                                                      @"dpop": retryProof.jwt,
                                                                      @"dpop-nonce": challengeNonce
                                                                  }
                                                                     body:[NSData data]
                                                             remoteAddress:@"127.0.0.1"];
        HttpResponse *replayResponse = [[HttpResponse alloc] init];
        [dispatcher handleRequest:replayRequest response:replayResponse];
        XCTAssertEqual(replayResponse.statusCode, HttpStatusUnauthorized);
        NSString *rotatedNonce = replayResponse.headers[@"DPoP-Nonce"];
        XCTAssertTrue(rotatedNonce.length > 0);
        XCTAssertNotEqualObjects(rotatedNonce, challengeNonce);
    } @finally {
        if (privateKey) {
            CFRelease(privateKey);
        }
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testOAuth2DPoPProofVerifyUsesProvidedNonceParameter {
    NSError *keyError = nil;
    SecKeyRef privateKey = xrpcCreateFixedP256PrivateKey(&keyError);
    if (privateKey == NULL) {
        XCTSkip(@"Skipping nonce parameter test: key import unavailable (%@)", keyError);
    }

    @try {
        NSString *urlString = @"https://example.com/xrpc/com.atproto.server.getSession";
        NSURL *url = [NSURL URLWithString:urlString];
        NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
        XCTAssertTrue(nonce.length > 0);

        NSError *error = nil;
        DPoPToken *proof = [DPoPUtil createDPoPForMethod:@"GET"
                                                      uri:urlString
                                                   nonce:nonce
                                                     key:privateKey
                                                   error:&error];
        XCTAssertNotNil(proof);
        XCTAssertNil(error);

        NSString *thumbprint = nil;
        BOOL valid = [OAuth2DPoPProof verifyProof:proof.jwt
                                           method:@"GET"
                                              url:url
                                            nonce:@"different-nonce"
                                    outThumbprint:&thumbprint
                                            error:&error];
        XCTAssertFalse(valid);
        XCTAssertEqualObjects(error.userInfo[@"use_dpop_nonce"], @YES);

        error = nil;
        thumbprint = nil;
        valid = [OAuth2DPoPProof verifyProof:proof.jwt
                                      method:@"GET"
                                         url:url
                                       nonce:nonce
                               outThumbprint:&thumbprint
                                       error:&error];
        XCTAssertTrue(valid);
        XCTAssertNil(error);
        XCTAssertTrue(thumbprint.length > 0);
    } @finally {
        CFRelease(privateKey);
    }
}

@end
