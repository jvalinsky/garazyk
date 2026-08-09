// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "App/PDSController.h"
#import "Auth/DPoPUtil.h"
#import "Auth/Crypto/JWT.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/TestKeyFixtures.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcIdentityHelper.h"
#import "Video/VideoJobStore.h"

@interface XrpcMethodRegistryTests : XCTestCase
@end

static SecKeyRef xrpcCreateFixedP256PrivateKey(NSError **error) {
    return PDSTestCreateFixedP256PrivateKey(error);
}

static ATProtoHttpResponse *xrpcDispatchRequest(XrpcDispatcher *dispatcher,
                                         NSString *path,
                                         NSDictionary<NSString *, NSString *> *headers) {
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                           path:path
                                                    queryString:@""
                                                    queryParams:@{}
                                                        version:@"1.1"
                                                        headers:headers ?: @{}
                                                           body:[NSData data]
                                                   remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *response = [ATProtoHttpResponse response];
    [dispatcher handleRequest:request response:response];
    return response;
}

@implementation XrpcMethodRegistryTests

- (void)testApplicationExposesProtocolBackedVideoJobStore {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    PDSApplication *app = nil;
    @try {
        app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        XCTAssertNotNil(app.videoJobStore);
        XCTAssertTrue([app.videoJobStore conformsToProtocol:@protocol(VideoJobStore)]);
        XCTAssertEqual(app.videoJobStore, app.legacyController.application.videoJobStore);
    } @finally {
        [app stop];
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testPublicKeyBytesFromMultibaseDecodesBase58 {
    NSError *error = nil;
    NSString *key = @"zQ3shZc2QzApp2oymGvQbzP8eKheVshBHbU4ZYjeXqwSKEn6N";
    NSData *bytes = [XrpcIdentityHelper publicKeyBytesFromMultibase:key error:&error];

    XCTAssertNotNil(bytes, @"Decoded bytes should exist for a valid base58 publicKeyMultibase");
    XCTAssertNil(error, @"No error should be produced for valid input");
    XCTAssertGreaterThan(bytes.length, 0, @"Result must not be empty");
}

- (void)testExtractDIDFromAuthHeaderDPoPNonceChallengeAndRetry {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    SecKeyRef privateKey = NULL;
    PDSApplication *app = nil;
    @try {
        app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        app.configuration.requireDPoPNonce = YES;
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
        // The server reconstructs the expected DPoP htu from jwtMinter.issuer
        // (authoritative over the Host header once an issuer is configured),
        // not from kPDSTestDPoPBaseURL — which defaults to port 2583 while
        // ATProtoServiceConfiguration's own default serverPort is 8080. Build
        // the proof's htu from the same issuer the server will check against.
        NSString *dpopURLString = [controller.jwtMinter.issuer stringByAppendingString:@"/xrpc/com.atproto.server.getSession"];
        NSURL *dpopURL = [NSURL URLWithString:dpopURLString];

        DPoPToken *initialProof = [DPoPUtil createDPoPForMethod:@"GET"
                                                             uri:dpopURLString
                                                          nonce:nil
                                                            key:privateKey
                                                          error:&error];
        if ([error.domain isEqualToString:NSOSStatusErrorDomain]) {
            XCTSkip(@"Skipping DPoP nonce flow test: proof signing unavailable (%@)", error.localizedDescription);
        }
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

        error = nil;
        ATProtoJWT *accessToken = [controller.jwtMinter mintAccessTokenForDID:did
                                                                 handle:handle
                                                                 scopes:@[@"com.atproto.access"]
                                                       dpopKeyThumbprint:thumbprint
                                                                  error:&error];
        if ([error.domain isEqualToString:NSOSStatusErrorDomain]) {
            XCTSkip(@"Skipping DPoP nonce flow test: token signing unavailable (%@)", error.localizedDescription);
        }
        XCTAssertNotNil(accessToken);
        XCTAssertNil(error);
        NSString *authorization = [NSString stringWithFormat:@"DPoP %@", [accessToken encodedToken]];
        NSString *encodedAccessToken = [accessToken encodedToken];

        // A DPoP proof used with a resource-server access token must bind that
        // token through its RFC 9449 `ath` claim. The unsigned-key proof above
        // is only used to derive the JWK thumbprint needed to mint the token.
        error = nil;
        initialProof = [DPoPUtil createDPoPForMethod:@"GET"
                                                 uri:dpopURLString
                                               nonce:nil
                                         accessToken:encodedAccessToken
                                                 key:privateKey
                                               error:&error];
        XCTAssertNotNil(initialProof);
        XCTAssertNil(error);

        ATProtoHttpRequest *firstRequest = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                            methodString:@"GET"
                                                                    path:path
                                                             queryString:@""
                                                             queryParams:@{}
                                                                 version:@"1.1"
                                                                 headers:@{
                                                                     @"authorization": authorization,
                                                                     @"host": kPDSTestPDSHostHeader,
                                                                     @"dpop": initialProof.jwt
                                                                 }
                                                                    body:[NSData data]
                                                            remoteAddress:@"127.0.0.1"];
        ATProtoHttpResponse *firstResponse = [[ATProtoHttpResponse alloc] init];
        [dispatcher handleRequest:firstRequest response:firstResponse];
        XCTAssertEqual(firstResponse.statusCode, HttpStatusUnauthorized);
        NSString *challengeNonce = [firstResponse headerForKey:@"DPoP-Nonce"];
        XCTAssertTrue(challengeNonce.length > 0);
        XCTAssertEqualObjects([firstResponse headerForKey:@"WWW-Authenticate"], @"DPoP error=\"use_dpop_nonce\"");
        XCTAssertEqualObjects([firstResponse headerForKey:@"Cache-Control"], @"no-store");
        XCTAssertEqualObjects([firstResponse headerForKey:@"Pragma"], @"no-cache");
        XCTAssertEqualObjects(firstResponse.jsonBody[@"message"], @"DPoP nonce required");

        DPoPToken *retryProof = [DPoPUtil createDPoPForMethod:@"GET"
                                                           uri:dpopURLString
                                                        nonce:challengeNonce
                                                  accessToken:encodedAccessToken
                                                          key:privateKey
                                                        error:&error];
        if ([error.domain isEqualToString:NSOSStatusErrorDomain]) {
            XCTSkip(@"Skipping DPoP nonce flow test: retry proof signing unavailable (%@)", error.localizedDescription);
        }
        XCTAssertNotNil(retryProof);
        XCTAssertNil(error);

        ATProtoHttpRequest *secondRequest = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                             methodString:@"GET"
                                                                     path:path
                                                              queryString:@""
                                                              queryParams:@{}
                                                                  version:@"1.1"
                                                                  headers:@{
                                                                      @"authorization": authorization,
                                                                      @"host": kPDSTestPDSHostHeader,
                                                                      @"dpop": retryProof.jwt,
                                                                      @"dpop-nonce": challengeNonce
                                                                  }
                                                                     body:[NSData data]
                                                             remoteAddress:@"127.0.0.1"];
        ATProtoHttpResponse *secondResponse = [[ATProtoHttpResponse alloc] init];
        [dispatcher handleRequest:secondRequest response:secondResponse];
        XCTAssertEqual(secondResponse.statusCode, HttpStatusOK);
        XCTAssertEqualObjects(secondResponse.jsonBody[@"did"], did);
        NSString *successNonce = [secondResponse headerForKey:@"DPoP-Nonce"];
        XCTAssertTrue(successNonce.length > 0);
        XCTAssertNotEqualObjects(successNonce, challengeNonce);

        // Replay same DPoP proof (same jti) — should be rejected via JTI replay cache
        ATProtoHttpRequest *replayRequest = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                              methodString:@"GET"
                                                                      path:path
                                                               queryString:@""
                                                               queryParams:@{}
                                                                   version:@"1.1"
                                                                   headers:@{
                                                                       @"authorization": authorization,
                                                                       @"host": kPDSTestPDSHostHeader,
                                                                       @"dpop": retryProof.jwt,
                                                                       @"dpop-nonce": challengeNonce
                                                                   }
                                                                      body:[NSData data]
                                                              remoteAddress:@"127.0.0.1"];
        ATProtoHttpResponse *replayResponse = [[ATProtoHttpResponse alloc] init];
        [dispatcher handleRequest:replayRequest response:replayResponse];
        XCTAssertEqual(replayResponse.statusCode, HttpStatusUnauthorized,
                      @"Replayed DPoP proof (same jti) must be rejected");
    } @finally {
        if (privateKey) {
            CFRelease(privateKey);
        }
        [app stop];
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

- (void)testRegisterMethodsStatusCodeNotEqual {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = nil;
    @try {
        app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];

        NSArray<NSString *> *paths = @[
            @"/xrpc/com.atproto.server.describeServer",
            @"/xrpc/com.atproto.identity.resolveHandle",
            @"/xrpc/com.atproto.sync.getLatestCommit",
            @"/xrpc/com.atproto.repo.describeRepo",
            @"/xrpc/app.bsky.actor.getProfile",
            @"/xrpc/com.atproto.admin.getInviteCodes"
        ];

        for (NSString *path in paths) {
            ATProtoHttpResponse *response = xrpcDispatchRequest(dispatcher, path, @{@"host": kPDSTestPDSHostHeader});
            XCTAssertNotEqual(response.statusCode, HttpStatusNotFound, @"Expected registered route for %@", path);
            XCTAssertNotEqual(response.statusCode, HttpStatusMethodNotAllowed, @"Expected callable route for %@", path);
        }
    } @finally {
        [app stop];
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testUnknownRouteReturnsNotFound {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = nil;
    @try {
        app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];

        ATProtoHttpResponse *response = xrpcDispatchRequest(dispatcher,
                                                     @"/xrpc/com.atproto.thisEndpointDoesNotExist",
                                                     @{@"host": kPDSTestPDSHostHeader});
        XCTAssertEqual(response.statusCode, HttpStatusNotFound);
    } @finally {
        [app stop];
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testRegisterMethodsWithControllerOverloadProvidesRoute {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = nil;
    @try {
        app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        XCTAssertNotNil(app.legacyController);

        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher
                                               controller:app.legacyController];

        ATProtoHttpResponse *response = xrpcDispatchRequest(dispatcher,
                                                     @"/xrpc/com.atproto.server.describeServer",
                                                     @{@"host": kPDSTestPDSHostHeader});
        XCTAssertEqual(response.statusCode, HttpStatusOK);
        XCTAssertTrue([response.jsonBody isKindOfClass:[NSDictionary class]]);
        XCTAssertNotNil(response.jsonBody[@"did"]);
    } @finally {
        [app stop];
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

@end
