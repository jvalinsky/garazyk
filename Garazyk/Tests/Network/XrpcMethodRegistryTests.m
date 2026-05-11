// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Auth/DPoPUtil.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/TestKeyFixtures.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcMethodRegistry.h"

@interface XrpcMethodRegistryTests : XCTestCase
@end

static SecKeyRef xrpcCreateFixedP256PrivateKey(NSError **error) {
    return PDSTestCreateFixedP256PrivateKey(error);
}

static HttpResponse *xrpcDispatchRequest(XrpcDispatcher *dispatcher,
                                         NSString *path,
                                         NSDictionary<NSString *, NSString *> *headers) {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                           path:path
                                                    queryString:@""
                                                    queryParams:@{}
                                                        version:@"1.1"
                                                        headers:headers ?: @{}
                                                           body:[NSData data]
                                                   remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [HttpResponse response];
    [dispatcher handleRequest:request response:response];
    return response;
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
        NSString *dpopURLString = @"http://localhost:2583/xrpc/com.atproto.server.getSession";
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
        JWT *accessToken = [controller.jwtMinter mintAccessTokenForDID:did
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
        NSString *challengeNonce = [firstResponse headerForKey:@"DPoP-Nonce"];
        XCTAssertTrue(challengeNonce.length > 0);
        XCTAssertEqualObjects([firstResponse headerForKey:@"WWW-Authenticate"], @"DPoP error=\"use_dpop_nonce\"");
        XCTAssertEqualObjects([firstResponse headerForKey:@"Cache-Control"], @"no-store");
        XCTAssertEqualObjects([firstResponse headerForKey:@"Pragma"], @"no-cache");
        XCTAssertEqualObjects(firstResponse.jsonBody[@"message"], @"DPoP nonce required");

        DPoPToken *retryProof = [DPoPUtil createDPoPForMethod:@"GET"
                                                           uri:dpopURLString
                                                        nonce:challengeNonce
                                                          key:privateKey
                                                        error:&error];
        if ([error.domain isEqualToString:NSOSStatusErrorDomain]) {
            XCTSkip(@"Skipping DPoP nonce flow test: retry proof signing unavailable (%@)", error.localizedDescription);
        }
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
        NSString *successNonce = [secondResponse headerForKey:@"DPoP-Nonce"];
        XCTAssertTrue(successNonce.length > 0);
        XCTAssertNotEqualObjects(successNonce, challengeNonce);

        // Replay same DPoP proof (same jti) — should be rejected via JTI replay cache
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
        XCTAssertEqual(replayResponse.statusCode, HttpStatusUnauthorized,
                      @"Replayed DPoP proof (same jti) must be rejected");
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

- (void)testRegisterMethodsStatusCodeNotEqual {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    @try {
        PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
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
            HttpResponse *response = xrpcDispatchRequest(dispatcher, path, @{@"host": @"localhost:2583"});
            XCTAssertNotEqual(response.statusCode, HttpStatusNotFound, @"Expected registered route for %@", path);
            XCTAssertNotEqual(response.statusCode, HttpStatusMethodNotAllowed, @"Expected callable route for %@", path);
        }
    } @finally {
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testUnknownRouteReturnsNotFound {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    @try {
        PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];

        HttpResponse *response = xrpcDispatchRequest(dispatcher,
                                                     @"/xrpc/com.atproto.thisEndpointDoesNotExist",
                                                     @{@"host": @"localhost:2583"});
        XCTAssertEqual(response.statusCode, HttpStatusNotFound);
    } @finally {
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testRegisterMethodsWithControllerOverloadProvidesRoute {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    @try {
        PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        XCTAssertNotNil(app.legacyController);

        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher
                                               controller:app.legacyController];

        HttpResponse *response = xrpcDispatchRequest(dispatcher,
                                                     @"/xrpc/com.atproto.server.describeServer",
                                                     @{@"host": @"localhost:2583"});
        XCTAssertEqual(response.statusCode, HttpStatusOK);
        XCTAssertTrue([response.jsonBody isKindOfClass:[NSDictionary class]]);
        XCTAssertNotNil(response.jsonBody[@"did"]);
    } @finally {
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

@end
