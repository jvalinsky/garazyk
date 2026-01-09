#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface OAuth2HandlerTests : XCTestCase
@property (nonatomic, strong) OAuth2Handler *handler;
@end

@implementation OAuth2HandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [[OAuth2Handler alloc] init];
}

- (void)tearDown {
    self.handler = nil;
    [super tearDown];
}

- (void)testTokenRequestRejectsInvalidClientSecret {
    // Setup request with valid client_id but wrong client_secret
    NSString *body = @"grant_type=authorization_code&code=valid&client_id=test-client&client_secret=wrong";
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/token"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    // Execute handler
    [self.handler handleTokenRequest:request response:response];
    
    // Assert 401 Unauthorized
    XCTAssertEqual(response.statusCode, 401, @"Should return 401 for invalid client secret");
}

@end
