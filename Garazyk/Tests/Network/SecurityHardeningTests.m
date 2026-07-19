// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/Pool/DatabasePool.h"
#import "Core/ATProtoValidator.h"
#import "Services/PDS/PDSBlobService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Auth/DPoPUtil.h"
#import "Auth/JWT.h"
#import "Auth/TestKeyFixtures.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Auth/Crypto/AuthCryptoJWK.h"

@interface NetworkSecurityHardeningTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy) NSString *accessJwt;
@property (nonatomic, copy) NSString *refreshJwt;
@end

@implementation NetworkSecurityHardeningTests

- (void)setUp {
    [super setUp];
    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.controller = app.legacyController;
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:app];

    NSError *error = nil;
    NSDictionary *account = [self.controller createAccountForEmail:@"test@example.com"
                                                          password:@"password"
                                                            handle:@"test.user"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.did = account[@"did"];

    NSDictionary *session = [self.controller loginWithHandle:@"test.user" password:@"password" error:&error];
    XCTAssertNil(error);
    self.accessJwt = session[@"accessJwt"];
    self.refreshJwt = session[@"refreshJwt"];
    XCTAssertNotNil(self.accessJwt);
    XCTAssertNotNil(self.refreshJwt);
}

- (void)tearDown {
    [self.controller stopServer];
    self.dispatcher = nil;
    self.controller = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (HttpResponse *)sendJsonRequestWithPath:(NSString *)path
                                body:(NSDictionary *)body
                               headers:(NSDictionary<NSString *, NSString *> *)headers {
    // HttpRequest's initializer marks the body parameter nonnull, so we must supply a real
    // (non-nil) NSData even when the test caller means "no payload". [NSData data]'s return
    // type isn't inferred as nonnull by the analyzer, so we cast explicitly to satisfy
    // -Wnonnull. refreshSession is the only existing caller that passes body:nil and it
    // tolerates an empty JSON payload ({} via @"" dataUsingEncoding:) the same way it does
    // an absent body.
    NSData *bodyData = body
        ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil]
        : (NSData * _Nonnull) [@"" dataUsingEncoding:NSASCIIStringEncoding];
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                   methodString:@"POST"
                                                           path:path
                                                    queryString:@""
                                                    queryParams:@{}
                                                        version:@"1.1"
                                                        headers:allHeaders
                                                           body:bodyData
                                                     remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (HttpResponse *)sendRawRequestWithPath:(NSString *)path
                                bodyData:(NSData *)bodyData
                                 headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                   methodString:@"POST"
                                                           path:path
                                                    queryString:@""
                                                    queryParams:@{}
                                                        version:@"1.1"
                                                        headers:allHeaders
                                                           body:bodyData
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                              queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    // HttpRequest's body: parameter is nonnull (NS_ASSUME_NONNULL_BEGIN in HttpRequest.h), so
    // a bare `body:nil` literal now trips -Wnonnull since the rest of the file was tightened.
    // Match the JSON helper: hand the GET request an explicit nonnull empty payload.
    NSData * _Nonnull emptyBody = [@"" dataUsingEncoding:NSASCIIStringEncoding];
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                           path:path
                                                    queryString:@""
                                                    queryParams:queryParams ?: @{}
                                                        version:@"1.1"
                                                        headers:allHeaders
                                                           body:emptyBody
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (void)testRefreshTokenRotation {
    // 1. Refresh session
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.refreshJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.refreshSession"
                                                      body:nil
                                                   headers:@{@"authorization": authHeader}];
    
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"accessJwt"]);
    XCTAssertNotNil(response.jsonBody[@"refreshJwt"]);
    XCTAssertNotEqualObjects(response.jsonBody[@"refreshJwt"], self.refreshJwt, @"Refresh token should be rotated");
    
    NSString *newRefreshJwt = response.jsonBody[@"refreshJwt"];
    
    // 2. Try to use OLD refresh token again
    HttpResponse *retryOldResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.refreshSession"
                                                             body:nil
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(retryOldResponse.statusCode, 401, @"Old refresh token should be revoked after rotation");
    
    // 3. Use NEW refresh token
    NSString *newAuthHeader = [NSString stringWithFormat:@"Bearer %@", newRefreshJwt];
    HttpResponse *useNewResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.refreshSession"
                                                            body:nil
                                                         headers:@{@"authorization": newAuthHeader}];
    XCTAssertEqual(useNewResponse.statusCode, 200, @"New refresh token should work");
}

