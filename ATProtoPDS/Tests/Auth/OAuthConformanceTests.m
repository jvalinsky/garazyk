#import <XCTest/XCTest.h>
#import "Auth/OAuth2Handler.h"
#import "Auth/JWT.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"

@interface OAuthConformanceTests : XCTestCase
@property (nonatomic, strong) OAuth2Handler *handler;
@property (nonatomic, strong) JWTMinter *minter;
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation OAuthConformanceTests

- (void)setUp {
    [super setUp];
    
    // Setup in-memory DB
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:@":memory:"]];
    [self.database openWithError:nil];
    
    // Setup Minter with static key for testing
    self.minter = [[JWTMinter alloc] init];
    // We need to set a key pair. Let's generate one using Secp256k1 if available or just use a mock if possible.
    // JWTMinter expects SecKeyRef.
    // For simplicity, we can rely on default empty state or try to set one.
    // If minter has no keys, toJWKS returns empty keys array which is valid but empty.
    
    self.handler = [[OAuth2Handler alloc] initWithDatabase:self.database];
    self.handler.minter = self.minter;
}

- (void)tearDown {
    [self.database close];
    [super tearDown];
}

- (void)testJWKSResponse {
    NSData *emptyBody = [NSData data];
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/oauth/jwks"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{}
                                                          body:emptyBody
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    // We need to invoke the handler logic. 
    // Since handleJWKS is private, we can't call it directly easily without exposing it.
    // However, we can register routes to a mock server or just use performSelector if we want unit test.
    // Or we can simple expose it in a category in the test file.
    
    // Better: integration test style, but we don't have full server running here easily.
    // Let's declare the private method here to access it.
    [self.handler performSelector:@selector(handleJWKS:response:) withObject:request withObject:response];
    
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.body);
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertNotNil(json[@"keys"]);
    XCTAssertTrue([json[@"keys"] isKindOfClass:[NSArray class]]);
    
    // Verify headers
    XCTAssertEqualObjects(response.headers[@"Access-Control-Allow-Origin"], @"*");
}

- (void)testPARResponse {
    // 1. Setup client
    [self.database createClient:@{@"client_id": @"test_client", @"client_secret": @"secret", @"redirect_uris": @[@"https://client.example.com/cb"]} error:nil];
    
    // 2. Prepare PAR request
    NSDictionary *params = @{
        @"client_id": @"test_client",
        @"client_secret": @"secret",
        @"response_type": @"code",
        @"redirect_uri": @"https://client.example.com/cb",
        @"scope": @"atproto",
        @"state": @"xyz"
    };
    
    NSMutableString *body = [NSMutableString string];
    for (NSString *key in params) {
        if (body.length > 0) [body appendString:@"&"];
        [body appendFormat:@"%@=%@", key, params[key]];
    }
    
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:@"/oauth/par"
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"HTTP/1.1"
                                                       headers:@{@"Content-Type": @"application/x-www-form-urlencoded"}
                                                          body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    // Call handlePARRequest
    [self.handler performSelector:@selector(handlePARRequest:response:) withObject:request withObject:response];
    
    XCTAssertEqual(response.statusCode, 201);
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertNotNil(json[@"request_uri"]);
    XCTAssertTrue([json[@"request_uri"] hasPrefix:@"urn:ietf:params:oauth:request_uri:"]);
    XCTAssertNotNil(json[@"expires_in"]);
    XCTAssertEqual([json[@"expires_in"] integerValue], 600);
    
    // Verify it's in DB
    NSArray *rows = [self.database executeQuery:@"SELECT * FROM oauth_par_requests WHERE request_uri = ?" error:nil]; // query needs binding, but executeQuery:error: doesn't support it directly in this interface? 
    // Wait, executeParameterizedQuery is available.
    rows = [self.database executeParameterizedQuery:@"SELECT * FROM oauth_par_requests WHERE request_uri = ?" params:@[json[@"request_uri"]] error:nil];
    XCTAssertEqual(rows.count, 1);
}

@end
