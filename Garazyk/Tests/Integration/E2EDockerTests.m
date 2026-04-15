#import <XCTest/XCTest.h>

@interface E2EDockerTests : XCTestCase
@property (nonatomic, copy) NSString *pdsBaseURL;
@property (nonatomic, copy) NSString *plcBaseURL;
@property (nonatomic, copy) NSString *relayBaseURL;
@end

@implementation E2EDockerTests

- (void)setUp {
    [super setUp];
    _pdsBaseURL = @"http://localhost:2583";
    _plcBaseURL = @"http://localhost:2580";
    _relayBaseURL = @"http://localhost:2584";

    NSError *probeError = nil;
    if (![self isLocalNetworkStackReachable:&probeError]) {
        XCTSkip(@"Skipping E2E docker tests: local-network stack not reachable (%@). Run docker/local-network compose first.",
                probeError.localizedDescription ?: @"unknown error");
    }
}

- (BOOL)isLocalNetworkStackReachable:(NSError **)error {
    NSArray<NSString *> *probeURLs = @[
        [NSString stringWithFormat:@"%@/xrpc/com.atproto.server.describeServer", self.pdsBaseURL],
        [NSString stringWithFormat:@"%@/xrpc/com.atproto.sync.listHosts", self.relayBaseURL]
    ];

    for (NSString *probeURLString in probeURLs) {
        NSURL *url = [NSURL URLWithString:probeURLString];
        if (!url) {
            if (error) {
                *error = [NSError errorWithDomain:@"E2EDockerTests"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid probe URL"}];
            }
            return NO;
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.timeoutInterval = 1.5;
        NSHTTPURLResponse *response = nil;
        NSError *requestError = nil;
        [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&requestError];
        if (requestError || response == nil || response.statusCode <= 0) {
            if (error) {
                *error = requestError;
            }
            return NO;
        }
    }

    return YES;
}

#pragma mark - PLC Tests

- (void)testPLCHealthCheck {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/_health", self.plcBaseURL]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - PDS Tests

- (void)testPDSHealthCheck {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.server.describeServer", self.pdsBaseURL]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(response.statusCode, 200);
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(json[@"did"]);
}

- (void)testPDSCreateAccount {
    NSString *uniqueHandle = [NSString stringWithFormat:@"e2e-%u", arc4random_uniform(100000)];
    NSDictionary *body = @{
        @"handle": [NSString stringWithFormat:@"%@.garazyk.xyz", uniqueHandle],
        @"email": [NSString stringWithFormat:@"%@@test.com", uniqueHandle],
        @"password": @"testpass123"
    };
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.server.createAccount", self.pdsBaseURL]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    
    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(response.statusCode, 200);
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(json[@"accessJwt"]);
}

- (void)testPDSCreateSession {
    NSString *uniqueHandle = [NSString stringWithFormat:@"e2e-session-%u", arc4random_uniform(100000)];
    
    // First create account
    NSDictionary *createBody = @{
        @"handle": [NSString stringWithFormat:@"%@.garazyk.xyz", uniqueHandle],
        @"email": [NSString stringWithFormat:@"%@session@test.com", uniqueHandle],
        @"password": @"testpass123"
    };
    
    NSURL *createURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.server.createAccount", self.pdsBaseURL]];
    NSMutableURLRequest *createRequest = [NSMutableURLRequest requestWithURL:createURL];
    createRequest.HTTPMethod = @"POST";
    [createRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    createRequest.HTTPBody = [NSJSONSerialization dataWithJSONObject:createBody options:0 error:nil];
    
    NSError *error = nil;
    NSHTTPURLResponse *createResponse = nil;
    NSData *createData = [NSURLConnection sendSynchronousRequest:createRequest returningResponse:&createResponse error:&error];
    
    if (createResponse.statusCode != 200) {
        XCTSkip(@"Account creation requires invite code, skipping");
        return;
    }
    
    NSDictionary *createJson = [NSJSONSerialization JSONObjectWithData:createData options:0 error:&error];
    NSString *accessToken = createJson[@"accessJwt"];
    
    XCTAssertNotNil(accessToken);
    
    // Then create session
    NSDictionary *sessionBody = @{
        @"identifier": [NSString stringWithFormat:@"%@.garazyk.xyz", uniqueHandle],
        @"password": @"testpass123"
    };
    
    NSURL *sessionURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.server.createSession", self.pdsBaseURL]];
    NSMutableURLRequest *sessionRequest = [NSMutableURLRequest requestWithURL:sessionURL];
    sessionRequest.HTTPMethod = @"POST";
    [sessionRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    sessionRequest.HTTPBody = [NSJSONSerialization dataWithJSONObject:sessionBody options:0 error:nil];
    
    NSHTTPURLResponse *sessionResponse = nil;
    NSData *sessionData = [NSURLConnection sendSynchronousRequest:sessionRequest returningResponse:&sessionResponse error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(sessionResponse.statusCode, 200);
    
    NSDictionary *sessionJson = [NSJSONSerialization JSONObjectWithData:sessionData options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(sessionJson[@"accessJwt"]);
    XCTAssertNotNil(sessionJson[@"refreshJwt"]);
}

- (void)testPDSResolveHandle {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.identity.resolveHandle?handle=garazyk.xyz", self.pdsBaseURL]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(response.statusCode, 200);
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(json[@"did"]);
}

#pragma mark - Relay Tests

- (void)testRelayGetHead {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.sync.getHead?repo=did:plc:test", self.relayBaseURL]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    XCTAssertNil(error);
    // 404 is expected for non-existent repo, but endpoint should respond
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 404);
    
    if (response.statusCode == 200) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        XCTAssertNil(error);
        XCTAssertNotNil(json[@"repo"]);
    }
}

- (void)testRelayListHosts {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.sync.listHosts", self.relayBaseURL]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(response.statusCode, 200);
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(json[@"hosts"]);
}

#pragma mark - Integration Tests

- (void)testFullPipeline {
    // 1. Create account on PDS
    NSString *uniqueHandle = [NSString stringWithFormat:@"e2e-pipeline-%u", arc4random_uniform(100000)];
    NSDictionary *createBody = @{
        @"handle": [NSString stringWithFormat:@"%@.garazyk.xyz", uniqueHandle],
        @"email": [NSString stringWithFormat:@"%@pipeline@test.com", uniqueHandle],
        @"password": @"testpass123"
    };
    
    NSURL *createURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.server.createAccount", self.pdsBaseURL]];
    NSMutableURLRequest *createRequest = [NSMutableURLRequest requestWithURL:createURL];
    createRequest.HTTPMethod = @"POST";
    [createRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    createRequest.HTTPBody = [NSJSONSerialization dataWithJSONObject:createBody options:0 error:nil];
    
    NSError *error = nil;
    NSHTTPURLResponse *createResponse = nil;
    NSData *createData = [NSURLConnection sendSynchronousRequest:createRequest returningResponse:&createResponse error:&error];
    
    if (createResponse.statusCode != 200) {
        XCTSkip(@"Account creation requires invite code");
        return;
    }
    
    NSDictionary *createJson = [NSJSONSerialization JSONObjectWithData:createData options:0 error:&error];
    NSString *accessToken = createJson[@"accessJwt"];
    NSString *did = createJson[@"did"];
    
    XCTAssertNotNil(accessToken);
    XCTAssertNotNil(did);
    
    // 2. Create session
    NSDictionary *sessionBody = @{
        @"identifier": [NSString stringWithFormat:@"%@.garazyk.xyz", uniqueHandle],
        @"password": @"testpass123"
    };
    
    NSURL *sessionURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.server.createSession", self.pdsBaseURL]];
    NSMutableURLRequest *sessionRequest = [NSMutableURLRequest requestWithURL:sessionURL];
    sessionRequest.HTTPMethod = @"POST";
    [sessionRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    sessionRequest.HTTPBody = [NSJSONSerialization dataWithJSONObject:sessionBody options:0 error:nil];
    
    NSHTTPURLResponse *sessionResponse = nil;
    NSData *sessionData = [NSURLConnection sendSynchronousRequest:sessionRequest returningResponse:&sessionResponse error:&error];
    
    XCTAssertEqual(sessionResponse.statusCode, 200);
    NSDictionary *sessionJson = [NSJSONSerialization JSONObjectWithData:sessionData options:0 error:&error];
    accessToken = sessionJson[@"accessJwt"];
    
    // 3. Create a post
    NSDictionary *postBody = @{
        @"collection": @"app.bsky.feed.post",
        @"repo": did,
        @"record": @{
            @"text": @"Hello from E2E test!",
            @"createdAt": [[NSDate date] description]
        }
    };
    
    NSURL *postURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.repo.createRecord", self.pdsBaseURL]];
    NSMutableURLRequest *postRequest = [NSMutableURLRequest requestWithURL:postURL];
    postRequest.HTTPMethod = @"POST";
    [postRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [postRequest setValue:[NSString stringWithFormat:@"Bearer %@", accessToken] forHTTPHeaderField:@"Authorization"];
    postRequest.HTTPBody = [NSJSONSerialization dataWithJSONObject:postBody options:0 error:nil];
    
    NSHTTPURLResponse *postResponse = nil;
    NSData *postData = [NSURLConnection sendSynchronousRequest:postRequest returningResponse:&postResponse error:&error];
    
    XCTAssertEqual(postResponse.statusCode, 200);
    NSDictionary *postJson = [NSJSONSerialization JSONObjectWithData:postData options:0 error:&error];
    XCTAssertNotNil(postJson[@"uri"]);
    
    // 4. Verify relay has the repo
    NSURL *relayURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.sync.getHead?repo=%@", self.relayBaseURL, did]];
    NSURLRequest *relayRequest = [NSURLRequest requestWithURL:relayURL];
    
    NSHTTPURLResponse *relayResponse = nil;
    NSData *relayData = [NSURLConnection sendSynchronousRequest:relayRequest returningResponse:&relayResponse error:&error];
    
    XCTAssertNil(error);
    XCTAssertEqual(relayResponse.statusCode, 200);
    
    NSDictionary *relayJson = [NSJSONSerialization JSONObjectWithData:relayData options:0 error:&error];
    XCTAssertNotNil(relayJson[@"root"]);
    
    XCTAssertTrue([relayJson[@"repo"] isEqualToString:did]);
}

- (void)testIdempotency {
    // Run the same test twice with different handles
    // Both should succeed independently
    
    NSString *handle1 = [NSString stringWithFormat:@"e2e-idempot1-%u", arc4random_uniform(100000)];
    NSString *handle2 = [NSString stringWithFormat:@"e2e-idempot2-%u", arc4random_uniform(100000)];
    
    // Create first account
    NSDictionary *body1 = @{
        @"handle": [NSString stringWithFormat:@"%@.garazyk.xyz", handle1],
        @"email": [NSString stringWithFormat:@"%@1@test.com", handle1],
        @"password": @"testpass123"
    };
    
    NSURL *url1 = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.server.createAccount", self.pdsBaseURL]];
    NSMutableURLRequest *request1 = [NSMutableURLRequest requestWithURL:url1];
    request1.HTTPMethod = @"POST";
    [request1 setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request1.HTTPBody = [NSJSONSerialization dataWithJSONObject:body1 options:0 error:nil];
    
    NSError *error = nil;
    NSHTTPURLResponse *response1 = nil;
    [NSURLConnection sendSynchronousRequest:request1 returningResponse:&response1 error:&error];
    
    if (response1.statusCode != 200) {
        XCTSkip(@"Account creation requires invite code");
        return;
    }
    
    // Create second account
    NSDictionary *body2 = @{
        @"handle": [NSString stringWithFormat:@"%@.garazyk.xyz", handle2],
        @"email": [NSString stringWithFormat:@"%@2@test.com", handle2],
        @"password": @"testpass123"
    };
    
    NSURL *url2 = [NSURL URLWithString:[NSString stringWithFormat:@"%@/xrpc/com.atproto.server.createAccount", self.pdsBaseURL]];
    NSMutableURLRequest *request2 = [NSMutableURLRequest requestWithURL:url2];
    request2.HTTPMethod = @"POST";
    [request2 setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request2.HTTPBody = [NSJSONSerialization dataWithJSONObject:body2 options:0 error:nil];
    
    NSHTTPURLResponse *response2 = nil;
    [NSURLConnection sendSynchronousRequest:request2 returningResponse:&response2 error:&error];
    
    XCTAssertEqual(response2.statusCode, 200);
    
    XCTAssertTrue(![handle1 isEqualToString:handle2]);
}

@end