- (void)testRefreshTokenExpiry {
    // The refreshSession handler routes through
    //   _sessionRepository sessionInfoForRefreshToken:error:
    // which executes
    //   SELECT account_did, session_id FROM refresh_tokens WHERE token = ? AND expires_at > ?
    // To exercise expiry specifically (and not revocation), we INSERT OR REPLACE the same
    // stored row with expires_at in the distant past, then assert refreshSession rejects it.
    // setUp already issues a fresh, unrotated token, so no positive-control round-trip is
    // needed (and one would itself rotate the token we're trying to backdate).
    PDSServiceDatabases *serviceDBs = self.controller.serviceDatabases;
    XCTAssertNotNil(serviceDBs, @"PDSController must expose serviceDatabases");

    NSError *infoError = nil;
    NSDictionary *sessionInfo = [serviceDBs sessionInfoForRefreshToken:self.refreshJwt
                                                                error:&infoError];
    XCTAssertNotNil(sessionInfo,
                   @"Pre-backdating refresh token must be discoverable, infoError=%@", infoError);
    NSString *sessionID = sessionInfo[@"session_id"];
    XCTAssertNotNil(sessionID,
                   @"Stored refresh token must carry a session_id, got: %@", sessionInfo);

    NSError *dbError = nil;
    PDSDatabase *serviceDB = [serviceDBs serviceDatabaseWithError:&dbError];
    XCTAssertNotNil(serviceDB, @"Failed to open service DB: %@", dbError);
    // storeRefreshToken: does INSERT OR REPLACE on (token). It keeps the same token +
    // session_id but resets created_at to "now" and stamps expires_at to the supplied value.
    // The created_at shift is irrelevant to the expiry check below; only expires_at matters.
    BOOL stored = [serviceDB storeRefreshToken:self.refreshJwt
                                      sessionID:sessionID
                                   forAccountDid:self.did
                                      expiresAt:[NSDate distantPast]
                                          error:&dbError];
    XCTAssertTrue(stored, @"Backdating refresh token must succeed: %@", dbError);

    // Backdating done; an unmutated refreshSession invocation must now return 401.
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.refreshJwt];
    HttpResponse *expiredResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.refreshSession"
                                                              body:nil
                                                           headers:@{@"authorization": authHeader}];
    XCTAssertEqual(expiredResponse.statusCode, 401,
                   @"Expired refresh token must be rejected with 401");
    // RpcServerPack.refreshSession maps a nil session (because the WHERE expires_at > ?
    // filter excludes the backdated row) through PDSAccountService.refreshAccessToken:,
    // which returns an AuthenticationFailed error. Pin the code so a future refactor that
    // renames the error to e.g. TokenInvalid is caught here instead of silently passing.
    XCTAssertEqualObjects(expiredResponse.jsonBody[@"error"], @"AuthenticationFailed",
                          @"Expired-token rejection must surface an AuthenticationFailed error");
    NSString *message = expiredResponse.jsonBody[@"message"];
    XCTAssertNotNil(message,
                    @"Expired-token rejection should carry a message explaining the rejection");
}

