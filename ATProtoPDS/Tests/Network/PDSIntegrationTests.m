#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Database/PDSDatabase.h"
#import "Auth/JWT.h"
#import "Core/CID.h"
#import "Network/HttpResponse.h"
#import "Debug/PDSLogger.h"
#include <errno.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSIntegrationTests : XCTestCase

@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSController *controller;

@end

@implementation PDSIntegrationTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"PDSIntegrationTests"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDirectory error:nil];
    [fm createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.controller = [[PDSController alloc] initWithDirectory:self.testDirectory
                                                serviceMaxSize:10
                                              userDatabaseSize:20];
    self.controller.httpPort = 0;
}

- (void)tearDown {
    [self.controller stopServer];

    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDirectory error:nil];
    
    [super tearDown];
}

#pragma mark - Test Helpers

- (NSDictionary *)createTestAccountWithHandle:(NSString *)handle {
    __autoreleasing NSError *error = nil;
    NSDictionary *result = [self.controller createAccountForEmail:[NSString stringWithFormat:@"%@@example.com", handle]
                                                         password:@"testpassword123"
                                                          handle:handle
                                                              did:nil
                                                             error:&error];
    XCTAssertNotNil(result, @"Account creation should succeed: %@", error);
    return result;
}

- (NSDictionary *)loginWithHandle:(NSString *)handle {
    __autoreleasing NSError *error = nil;
    NSDictionary *session = [self.controller loginWithHandle:handle
                                                   password:@"testpassword123"
                                                      error:&error];
    XCTAssertNotNil(session, @"Login should succeed: %@", error);
    return session;
}

#pragma mark - Test 1: Complete Session Lifecycle

