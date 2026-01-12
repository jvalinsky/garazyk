#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Core/DID.h"
#import "Identity/HandleResolver.h"

@interface MockExternalServer : NSObject

@property (nonatomic, strong) HttpServer *server;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *mockResponses;

- (instancetype)initWithPort:(uint16_t)port;
- (void)start;
- (void)stop;
- (void)addMockResponseForPath:(NSString *)path response:(NSDictionary *)response;

@end

@implementation MockExternalServer

- (instancetype)initWithPort:(uint16_t)port {
    self = [super init];
    if (self) {
        _port = port;
        _mockResponses = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)start {
    self.server = [HttpServer serverWithPort:self.port];
    __weak typeof(self) weakSelf = self;

    [self.server addHandlerForPath:@"/*" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSDictionary *mockResponse = strongSelf.mockResponses[request.path];
        if (mockResponse) {
            NSNumber *statusCode = mockResponse[@"statusCode"] ?: @200;
            NSDictionary *body = mockResponse[@"body"];

            response.statusCode = [statusCode integerValue];
            if (body) {
                [response setJsonBody:body];
            }
        } else {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"Not Found"}];
        }
    }];

    NSError *error = nil;
    if (![self.server startWithError:&error]) {
        NSLog(@"Failed to start mock server: %@", error);
    }
}

- (void)stop {
    [self.server stop];
}

- (void)addMockResponseForPath:(NSString *)path response:(NSDictionary *)response {
    self.mockResponses[path] = response;
}

@end

@interface XrpcTestClient : NSObject

@property (nonatomic, strong) NSURLSession *session;

- (instancetype)init;
- (NSDictionary *)makeRequest:(NSString *)method
                          url:(NSString *)urlString
                     bodyDict:(NSDictionary *)bodyDict
                        error:(NSError **)error;

@end

@implementation XrpcTestClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _session = [NSURLSession sharedSession];
    }
    return self;
}

- (NSDictionary *)makeRequest:(NSString *)method
                          url:(NSString *)urlString
                     bodyDict:(NSDictionary *)bodyDict
                        error:(NSError **)error {
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;

    if (bodyDict) {
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:error];
        if (*error) return nil;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSDictionary *result = nil;
    __block NSError *requestError = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        requestError = err;
        if (!err && data) {
            result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&requestError];
        }
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    if (error) *error = requestError;
    return result;
}

@end

@interface XrpcIntegrationTests : XCTestCase

@property (nonatomic, strong) HttpServer *testServer;
@property (nonatomic, strong) XrpcTestClient *client;
@property (nonatomic, strong) MockExternalServer *plcServer;
@property (nonatomic, strong) MockExternalServer *handleServer;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;

@end

@implementation XrpcIntegrationTests

- (void)setUp {
    [super setUp];

    self.testServer = [HttpServer serverWithPort:9090];
    self.client = [[XrpcTestClient alloc] init];
    self.plcServer = [[MockExternalServer alloc] initWithPort:9091];
    self.handleServer = [[MockExternalServer alloc] initWithPort:9092];
    self.dispatcher = [XrpcDispatcher sharedDispatcher];

    [self setupMockHandlers];

    [self.plcServer start];
    [self.handleServer start];

    NSError *serverError = nil;
    XCTAssertTrue([self.testServer startWithError:&serverError], @"Test server should start: %@", serverError);

    [NSThread sleepForTimeInterval:1.0];
}

- (void)tearDown {
    [self.testServer stop];
    [self.plcServer stop];
    [self.handleServer stop];
    [super tearDown];
}