- (void)testDPoPNonceChallenge {
    // When (and when NOT) the `use_dpop_nonce` challenge path fires
    // =============================================================
    // The XRPC auth helper emits BOTH a `DPoP-Nonce` header AND a
    // `WWW-Authenticate: DPoP error="use_dpop_nonce"` response only when
    // the verifier's failure error carries `use_dpop_nonce = YES`.
    //
    // That flag is set in exactly three branches of
    // AuthCryptoDPoP.verifyProof:method:url:nonce:requireNonce:...:
    //   1. `requireNonce=YES` and the proof's `nonce` claim is absent
    //   2. `nonce` was supplied by the caller and the proof's `nonce`
    //      claim differs from it
    //   3. A nonce validator was supplied and rejected the proof's nonce
    //
    // It does NOT fire for parse, signature, jwk, htm, htu, iat, or
    // jti-replay failures — those emit a generic 401 with a non-challenge
    // `WWW-Authenticate: DPoP` value and an `error` code such as
    // `invalid_dpop_proof` or `jti_replay`. This test exercises branch (1)
    // by setting `requireDPoPNonce=YES`, minting a structurally valid DPoP
    // proof *without* a nonce, and asserting the response carries both
    // challenge headers plus the boilerplate no-store / no-cache /
    // "DPoP nonce required" body.
    //
    // Implementation note: setUp's `self.dispatcher` was registered with
    // `requireDPoPNonce=NO` (its default). To exercise branch (1) without
    // changing global config for every other test in this class, this case
    // spins up a fresh PDSApplication with the flag enabled. SetUp of the
    // temporary directory and SecKeyRef is scoped to this method.

    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSError *fsError = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&fsError];
    XCTAssertNil(fsError);

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
        XCTAssertNotNil(did);

        NSError *keyError = nil;
        privateKey = PDSTestCreateFixedP256PrivateKey(&keyError);
        if (privateKey == NULL) {
            XCTSkip(@"Skipping DPoP nonce challenge test: key import unavailable (%@)", keyError);
        }

        NSString *path = @"/xrpc/com.atproto.server.getSession";
        NSString *dpopURLString = [kPDSTestDPoPBaseURL stringByAppendingString:@"/xrpc/com.atproto.server.getSession"];
        NSURL *dpopURL = [NSURL URLWithString:dpopURLString];

        // Real signed DPoP proof — without a nonce — so the verifier
        // reaches the *nonce* check rather than the parse/signature pipeline.
        DPoPToken *proof = [DPoPUtil createDPoPForMethod:@"GET"
                                                     uri:dpopURLString
                                                  nonce:nil
                                                    key:privateKey
                                                  error:&error];
        if ([error.domain isEqualToString:NSOSStatusErrorDomain]) {
            XCTSkip(@"Skipping DPoP nonce challenge test: proof signing unavailable (%@)", error.localizedDescription);
        }
        XCTAssertNotNil(proof);
        XCTAssertNil(error);

        NSString *thumbprint = [self thumbprintFromDPoPProofJWT:proof.jwt error:&error];
        XCTAssertNotNil(thumbprint, @"Could not derive thumbprint from the proof JWT: %@", error);

        // Mint a DPoP-bound access token tied to the proof's key thumbprint.
        error = nil;
        JWT *accessToken = [controller.jwtMinter mintAccessTokenForDID:did
                                                                handle:@"nonce.user"
                                                                scopes:@[@"com.atproto.access"]
                                                      dpopKeyThumbprint:thumbprint
                                                                 error:&error];
        if ([error.domain isEqualToString:NSOSStatusErrorDomain]) {
            XCTSkip(@"Skipping DPoP nonce challenge test: token signing unavailable (%@)", error.localizedDescription);
        }
        XCTAssertNotNil(accessToken);
        XCTAssertNil(error);

        NSString *authorization = [NSString stringWithFormat:@"DPoP %@", [accessToken encodedToken]];
        // HttpRequest's `body:` parameter is nonnull, so the analyzer insists on a real
        // NSData even for routes that don't read a payload.
        NSData * _Nonnull emptyBody = [@"" dataUsingEncoding:NSASCIIStringEncoding];

        HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                        methodString:@"GET"
                                                                path:path
                                                         queryString:@""
                                                         queryParams:@{}
                                                             version:@"1.1"
                                                             headers:@{
                                                                 @"authorization": authorization,
                                                                 @"host": kPDSTestPDSHostHeader,
                                                                 @"dpop": proof.jwt
                                                             }
                                                                body:emptyBody
                                                       remoteAddress:@"127.0.0.1"];
        HttpResponse *response = [[HttpResponse alloc] init];
        [dispatcher handleRequest:request response:response];

        XCTAssertEqual(response.statusCode, HttpStatusUnauthorized,
                       @"A nonce-required proof without a nonce must be rejected");
        // Both challenge headers are emitted together: DPoP-Nonce carries the
        // fresh nonce to retry with; WWW-Authenticate names the challenge so
        // OAuth clients can branch on the `error="..."` field.
        XCTAssertTrue([response headerForKey:@"DPoP-Nonce"].length > 0,
                       @"Challenge response must include a fresh DPoP-Nonce header");
        XCTAssertEqualObjects([response headerForKey:@"WWW-Authenticate"],
                              @"DPoP error=\"use_dpop_nonce\"",
                              @"Challenge response must name the use_dpop_nonce challenge");
        // Boilerplate no-store / no-cache accompany nonce challenges so the
        // challenge response cannot be cached by intermediaries.
        XCTAssertEqualObjects([response headerForKey:@"Cache-Control"], @"no-store");
        XCTAssertEqualObjects([response headerForKey:@"Pragma"], @"no-cache");
        XCTAssertEqualObjects(response.jsonBody[@"message"], @"DPoP nonce required",
                              @"Challenge body must explain the rejection reason");
    } @finally {
        if (privateKey) {
            CFRelease(privateKey);
        }
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testDPoPNonceRetrySucceeds {
    // End-to-end DPoP nonce dance against a server with requireDPoPNonce=YES:
    //   1. Send a nonce-less DPoP proof. The handler responds with 401 and a
    //      challenge carrying a fresh `DPoP-Nonce` value.
    //   2. Parse the challenge nonce. Build a second DPoP proof that carries
    //      it both as the JWT `nonce` claim AND in a `dpop-nonce` HTTP header
    //      (the verifier reads either path; setting both is safe).
    //   3. Replay to the same endpoint. The proof now carries the challenge
    //      nonce, so the auth helper accepts it and responds 200.
    // The success response also carries a fresh `DPoP-Nonce` (different from
    // the challenge), which is a useful invariant to pin: every server-side
    // response rotates the nonce so subsequent requests always see a new one.

    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSError *fsError = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&fsError];
    XCTAssertNil(fsError);

    SecKeyRef privateKey = NULL;
    @try {
        PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        app.configuration.requireDPoPNonce = YES;
        PDSController *controller = app.legacyController;
        XCTAssertNotNil(controller);

        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];

        NSError *error = nil;
        NSDictionary *account = [controller createAccountForEmail:@"nonce-retry@example.com"
                                                          password:@"password"
                                                            handle:@"nonce.retry"
                                                               did:nil
                                                             error:&error];
        XCTAssertNotNil(account);
        XCTAssertNil(error);
        NSString *did = account[@"did"];
        XCTAssertNotNil(did);

        NSError *keyError = nil;
        privateKey = PDSTestCreateFixedP256PrivateKey(&keyError);
        if (privateKey == NULL) {
            XCTSkip(@"Skipping DPoP nonce retry test: key import unavailable (%@)", keyError);
        }

        NSString *path = @"/xrpc/com.atproto.server.getSession";
        NSString *dpopURLString = [kPDSTestDPoPBaseURL stringByAppendingString:@"/xrpc/com.atproto.server.getSession"];
        NSURL *dpopURL = [NSURL URLWithString:dpopURLString];

        // Initial proof carries no nonce — the verifier trips the
        // `requireNonce && !proofNonce` branch and emits the challenge.
        error = nil;
        DPoPToken *initialProof = [DPoPUtil createDPoPForMethod:@"GET"
                                                             uri:dpopURLString
                                                          nonce:nil
                                                            key:privateKey
                                                          error:&error];
        if ([error.domain isEqualToString:NSOSStatusErrorDomain]) {
            XCTSkip(@"Skipping DPoP nonce retry test: initial proof signing unavailable (%@)", error.localizedDescription);
        }
        XCTAssertNotNil(initialProof);
        XCTAssertNil(error);

        NSString *thumbprint = [self thumbprintFromDPoPProofJWT:initialProof.jwt error:&error];
        XCTAssertNotNil(thumbprint, @"Could not derive thumbprint from the proof JWT: %@", error);

        error = nil;
        JWT *accessToken = [controller.jwtMinter mintAccessTokenForDID:did
                                                                handle:@"nonce.retry"
                                                                scopes:@[@"com.atproto.access"]
                                                      dpopKeyThumbprint:thumbprint
                                                                 error:&error];
        if ([error.domain isEqualToString:NSOSStatusErrorDomain]) {
            XCTSkip(@"Skipping DPoP nonce retry test: token signing unavailable (%@)", error.localizedDescription);
        }
        XCTAssertNotNil(accessToken);
        XCTAssertNil(error);

        NSString *authorization = [NSString stringWithFormat:@"DPoP %@", [accessToken encodedToken]];
        NSData * _Nonnull emptyBody = [@"" dataUsingEncoding:NSASCIIStringEncoding];

        // (1) Nonce-less request — expect 401 + DPoP-Nonce challenge.
        HttpRequest *firstRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
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
                                                                    body:emptyBody
                                                            remoteAddress:@"127.0.0.1"];
        HttpResponse *firstResponse = [[HttpResponse alloc] init];
        [dispatcher handleRequest:firstRequest response:firstResponse];

        XCTAssertEqual(firstResponse.statusCode, HttpStatusUnauthorized,
                       @"A nonce-less DPoP proof against requireDPoPNonce=YES must be challenged");
        NSString *challengeNonce = [firstResponse headerForKey:@"DPoP-Nonce"];
        XCTAssertTrue(challengeNonce.length > 0,
                      @"Challenge response must include a DPoP-Nonce header to retry with");
        XCTAssertEqualObjects([firstResponse headerForKey:@"WWW-Authenticate"],
                              @"DPoP error=\"use_dpop_nonce\"",
                              @"Challenge must name the use_dpop_nonce challenge");

        // (2) Retry proof carries the challenge nonce in both the proof JWT and
        // the `dpop-nonce` HTTP header. Both paths are equivalent to the
        // verifier; setting both is defensive across server variants.
        error = nil;
        DPoPToken *retryProof = [DPoPUtil createDPoPForMethod:@"GET"
                                                         uri:dpopURLString
                                                      nonce:challengeNonce
                                                        key:privateKey
                                                      error:&error];
        if ([error.domain isEqualToString:NSOSStatusErrorDomain]) {
            XCTSkip(@"Skipping DPoP nonce retry test: retry proof signing unavailable (%@)", error.localizedDescription);
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
                                                                      @"host": kPDSTestPDSHostHeader,
                                                                      @"dpop": retryProof.jwt,
                                                                      @"dpop-nonce": challengeNonce
                                                                  }
                                                                     body:emptyBody
                                                             remoteAddress:@"127.0.0.1"];
        HttpResponse *secondResponse = [[HttpResponse alloc] init];
        [dispatcher handleRequest:secondRequest response:secondResponse];

        XCTAssertEqual(secondResponse.statusCode, HttpStatusOK,
                       @"A DPoP proof carrying the challenge nonce must be accepted");
        XCTAssertEqualObjects(secondResponse.jsonBody[@"did"], did,
                              @"getSession body's did field must match the account did");
        // Pin the per-response nonce-rotation contract: success nonce differs
        // from the challenge nonce so subsequent requests must re-challenge.
        NSString *successNonce = [secondResponse headerForKey:@"DPoP-Nonce"];
        XCTAssertTrue(successNonce.length > 0,
                      @"Success response must include a fresh DPoP-Nonce header");
        XCTAssertNotEqualObjects(successNonce, challengeNonce,
                                 @"Server must rotate the nonce on every response");
    } @finally {
        if (privateKey) {
            CFRelease(privateKey);
        }
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testImportTamperRejection {
    // importRepo must reject a structurally corrupted CAR payload at the parser, not just an
    // empty body. Send real (non-empty) bytes that are not a valid CAR: the leading byte is
    // read as a CAR varint header length that runs past the buffer, so CARReader rejects it.
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt];
    NSData *tamperedCar = [@"tampered-car-not-a-valid-archive" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *contentLength = [NSString stringWithFormat:@"%lu", (unsigned long)tamperedCar.length];

    HttpResponse *response = [self sendRawRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                 bodyData:tamperedCar
                                                  headers:@{
                                                      @"authorization": authHeader,
                                                      @"Content-Type": @"application/vnd.ipld.car",
                                                      @"Content-Length": contentLength
                                                  }];

    XCTAssertEqual(response.statusCode, 400, @"Tampered CAR payload must be rejected");
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
    NSString *message = response.jsonBody[@"message"];
    XCTAssertNotNil(message);
    // The rejection must come from the CAR parser (past the empty-body guard), so the reason
    // references the CAR header/parse failure rather than "Missing repository body".
    XCTAssertTrue([message.lowercaseString containsString:@"car"],
                  @"Expected a CAR-parse rejection, got: %@", message);
}

- (void)testApplyWritesLimitBypassWithLegacyRecordField {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt];

    // The hard guarantee must hold regardless of which write-field conveys the payload: a write
    // large enough to exceed kPDSApplyWritesMaxRecordBytes (256 KB) must be rejected with 413
    // even when the attacker uses the legacy "record" field instead of the modern "value"
    // field. The validator's value->record fallback ensures both paths share the same bound.
    NSUInteger fieldChars = 270000; // serializes to ~270 KB, comfortably above the 256 KB threshold
    NSMutableString *largeString = [NSMutableString stringWithCapacity:fieldChars];
    for (NSUInteger i = 0; i < fieldChars; i++) {
        [largeString appendString:@"A"];
    }

    NSDictionary *body = @{
        @"repo": self.did,
        @"writes": @[
            @{
                @"$type": @"com.atproto.repo.applyWrites#create",
                @"collection": @"app.bsky.feed.post",
                @"record": @{
                    @"text": largeString
                }
            }
        ]
    };

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                                                      body:body
                                                   headers:@{@"authorization": authHeader}];

    // The size check fires in validateApplyWritesPayload and maps PayloadTooLarge -> 413.
    XCTAssertEqual(response.statusCode, 413, @"Large record in legacy field should be rejected");
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"PayloadTooLarge",
                          @"The rejection must come from the size bound, not lexicon validation");
    NSString *message = response.jsonBody[@"message"];
    XCTAssertTrue([message.lowercaseString containsString:@"large"],
                  @"Expected a size-bound rejection, got: %@", message);
}