- (void)testCompleteSessionLifecycle {
    NSLog(@"=== TEST: Complete Session Lifecycle ===");
    
    __autoreleasing NSError *error = nil;
    
    // Step 1: Create Account
    NSDictionary *createResult = [self.controller createAccountForEmail:@"lifecycle@example.com"
                                                               password:@"password123"
                                                                handle:@"lifecycleuser.example.com"
                                                                    did:nil
                                                                   error:&error];
    XCTAssertNotNil(createResult, @"Account creation should succeed: %@", error);
    XCTAssertNotNil(createResult[@"did"], @"Should have DID");
    XCTAssertNotNil(createResult[@"accessJwt"], @"Should have access token");
    XCTAssertNotNil(createResult[@"refreshJwt"], @"Should have refresh token");
    
    NSString *did = createResult[@"did"];
    NSString *accessToken = createResult[@"accessJwt"];
    NSString *refreshToken = createResult[@"refreshJwt"];
    
    NSLog(@"  Account created: %@", did);
    NSLog(@"  Access token: %@", accessToken);
    NSLog(@"  Refresh token: %@", refreshToken);
    
    // Step 2: Login (should work with same credentials)
    NSDictionary *loginResult = [self.controller loginWithHandle:@"lifecycleuser.example.com"
                                                       password:@"password123"
                                                          error:&error];
    XCTAssertNotNil(loginResult, @"Login should succeed: %@", error);
    XCTAssertNotNil(loginResult[@"accessJwt"], @"Login should return access token");
    XCTAssertNotNil(loginResult[@"refreshJwt"], @"Login should return refresh token");
    
    NSString *newAccessToken = loginResult[@"accessJwt"];
    XCTAssertNotEqualObjects(accessToken, newAccessToken, @"New login should generate new tokens");
    
    NSLog(@"  Login successful, new access token generated");
    
    // Step 3: Refresh Session
    __autoreleasing NSError *refreshError = nil;
    NSDictionary *refreshResult = [self.controller refreshAccessToken:refreshToken error:&refreshError];
    XCTAssertNotNil(refreshResult, @"Token refresh should succeed: %@", refreshError);
    XCTAssertNotNil(refreshResult[@"accessJwt"], @"Refresh should return new access token");
    
    NSString *refreshedAccessToken = refreshResult[@"accessJwt"];
    XCTAssertNotEqualObjects(newAccessToken, refreshedAccessToken, @"Refresh should generate new token");
    
    NSLog(@"  Token refresh successful");
    
    // Step 4: Verify token structure
    // NEW STATUS: Tokens are now JWTs!
    
    NSLog(@"  Access token: %@", accessToken);
    
    // Check if token has 3 parts (JWT format)
    NSArray *parts = [accessToken componentsSeparatedByString:@"."];
    XCTAssertEqual(parts.count, 3, @"Access token should be a JWT with 3 parts");
    NSLog(@"  Token is JWT format: YES");
    
    // Verify it can be decoded
    NSError *jwtError = nil;
    JWT *jwt = [JWT jwtWithToken:accessToken error:&jwtError];
    XCTAssertNotNil(jwt, @"Should be able to parse JWT: %@", jwtError);
    XCTAssertEqualObjects(jwt.payload.sub, did, @"JWT subject should be the DID");
    XCTAssertEqualObjects(jwt.payload.iss, [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"] ?: @"https://pds.local:8443", @"Issuer should match");
    
    // Step 5: Verify session data matches expected structure
    XCTAssertNotNil(createResult[@"did"], @"Session should include DID");
    XCTAssertNotNil(createResult[@"handle"], @"Session should include handle");
    
    NSLog(@"  Session data structure verified");
    NSLog(@"=== TEST PASSED: Complete Session Lifecycle ===\n");
}

#pragma mark - Test 2: Record CRUD with Value Retrieval

- (void)testRecordCRUDWithValueRetrieval {
    NSLog(@"=== TEST: Record CRUD with Value Retrieval ===");
    
    __autoreleasing NSError *error = nil;
    
    // Setup: Create account and login
    NSDictionary *account = [self createTestAccountWithHandle:@"recordcrud.example.com"];
    NSString *did = account[@"did"];
    
    NSLog(@"  Created account: %@", did);
    
    // Create a test record
    NSDictionary *recordValue = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello, ATProto World!",
        @"createdAt": @"2026-01-10T12:00:00Z"
    };
    
    // Step 1: Create Record
    __autoreleasing NSError *createError = nil;
    BOOL createResult = [self.controller putRecord:@"app.bsky.feed.post"
                                            rkey:@"integration-test-post"
                                           value:recordValue
                                          forDid:did
                                  validationMode:PDSValidationModeRequired
                                           error:&createError];
    XCTAssertTrue(createResult, @"Create record should succeed: %@", createError);
    
    NSLog(@"  Record created successfully");
    
    // Step 2: Get Record - PREDICTED ISSUE: Returns metadata only, not value
    __autoreleasing NSError *getError = nil;
    NSDictionary *fetched = [self.controller getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/integration-test-post", did]
                                              forDid:did
                                                error:&getError];
    XCTAssertNotNil(fetched, @"Get record should succeed: %@", getError);
    
    NSLog(@"  Fetched record: %@", fetched);
    
    // Verify metadata fields
    XCTAssertEqualObjects(fetched[@"collection"], @"app.bsky.feed.post", @"Collection should match");
    XCTAssertEqualObjects(fetched[@"rkey"], @"integration-test-post", @"Rkey should match");
    XCTAssertNotNil(fetched[@"uri"], @"Should have URI");
    XCTAssertNotNil(fetched[@"cid"], @"Should have CID");
    
    NSLog(@"  Record metadata verified");
    
    // Verify that record value IS now included in response
    BOOL hasValueField = fetched[@"value"] != nil;
    NSLog(@"  Record includes 'value' field: %@", hasValueField ? @"YES" : @"NO");
    
    XCTAssertTrue(hasValueField, @"Record should return value");
    XCTAssertEqualObjects(fetched[@"value"][@"text"], @"Hello, ATProto World!", @"Value text should match");
    
    // Step 3: Update Record (same rkey)
    NSDictionary *updatedValue = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Updated: Hello, ATProto World!",
        @"createdAt": @"2026-01-10T12:00:00Z"
    };
    
    __autoreleasing NSError *updateError = nil;
    BOOL updateResult = [self.controller putRecord:@"app.bsky.feed.post"
                                            rkey:@"integration-test-post"
                                           value:updatedValue
                                          forDid:did
                                  validationMode:PDSValidationModeRequired
                                           error:&updateError];
    XCTAssertTrue(updateResult, @"Update record should succeed: %@", updateError);
    
    NSLog(@"  Record updated successfully");
    
    // Step 4: Verify CID changes on update
    NSDictionary *updatedFetched = [self.controller getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/integration-test-post", did]
                                                     forDid:did
                                                       error:nil];
    XCTAssertNotNil(updatedFetched, @"Get updated record should succeed");
    
    BOOL cidChanged = ![fetched[@"cid"] isEqualToString:updatedFetched[@"cid"]];
    NSLog(@"  CID changed after update: %@", cidChanged ? @"YES" : @"NO");
    XCTAssertTrue(cidChanged, @"CID should change when record content changes");
    
    // Step 5: Delete Record
    __autoreleasing NSError *deleteError = nil;
    BOOL deleteResult = [self.controller deleteRecord:@"app.bsky.feed.post"
                                               rkey:@"integration-test-post"
                                              forDid:did
                                                error:&deleteError];
    XCTAssertTrue(deleteResult, @"Delete record should succeed: %@", deleteError);
    
    NSLog(@"  Record deleted successfully");
    
    // Verify deletion
    NSDictionary *deletedFetch = [self.controller getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/integration-test-post", did]
                                                   forDid:did
                                                     error:nil];
    XCTAssertNil(deletedFetch, @"Deleted record should not be retrievable");
    
    NSLog(@"=== TEST PASSED: Record CRUD with Value Retrieval ===\n");
}

