#import <XCTest/XCTest.h>
#import "Auth/OAuth2.h"
#import "Auth/Session.h"

@interface OAuth2Tests : XCTestCase
@property (nonatomic, strong) OAuth2Server *server;
@end

@implementation OAuth2Tests

- (void)setUp {
    [super setUp];
    self.server = [[OAuth2Server alloc] init];
}

- (void)tearDown {
    self.server = nil;
    [super tearDown];
}

- (void)testRefreshToken {
    // Create a mock session with a refresh token
    Session *session = [[Session alloc] initWithDID:@"did:plc:test"
                                             handle:@"test.bsky.social"
                                              scope:@"atproto"];
    NSLog(@"[DEBUG] Created session: %@", session);
    NSLog(@"[DEBUG] Session ID: %@", session.sessionID);
    NSLog(@"[DEBUG] Active Sessions before: %@", self.server.activeSessions);
    self.server.activeSessions[session.sessionID] = session;
    NSLog(@"[DEBUG] Active Sessions after: %@", self.server.activeSessions);
    
    NSString *refreshToken = session.refreshToken;
    NSLog(@"[DEBUG] Refresh Token: %@", refreshToken);
    XCTAssertNotNil(refreshToken, @"Should have a refresh token");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Refresh token"];
    
    [self.server refreshAccessToken:refreshToken
                              scope:nil
                            dpopJWK:nil
                         completion:^(NSString * _Nullable accessToken, NSError * _Nullable error) {
        NSLog(@"[DEBUG] Refresh completion block called");
        XCTAssertNotNil(accessToken, @"Should return new access token");
        XCTAssertNil(error, @"Should not have error");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testRefreshTokenInvalid {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Refresh token invalid"];
    
    [self.server refreshAccessToken:@"invalid-token"
                              scope:nil
                            dpopJWK:nil
                         completion:^(NSString * _Nullable accessToken, NSError * _Nullable error) {
        XCTAssertNil(accessToken, @"Should not return access token");
        XCTAssertNotNil(error, @"Should have error");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testRefreshTokenRotation {
    Session *session = [[Session alloc] initWithDID:@"did:plc:test"
                                             handle:@"test.bsky.social"
                                              scope:@"atproto"];
    NSString *originalRefreshToken = session.refreshToken;
    XCTAssertNotNil(originalRefreshToken, @"Should have initial refresh token");
    
    self.server.activeSessions[session.sessionID] = session;
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Refresh token rotation"];
    
    [self.server refreshAccessToken:originalRefreshToken
                              scope:nil
                            dpopJWK:nil
                         completion:^(NSString * _Nullable accessToken, NSError * _Nullable error) {
        XCTAssertNotNil(accessToken, @"Should return new access token");
        XCTAssertNil(error, @"Should not have error");
        
        NSString *newRefreshToken = session.refreshToken;
        XCTAssertNotNil(newRefreshToken, @"Should have new refresh token after rotation");
        
        BOOL rotated = ![originalRefreshToken isEqualToString:newRefreshToken];
        XCTAssertTrue(rotated, @"Refresh token should be rotated (new token different from old)");
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end