- (void)testSyncExportBound {
    // Export is bounded to repositories that actually exist on this PDS. A valid-format DID
    // for an account that was never created must return 404 RepoNotFound rather than an
    // arbitrary body. (The per-repo size bound -- the 100000-record safety cap in
    // PDSRepositoryService -- maps to the same handler's 413 path, but is not reachable from
    // a small fixture.)
    NSString *unknownDid = @"did:plc:zzzzzzzzzzzzzzzzzzzzzzzz"; // valid 24-char base32, never created

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                              queryParams:@{@"did": unknownDid}
                                                  headers:@{}];

    XCTAssertEqual(response.statusCode, 404, @"Export of an unknown repo must be bounded out");
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"RepoNotFound");
}

- (void)testBlobHeaderMIME {
    // Store a real blob, fetch it via sync.getBlob, and verify the response carries the stored
    // MIME type and the anti-sniffing X-Content-Type-Options: nosniff header. The previous
    // version only asserted that a made-up CID did not return 200, which never exercised the
    // serving path.
    NSData *blobData = [@"hardening-blob-header-probe" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *uploadError = nil;
    NSDictionary *uploaded = [self.controller.blobService uploadBlob:blobData
                                                              forDid:self.did
                                                             mimeType:@"text/plain"
                                                               error:&uploadError];
    XCTAssertNotNil(uploaded, @"Blob upload should succeed");
    XCTAssertNil(uploadError);
    NSString *cid = uploaded[@"blob"][@"ref"][@"$link"];
    XCTAssertTrue(cid.length > 0);

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getBlob"
                                              queryParams:@{@"did": self.did, @"cid": cid}
                                                  headers:@{}];

    XCTAssertEqual(response.statusCode, 200, @"Stored blob should be served");
    // contentType is an HttpResponse property populated by the handler, not a setHeader entry.
    NSString *contentType = response.contentType;
    XCTAssertNotNil(contentType);
    XCTAssertTrue([contentType.lowercaseString containsString:@"text/plain"],
                  @"Served Content-Type must reflect the stored MIME, got: %@", contentType);
    XCTAssertEqualObjects([response headerForKey:@"X-Content-Type-Options"], @"nosniff",
                          @"Blob responses must disable MIME sniffing");
}