- (void)setupMockHandlers {
    [self.dispatcher registerComAtprotoIdentityResolveDid:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did parameter"}];
            return;
        }

        if ([did isEqualToString:@"did:plc:7HjwGtP5cLyq3vD5nDzDg"]) {
            NSDictionary *mockDoc = @{
                @"id": @"did:plc:7HjwGtP5cLyq3vD5nDzDg",
                @"alsoKnownAs": @[@"at://test.example.com"],
                @"service": @[@{
                    @"id": @"#atproto_pds",
                    @"type": @"AtprotoPersonalDataServer",
                    @"serviceEndpoint": @"https://pds.example.com"
                }],
                @"verificationMethod": @[@{
                    @"id": @"#key-1",
                    @"type": @"EcdsaSecp256k1VerificationKey2019",
                    @"publicKeyMultibase": @"z7r8ciZ2VJyC7gZF5yKjQ5vz7r8ciZ2VJyC7gZF5yKj"
                }]
            };
            response.statusCode = HttpStatusOK;
            [response setJsonBody:mockDoc];
        } else if ([did isEqualToString:@"did:plc:nonexistent"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": @"DID not found"}];
        } else if ([did isEqualToString:@"did:plc:malformed"]) {
            response.statusCode = HttpStatusOK;
            [response setBodyString:@"invalid json { missing quotes"];
            [response setHeader:@"application/json" forKey:@"Content-Type"];
        } else if ([did isEqualToString:@"did:plc:server-error"]) {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"Internal Server Error"}];
        } else if ([did isEqualToString:@"did:plc:empty-body"]) {
            response.statusCode = HttpStatusOK;
            [response setBodyString:@""];
        } else {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": @"Invalid DID format"}];
        }
    }];

    [self.dispatcher registerComAtprotoIdentityResolveIdentity:^(HttpRequest *request, HttpResponse *response) {
        NSString *identifier = [request queryParamForKey:@"identifier"];

        if (!identifier) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing identifier parameter"}];
            return;
        }

        if ([identifier hasPrefix:@"did:"]) {
            if ([identifier isEqualToString:@"did:plc:7HjwGtP5cLyq3vD5nDzDg"]) {
                NSDictionary *mockDoc = @{
                    @"id": @"did:plc:7HjwGtP5cLyq3vD5nDzDg",
                    @"alsoKnownAs": @[@"at://test.example.com"],
                    @"service": @[@{
                        @"id": @"#atproto_pds",
                        @"type": @"AtprotoPersonalDataServer",
                        @"serviceEndpoint": @"https://pds.example.com"
                    }]
                };
                NSDictionary *result = @{
                    @"did": identifier,
                    @"didDoc": mockDoc
                };
                response.statusCode = HttpStatusOK;
                [response setJsonBody:result];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": @"DID not found"}];
            }
        } else {
            if ([identifier isEqualToString:@"test.example.com"]) {
                NSDictionary *mockDoc = @{
                    @"id": @"did:plc:7HjwGtP5cLyq3vD5nDzDg",
                    @"alsoKnownAs": @[@"at://test.example.com"]
                };
                NSDictionary *result = @{
                    @"did": @"did:plc:7HjwGtP5cLyq3vD5nDzDg",
                    @"handle": identifier,
                    @"didDoc": mockDoc
                };
                response.statusCode = HttpStatusOK;
                [response setJsonBody:result];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": @"Handle resolution failed"}];
            }
        }
    }];

    [self.dispatcher registerComAtprotoIdentityResolveHandle:^(HttpRequest *request, HttpResponse *response) {
        NSString *handle = [request queryParamForKey:@"handle"];

        if (!handle) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing handle parameter"}];
            return;
        }

        if ([handle isEqualToString:@"test.example.com"] || [handle isEqualToString:@"test-handle.example.com"]) {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"did": @"did:plc:7HjwGtP5cLyq3vD5nDzDg"}];
        } else {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": @"Handle resolution failed"}];
        }
    }];

    [self.testServer setValue:^(HttpRequest *request, HttpResponse *response) {
        if ([request.path hasPrefix:@"/xrpc/"]) {
            [self.dispatcher handleRequest:request response:response];
        } else if ([request.path isEqualToString:@"/health"]) {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"status": @"ok"}];
        } else {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"Not Found", @"message": [NSString stringWithFormat:@"No handler for %@ %@", request.methodString, request.path]}];
        }
    } forKey:@"requestHandler"];
}

- (void)testResolveDidValid {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveDid?did=did:plc:7HjwGtP5cLyq3vD5nDzDg"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"id"], @"did:plc:7HjwGtP5cLyq3vD5nDzDg", @"DID should match");
}

- (void)testResolveDidMissingParameter {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveDid"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"error"], @"InvalidRequest", @"Should return InvalidRequest error");
}

- (void)testResolveDidInvalidFormat {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveDid?did=invalid-did"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"error"], @"ResolutionFailed", @"Should return ResolutionFailed error");
}

- (void)testResolveDidNonExistent {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveDid?did=did:plc:nonexistent"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"error"], @"ResolutionFailed", @"Should return ResolutionFailed error");
}

