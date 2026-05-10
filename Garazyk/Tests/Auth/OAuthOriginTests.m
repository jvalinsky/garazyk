#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "Network/HttpRequest.h"

// Category to expose private method for testing
@interface OAuth2Handler (Test)
- (NSString *)requestOriginForRequest:(HttpRequest *)request;
@end

@interface OAuthOriginTests : XCTestCase
@end

@implementation OAuthOriginTests

- (void)testRequestOriginForRequest {
    // This requires a real or mock OAuth2Handler and HttpRequest.
    // Since we're in a unit test, we'll try to verify the logic.
}

@end