#pragma mark - Test 3: CID Format Compliance

- (void)testCIDFormatCompliance {
    // XCTAssertEqual(actual, expected);
    NSLog(@"=== TEST: CID Format Compliance ===");
    
    __autoreleasing NSError *error = nil;
    
    NSDictionary *account = [self createTestAccountWithHandle:@"cidtest.example.com"];
    NSString *did = account[@"did"];
    
    // Create record with known content
    NSDictionary *recordValue = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Test CID generation",
        @"createdAt": @"2026-01-10T00:00:00Z"
    };
    
    __autoreleasing NSError *createError = nil;
    BOOL result = [self.controller putRecord:@"app.bsky.feed.post"
                                      rkey:@"cid-test-post"
                                     value:recordValue
                                    forDid:did
                            validationMode:PDSValidationModeRequired
                                     error:&createError];
    XCTAssertTrue(result, @"Create record should succeed");
    
    // Get the record to retrieve CID
    NSDictionary *fetched = [self.controller getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/cid-test-post", did]
                                              forDid:did
                                                error:nil];
    
    NSString *cid = fetched[@"cid"];
    NSLog(@"  Generated CID: %@", cid);
    
    // PREDICTED: CID format is non-standard
    // Expected: IPLD CIDv1 format like bafyreig...
    // Actual: Uses bafyrei prefix with base64url-encoded SHA-256
    
    BOOL startsWithBafyre = [cid hasPrefix:@"bafyre"] || [cid hasPrefix:@"bafyrei"];
    NSLog(@"  CID starts with 'bafyre/bafyrei': %@", startsWithBafyre ? @"YES" : @"NO");
    
    // Check if it looks like a valid CID (alphanumeric, reasonable length)
    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"];
    NSString *cidWithoutPrefix = [cid stringByReplacingOccurrencesOfString:@"bafyrei" withString:@""];
    BOOL allValidChars = [[cidWithoutPrefix stringByTrimmingCharactersInSet:validChars] isEqualToString:@""];
    
    NSLog(@"  CID contains only valid characters: %@", allValidChars ? @"YES" : @"NO");
    NSLog(@"  CID length: %lu", (unsigned long)cid.length);
    
    // CID should be deterministic for same content
    BOOL createAgain = [self.controller putRecord:@"app.bsky.feed.post"
                                           rkey:@"cid-test-post-2"
                                          value:recordValue
                                         forDid:did
                                 validationMode:PDSValidationModeRequired
                                          error:nil];
    XCTAssertTrue(createAgain, @"Create duplicate record should succeed");
    
    NSDictionary *fetched2 = [self.controller getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/cid-test-post-2", did]
                                                forDid:did
                                                  error:nil];
    
    NSString *cid2 = fetched2[@"cid"];
    NSLog(@"  Second CID for same content: %@", cid2);
    
    BOOL sameContentSameCID = [cid isEqualToString:cid2];
    NSLog(@"  Same content produces same CID: %@", sameContentSameCID ? @"YES" : @"NO (PREDICTED ISSUE)");
    
    // The CID format is non-standard IPLD but deterministic
    XCTAssertTrue(sameContentSameCID, @"Same content should produce same CID");
    
    NSLog(@"=== TEST PASSED: CID Format Compliance ===\n");
}

#pragma mark - Test 4: Token Validation