- (void)testSQLAllowlist {
    // The DID-format allowlist is the guard DatabasePool.dbPathForDid relies on to keep
    // SQL-injection and path-traversal strings out of actor-store path derivation. It must
    // reject any identifier that is not a well-formed DID.
    NSArray<NSString *> *maliciousIdentifiers = @[
        @"did:plc:abc' OR '1'='1",   // SQL injection appended to a DID prefix
        @"did:plc:../../etc/passwd", // path traversal
        @"'; DROP TABLE actors;--",  // raw SQL
        @"did:plc:"                  // malformed plc (wrong length)
    ];
    for (NSString *bad in maliciousIdentifiers) {
        NSError *error = nil;
        BOOL accepted = [ATProtoValidator validateDID:bad error:&error];
        XCTAssertFalse(accepted, @"DID allowlist must reject malicious identifier: %@", bad);
        XCTAssertNotNil(error, @"Rejection must surface an error for: %@", bad);
    }

    // The same guard must be wired into the XRPC layer: a sync export carrying a SQL-injection
    // DID must be rejected with 400 InvalidRequest and never reach the database.
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                              queryParams:@{@"did": @"did:plc:abc' OR '1'='1"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

// Extract the RFC 7638 thumbprint from the public JWK embedded in a signed DPoP
// proof JWT. `DPoPToken.header` returns a placeholder JWK (empty x/y coordinates);
// the real coordinates live in the JWT's signed header. Decoding the header
// directly ensures the access token's `cnf.jkt` claim matches the JWK the auth
// helper's DPoP verifier actually saw — otherwise it rejects the bound token with
// a thumbprint mismatch.
- (NSString *)thumbprintFromDPoPProofJWT:(NSString *)proofJWT error:(NSError **)error {
    NSArray<NSString *> *proofParts = [proofJWT componentsSeparatedByString:@"."];
    NSData *proofHeaderData = [AuthCryptoBase64URL decode:proofParts[0]];
    if (!proofHeaderData) {
        return nil;
    }
    NSDictionary *proofHeaderJSON = [NSJSONSerialization JSONObjectWithData:proofHeaderData
                                                                   options:0
                                                                     error:error];
    if (!proofHeaderJSON) {
        return nil;
    }
    return [AuthCryptoJWK thumbprint:proofHeaderJSON[@"jwk"] error:error];
}

@end
