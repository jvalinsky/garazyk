#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Auth/DPoPUtil.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcMethodRegistry.h"

@interface XrpcMethodRegistryTests : XCTestCase
@end

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

        NSDictionary *attributes = @{
            (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
            (id)kSecAttrKeySizeInBits: @256
        };
        CFErrorRef keyErrorRef = NULL;
        privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &keyErrorRef);
        if (privateKey == NULL) {
            NSError *keyError = CFBridgingRelease(keyErrorRef);
            XCTSkip(@"Skipping DPoP nonce flow test: key generation unavailable (%@)", keyError);
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
                                                                     @"host": @"localhost:2583",
                                                                     @"dpop": initialProof.jwt
                                                                 }
                                                                    body:[NSData data]
                                                            remoteAddress:@"127.0.0.1"];
        HttpResponse *firstResponse = [[HttpResponse alloc] init];
        NSString *firstDid = [XrpcMethodRegistry extractDIDFromAuthHeader:authorization
                                                                controller:controller
                                                                   request:firstRequest
                                                                  response:firstResponse];
        XCTAssertNil(firstDid);
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
                                                                      @"host": @"localhost:2583",
                                                                      @"dpop": retryProof.jwt,
                                                                      @"dpop-nonce": challengeNonce
                                                                  }
                                                                     body:[NSData data]
                                                             remoteAddress:@"127.0.0.1"];
        HttpResponse *secondResponse = [[HttpResponse alloc] init];
        NSString *secondDid = [XrpcMethodRegistry extractDIDFromAuthHeader:authorization
                                                                 controller:controller
                                                                    request:secondRequest
                                                                   response:secondResponse];
        XCTAssertEqualObjects(secondDid, did);
        XCTAssertNil(secondResponse.headers[@"DPoP-Nonce"]);

        HttpRequest *replayRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                             methodString:@"GET"
                                                                     path:path
                                                              queryString:@""
                                                              queryParams:@{}
                                                                  version:@"1.1"
                                                                  headers:@{
                                                                      @"host": @"localhost:2583",
                                                                      @"dpop": retryProof.jwt,
                                                                      @"dpop-nonce": challengeNonce
                                                                  }
                                                                     body:[NSData data]
                                                             remoteAddress:@"127.0.0.1"];
        HttpResponse *replayResponse = [[HttpResponse alloc] init];
        NSString *replayDid = [XrpcMethodRegistry extractDIDFromAuthHeader:authorization
                                                                 controller:controller
                                                                    request:replayRequest
                                                                   response:replayResponse];
        XCTAssertNil(replayDid);
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

@end