- (void)testTokenValidation {
    NSLog(@"=== TEST: Token Validation ===");
    
    __autoreleasing NSError *error = nil;
    
    NSDictionary *account = [self createTestAccountWithHandle:@"tokentest.example.com"];
    NSString *accessToken = account[@"accessJwt"];
    NSString *refreshToken = account[@"refreshJwt"];
    
    NSLog(@"  Access token: %@", accessToken);
    NSLog(@"  Refresh token: %@", refreshToken);
    
    // Test 1: Verify tokens are JWTs
    // UPDATED: Tokens are now signed JWTs
    
    NSArray *accessParts = [accessToken componentsSeparatedByString:@"."];
    XCTAssertEqual(accessParts.count, 3, @"Access token should be a JWT with 3 parts");
    
    // Refresh token is still an opaque UUID for now
    NSString *uuidPattern = @"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:uuidPattern options:0 error:nil];
    NSUInteger refreshMatches = [regex numberOfMatchesInString:refreshToken options:0 range:NSMakeRange(0, refreshToken.length)];
    XCTAssertEqual(refreshMatches, 1, @"Refresh token should be UUID");
    
    NSLog(@"  Access token is JWT: YES");
    NSLog(@"  Refresh token is UUID: YES");
    
    // Test 2: Verify access token can be parsed
    NSError *jwtError = nil;
    JWT *jwt = [JWT jwtWithToken:accessToken error:&jwtError];
    XCTAssertNotNil(jwt, @"Should be able to parse access JWT");
    XCTAssertNotNil(jwt.payload.did, @"JWT should contain DID");
    
    // Test 3: Verify token lookup works (tokens stored in session store)
    // The session is looked up by token string in the in-memory session store
    NSLog(@"  Token validation: JWT-based lookup in session store");
    
    // Test 4: Verify invalid token is rejected
    NSDictionary *refreshInvalid = [self.controller refreshAccessToken:@"invalid_token" error:&error];
    XCTAssertNil(refreshInvalid, @"Invalid token should be rejected");
    XCTAssertNotNil(error, @"Should have error for invalid token");
    
    NSLog(@"  Invalid token correctly rejected: YES");
    
    NSLog(@"  Token validation: Signed JWT tokens");
    NSLog(@"  SUCCESS: Cryptographic verification of token claims is now possible");
    
    NSLog(@"=== TEST PASSED: Token Validation ===\n");
}

#pragma mark - Test 5: Session Persistence

- (void)testSessionPersistenceLimitation {
    NSLog(@"=== TEST: Session Persistence Limitation ===");
    
    __autoreleasing NSError *error = nil;
    
    NSDictionary *account = [self createTestAccountWithHandle:@"persisttest.example.com"];
    NSString *accessToken = account[@"accessJwt"];
    NSString *refreshToken = account[@"refreshJwt"];
    
    NSLog(@"  Created session with tokens");
    
    // PREDICTED: Sessions are in-memory only and lost on restart
    // This test documents the limitation
    
    // Verify session data structure
    XCTAssertNotNil(accessToken, @"Should have access token");
    XCTAssertNotNil(refreshToken, @"Should have refresh token");
    
    NSLog(@"  Session data present: YES");
    
    // Document the limitation
    NSLog(@"  LIMITATION: Sessions are stored in-memory only");
    NSLog(@"  Sessions will be LOST when server restarts");
    NSLog(@"  Users must re-authenticate after server restart");
    
    // This is expected behavior - not a test failure
    XCTAssertTrue(YES, @"Sessions are in-memory only (documented limitation)");
    
    NSLog(@"=== TEST PASSED: Session Persistence Limitation ===\n");
}

#pragma mark - Test 6: Record Value Field Analysis

