// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"
#import "App/PDSApplication.h"
#import "Network/RateLimiter.h"
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/SubscribeReposHandler.h"

@interface RepoAuthIdentityTests : RepoAuthXrpcTestBase
@end

@implementation RepoAuthIdentityTests

- (void)testIdentityUpdateHandleReturnsStatus401WithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.updateHandle"
                                                      body:@{@"handle": @"repoauth1-renamed.test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testIdentityUpdateHandleUpdatesAccountHandle {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.updateHandle"
                                                      body:@{@"handle": @"repoauth1-renamed.test"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSError *error = nil;
    NSDictionary *account = [self.controller getAccountForDid:self.did1 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(account[@"handle"], @"repoauth1-renamed.test");

    NSDictionary *session = [self.controller loginWithHandle:@"repoauth1-renamed.test" password:@"password" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(session[@"accessJwt"]);
}

- (void)testRefreshIdentityReturnsIdentityInfo {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.refreshIdentity"
                                                      body:@{@"identifier": @"repoauth1.test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"did"], self.did1);
    XCTAssertNotNil(response.jsonBody[@"didDoc"]);
    XCTAssertNotNil(response.jsonBody[@"handle"]);
}

- (void)testIdentitySignAndSubmitPlcOperation {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    HttpResponse *requestSignature = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.requestPlcOperationSignature"
                                                              body:@{}
                                                           headers:@{@"authorization": authHeader}];
    XCTAssertEqual(requestSignature.statusCode, 200);
    NSString *token = requestSignature.jsonBody[@"token"];
    XCTAssertNotNil(token);

    HttpResponse *signResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.signPlcOperation"
                                                          body:@{@"token": token}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(signResponse.statusCode, 200);
    NSDictionary *operation = signResponse.jsonBody[@"operation"];
    XCTAssertNotNil(operation);
    // PLC operations don't include "did" — it's derived from the operation content.
    // Verify the operation contains the required PLC operation fields.
    XCTAssertNotNil(operation[@"sig"], @"Signed PLC operation must include sig");
    XCTAssertNotNil(operation[@"type"], @"Signed PLC operation must include type");
    XCTAssertNotNil(operation[@"rotationKeys"], @"Signed PLC operation must include rotationKeys");
    XCTAssertNotNil(operation[@"verificationMethods"], @"Signed PLC operation must include verificationMethods");
    NSString *sig = operation[@"sig"];
    XCTAssertNotNil(sig);
    XCTAssertFalse([sig containsString:@"="]);
    XCTAssertFalse([sig containsString:@"+"]);
    XCTAssertFalse([sig containsString:@"/"]);

    HttpResponse *submitResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.submitPlcOperation"
                                                            body:@{@"operation": operation}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(submitResponse.statusCode, 200);
}

- (void)testIdentityUpdateHandleUniquenessReturns409 {
    // repoauth2.test is taken by did2
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.updateHandle"
                                                      body:@{@"handle": @"repoauth2.test"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 409);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"HandleAlreadyTaken");
}

- (void)testIdentityUpdateHandleBroadcastsEvent {
    PDSServiceDatabases *db = [self serviceDatabases];
    NSError *error = nil;
    long long initialSeq = [db getMaxEventSequence:&error];
    XCTAssertNil(error);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.updateHandle"
                                                      body:@{@"handle": @"repoauth1-broadcast.test"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    XCTAssertTrue([self.application.subscribeReposHandler waitForIdleWithTimeout:1.0]);
    long long finalSeq = [db getMaxEventSequence:&error];
    
    XCTAssertGreaterThan(finalSeq, initialSeq, @"Sequence number did not increment after handle update");

    // Verify event in database
    NSArray *events = [db getEventsSince:initialSeq limit:10 error:&error];
    XCTAssertNil(error);
    
    EventFormatter *formatter = [[EventFormatter alloc] init];
    BOOL foundIdentityEvent = NO;
    for (NSDictionary *event in events) {
        if ([event[@"type"] isEqualToString:@"identity"]) {
            NSData *eventData = event[@"data"];
            NSInteger op = 0;
            NSString *msgType = nil;
            NSDictionary *payload = [formatter decodeEventFromData:eventData op:&op msgType:&msgType error:&error];
            XCTAssertNotNil(payload, @"Failed to decode identity event data: %@", error);
            
            if ([payload[@"did"] isEqualToString:self.did1] && [payload[@"handle"] isEqualToString:@"repoauth1-broadcast.test"]) {
                foundIdentityEvent = YES;
                break;
            }
        }
    }
    XCTAssertTrue(foundIdentityEvent, @"Identity event not found in firehose sequence");
}

- (void)testIdentityUpdateHandleRateLimiting {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    RateLimiter *limiter = [RateLimiter sharedLimiter];
    BOOL oldGlobalDisabled = RateLimiterIsDisabledGlobally();
    BOOL oldEnabled = limiter.isEnabled;
    NSString *dbPath = [self.tempURL.path stringByAppendingPathComponent:@"identity-rate-limits.sqlite"];
    NSString *shortKey = [NSString stringWithFormat:@"identity.updateHandle:5m:%@", self.did1];

    @try {
        RateLimiterSetDisabledGlobally(NO);
        limiter.enabled = YES;
        [limiter reconfigureDatabasePath:dbPath];

        // Seed the endpoint's limiter directly so the request exercises the
        // rejected XRPC path without performing ten full identity updates.
        for (int i = 0; i < 10; i++) {
            RateLimitResult *seedResult = [limiter checkRateLimitForKey:shortKey
                                                                  limit:10
                                                          windowSeconds:300];
            XCTAssertTrue(seedResult.allowed, @"Seed request %d should be allowed", i);
        }

        HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.updateHandle"
                                                          body:@{@"handle": @"too-many.test"}
                                                       headers:@{@"authorization": authHeader}];
        XCTAssertEqual(response.statusCode, 429, @"Seeded request should be rate limited");
        XCTAssertEqualObjects(response.jsonBody[@"error"], @"RateLimitExceeded");
    } @finally {
        [limiter reconfigureDatabasePath:nil];
        limiter.enabled = oldEnabled;
        RateLimiterSetDisabledGlobally(oldGlobalDisabled);
    }
}

- (void)testIdentityUpdateHandleSameHandleStillBroadcasts {
    PDSServiceDatabases *db = [self serviceDatabases];
    NSError *error = nil;
    
    // 1. Get current handle
    NSDictionary *account = [self.controller getAccountForDid:self.did1 error:&error];
    NSString *currentHandle = account[@"handle"];
    XCTAssertNotNil(currentHandle);
    
    long long initialSeq = [db getMaxEventSequence:&error];
    XCTAssertNil(error);

    // 2. Update to the SAME handle
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.updateHandle"
                                                      body:@{@"handle": currentHandle}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    // 3. Verify event is STILL broadcasted (for sequencing)
    XCTAssertTrue([self.application.subscribeReposHandler waitForIdleWithTimeout:1.0]);
    long long finalSeq = [db getMaxEventSequence:&error];
    
    XCTAssertGreaterThan(finalSeq, initialSeq, @"Sequence number did not increment even for same-handle update");
}

@end
