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
    self.server.activeSessions[session.sessionID] = session;
    
    NSString *refreshToken = session.refreshToken;
    XCTAssertNotNil(refreshToken, @"Should have a refresh token");
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Refresh token"];
    
    [self.server refreshAccessToken:refreshToken
                              scope:nil
                            dpopJWK:nil
                         completion:^(NSString * _Nullable accessToken, NSError * _Nullable error) {
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

@end