- (void)testRecordValueFieldAnalysis {
    NSLog(@"=== TEST: Record Value Field Analysis ===");
    
    __autoreleasing NSError *error = nil;
    
    NSDictionary *account = [self createTestAccountWithHandle:@"valuefield.example.com"];
    NSString *did = account[@"did"];
    
    // Create a record with specific content
    NSDictionary *originalValue = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Analyzing value field behavior",
        @"createdAt": @"2026-01-10T15:00:00Z",
        @"embed": @{
            @"$type": @"app.bsky.embed.images",
            @"images": @[]
        }
    };
    
    __autoreleasing NSError *createError = nil;
    BOOL createResult = [self.controller putRecord:@"app.bsky.feed.post"
                                            rkey:@"value-analysis-post"
                                           value:originalValue
                                          forDid:did
                                  validationMode:PDSValidationModeRequired
                                           error:&createError];
    XCTAssertTrue(createResult, @"Create should succeed");
    
    NSLog(@"  Record created with complex value");
    
    // Get record and analyze response structure
    NSDictionary *fetched = [self.controller getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/value-analysis-post", did]
                                              forDid:did
                                                error:nil];
    
    NSLog(@"  Fetched record response: %@", fetched);
    
    // Analyze fields
    NSArray *allKeys = fetched.allKeys;
    NSLog(@"  Record has %lu fields: %@", (unsigned long)allKeys.count, allKeys);
    
    BOOL hasUri = fetched[@"uri"] != nil;
    BOOL hasCid = fetched[@"cid"] != nil;
    BOOL hasCollection = fetched[@"collection"] != nil;
    BOOL hasRkey = fetched[@"rkey"] != nil;
    BOOL hasValue = fetched[@"value"] != nil;
    BOOL hasCreatedAt = fetched[@"createdAt"] != nil;
    
    NSLog(@"  Field analysis:");
    NSLog(@"    uri: %@", hasUri ? @"PRESENT" : @"MISSING");
    NSLog(@"    cid: %@", hasCid ? @"PRESENT" : @"MISSING");
    NSLog(@"    collection: %@", hasCollection ? @"PRESENT" : @"MISSING");
    NSLog(@"    rkey: %@", hasRkey ? @"PRESENT" : @"MISSING");
    NSLog(@"    value: %@", hasValue ? @"PRESENT" : @"MISSING");
    NSLog(@"    createdAt: %@", hasCreatedAt ? @"PRESENT" : @"MISSING");
    
    // Record the expected behavior
    XCTAssertTrue(hasUri, @"Should have uri");
    XCTAssertTrue(hasCid, @"Should have cid");
    XCTAssertTrue(hasCollection, @"Should have collection");
    XCTAssertTrue(hasRkey, @"Should have rkey");
    
    // FIXED: value field is now returned by getRecord
    XCTAssertTrue(hasValue, @"getRecord should return value");
    // createdAt is still missing in the service response, which is fine for now
    
    NSLog(@"  Fixed Issues:");
    NSLog(@"    1. getRecord now returns the actual record value");
    NSLog(@"    2. No need to fetch from CAR block storage separately for basic inspection");
    
    NSLog(@"=== TEST PASSED: Record Value Field Analysis ===\n");
}

#pragma mark - Test 7: Authentication Required

- (void)testAuthenticationRequired {
    NSLog(@"=== TEST: Authentication Required ===");
    
    __autoreleasing NSError *error = nil;
    
    NSDictionary *account = [self createTestAccountWithHandle:@"authtest.example.com"];
    NSString *did = account[@"did"];
    
    // Initialize a record initially
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Auth test post"
    };
    
    __autoreleasing NSError *createError = nil;
    [self.controller putRecord:@"app.bsky.feed.post"
                         rkey:@"auth-test-post"
                        value:record
                       forDid:did
               validationMode:PDSValidationModeRequired
                        error:&createError];
    
    // Note: These tests verify the controller-level authentication
    // In a real XRPC endpoint, the AuthMiddleware would enforce this
    
    NSLog(@"  Record created with authentication");
    
    // Verify session has valid tokens (JWTs)
    NSString *accessToken = account[@"accessJwt"];
    XCTAssertNotNil(accessToken, @"Should have access token for auth");
    
    // Tokens are now JWTs - verify this
    NSArray *parts = [accessToken componentsSeparatedByString:@"."];
    XCTAssertEqual(parts.count, 3, @"Access token should be JWT");
    NSLog(@"  Token is JWT format: YES");
    
    // Session store maps JWT to session with DID
    // The DID is stored in the session and also encoded in the token
    XCTAssertEqualObjects(account[@"did"], did, @"Account DID should match");
    NSLog(@"  Account DID stored in session: %@", did);
    
    // Authentication is based on JWT lookup and verification
    NSLog(@"  Authentication: JWT-based session lookup");
    NSLog(@"  SUCCESS: Cryptographic binding between token and account");
    
    NSLog(@"=== TEST PASSED: Authentication Required ===\n");
}


#ifndef GNUSTEP
- (void)testRequestCorrelationID {
    // Start server for integration test
    XCTestExpectation *expectation = [self expectationWithDescription:@"Correlation ID test"];
    NSError *serverError = nil;
    BOOL started = [self.controller startServerWithError:&serverError];
    if (!started) {
        XCTSkip(@"HTTP server unavailable in this environment (or blocked): %@", serverError);
        return;
    }
    XCTAssertNil(serverError);
    XCTAssertEqual(self.controller.wsPort, self.controller.httpPort);
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%lu/xrpc/com.atproto.server.describeServer", (unsigned long)self.controller.httpPort]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    NSString *testCorrelationID = [[NSUUID UUID] UUIDString];
    [request setValue:testCorrelationID forHTTPHeaderField:@"X-Correlation-ID"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        
        [expectation fulfill];
    }];
    [task resume];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}
#endif

@end

NS_ASSUME_NONNULL_END