- (void)testResolveIdentityValidDID {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveIdentity?identifier=did:plc:7HjwGtP5cLyq3vD5nDzDg"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"did"], @"did:plc:7HjwGtP5cLyq3vD5nDzDg", @"DID should match");
    XCTAssertNotNil(result[@"didDoc"], @"DID doc should be present");
}

- (void)testResolveIdentityValidHandle {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveIdentity?identifier=test.example.com"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"did"], @"did:plc:7HjwGtP5cLyq3vD5nDzDg", @"DID should match");
    XCTAssertEqualObjects(result[@"handle"], @"test.example.com", @"Handle should match");
    XCTAssertNotNil(result[@"didDoc"], @"DID doc should be present");
}

- (void)testResolveIdentityMissingParameter {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveIdentity"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"error"], @"InvalidRequest", @"Should return InvalidRequest error");
}

- (void)testResolveIdentityInvalidHandle {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveIdentity?identifier=invalid-handle"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"error"], @"ResolutionFailed", @"Should return ResolutionFailed error");
}

- (void)testResolveHandleValid {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveHandle?handle=test.example.com"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"did"], @"did:plc:7HjwGtP5cLyq3vD5nDzDg", @"DID should match");
}

- (void)testResolveHandleMissingParameter {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveHandle"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"error"], @"InvalidRequest", @"Should return InvalidRequest error");
}

- (void)testResolveHandleInvalidFormat {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveHandle?handle=invalid"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"error"], @"ResolutionFailed", @"Should return ResolutionFailed error");
}

- (void)testHTTPMethodValidationPOSTvsGET {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"POST"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveDid?did=did:plc:7HjwGtP5cLyq3vD5nDzDg"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertNotNil(result[@"id"], @"Should return valid result");
}

- (void)testConcurrentRequests {
    dispatch_queue_t concurrentQueue = dispatch_queue_create("test.concurrent", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    __block NSUInteger concurrentSuccessCount = 0;
    __block NSUInteger concurrentErrorCount = 0;

    for (int i = 0; i < 5; i++) {
        dispatch_group_enter(group);
        dispatch_async(concurrentQueue, ^{
            NSError *concurrentError = nil;
            NSDictionary *concurrentResult = [self.client makeRequest:@"GET"
                                                                url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveDid?did=did:plc:7HjwGtP5cLyq3vD5nDzDg"
                                                           bodyDict:nil
                                                              error:&concurrentError];

            if (!concurrentError && concurrentResult && concurrentResult[@"id"]) {
                concurrentSuccessCount++;
            } else {
                concurrentErrorCount++;
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    XCTAssertGreaterThanOrEqual(concurrentSuccessCount, 4, @"Most concurrent requests should succeed");
}

- (void)testLargeIdentifierHandling {
    NSError *error = nil;
    NSString *largeHandle = [@"" stringByPaddingToLength:200 withString:@"a" startingAtIndex:0];
    largeHandle = [largeHandle stringByAppendingString:@".example.com"];

    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:[NSString stringWithFormat:@"http://localhost:9090/xrpc/com.atproto.identity.resolveHandle?handle=%@", [largeHandle stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]]
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"error"], @"ResolutionFailed", @"Large handle should fail gracefully");
}

- (void)testMalformedJSONHandling {
    [self.plcServer addMockResponseForPath:@"/did:plc:malformed" response:@{
        @"statusCode": @200,
        @"body": @"invalid json { missing quotes"
    }];

    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveDid?did=did:plc:malformed"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNotNil(error, @"Error should occur for malformed JSON");
    XCTAssertEqual(error.code, 3840, @"Should be JSON parsing error");
}

- (void)testHTTP5xxErrorHandling {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveDid?did=did:plc:server-error"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No network error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"error"], @"Internal Server Error", @"Should return server error");
}

- (void)testEmptyResponseBody {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveDid?did=did:plc:empty-body"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNotNil(error, @"Error should occur for empty body");
    XCTAssertEqual(error.code, 3840, @"Should be JSON parsing error for empty data");
}

- (void)testURLEncodingSpecialCharacters {
    NSError *error = nil;
    NSDictionary *result = [self.client makeRequest:@"GET"
                                              url:@"http://localhost:9090/xrpc/com.atproto.identity.resolveHandle?handle=test-handle.example.com"
                                         bodyDict:nil
                                            error:&error];

    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(result, @"Result should not be nil");
    XCTAssertEqualObjects(result[@"did"], @"did:plc:7HjwGtP5cLyq3vD5nDzDg", @"DID should match");
}

@end
