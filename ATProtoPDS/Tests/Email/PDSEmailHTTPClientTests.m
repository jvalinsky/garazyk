#import <XCTest/XCTest.h>
#import "Email/PDSEmailHTTPClient.h"

@interface PDSEmailHTTPClientTests : XCTestCase
@end

@implementation PDSEmailHTTPClientTests

- (void)testInit {
    NSURL *baseURL = [NSURL URLWithString:@"https://api.example.com"];
    NSString *apiKey = @"test-api-key";
    
    PDSEmailHTTPClient *client = [[PDSEmailHTTPClient alloc] initWithBaseURL:baseURL apiKey:apiKey];
    
    XCTAssertNotNil(client);
    XCTAssertEqualObjects(client.baseURL, baseURL);
    XCTAssertEqualObjects(client.apiKey, apiKey);
}

- (void)testDefaultValues {
    NSURL *baseURL = [NSURL URLWithString:@"https://api.example.com"];
    NSString *apiKey = @"test-api-key";
    
    PDSEmailHTTPClient *client = [[PDSEmailHTTPClient alloc] initWithBaseURL:baseURL apiKey:apiKey];
    
    XCTAssertEqual(client.timeoutInterval, 30.0);
    XCTAssertEqual(client.maxRetries, 3);
}

- (void)testConfigurableValues {
    NSURL *baseURL = [NSURL URLWithString:@"https://api.example.com"];
    NSString *apiKey = @"test-api-key";
    
    PDSEmailHTTPClient *client = [[PDSEmailHTTPClient alloc] initWithBaseURL:baseURL apiKey:apiKey];
    
    client.timeoutInterval = 60.0;
    client.maxRetries = 5;
    
    XCTAssertEqual(client.timeoutInterval, 60.0);
    XCTAssertEqual(client.maxRetries, 5);
}

@end
