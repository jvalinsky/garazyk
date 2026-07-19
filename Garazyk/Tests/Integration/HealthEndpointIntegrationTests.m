// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "App/PDSController.h"
#import "Database/Monitoring/PDSHealthCheck.h"

@interface HealthEndpointIntegrationTests : XCTestCase
@property (nonatomic, strong) HttpServer *server;
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, copy) NSString *tempDir;
@property (nonatomic, assign) BOOL serverStarted;
@end

@implementation HealthEndpointIntegrationTests

- (void)setUp {
    [super setUp];
    
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"pds-health-int-test-%@", uuid]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.controller = [[PDSController alloc] initWithDirectory:self.tempDir
                                               serviceMaxSize:10
                                             userDatabaseSize:1000];
    
    self.server = [HttpServer serverWithPort:0]; // Random port
    XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];
    [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher controller:self.controller];
    
    [self.server addHandlerForPath:@"/xrpc" handler:^(HttpRequest *request, HttpResponse *response) {
        [dispatcher handleRequest:request response:response];
    }];
    
    [self.server addRoute:@"GET" path:@"/_health" handler:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *health = [[PDSHealthCheck sharedInstance] performHealthCheck];
        response.statusCode = [health[@"status"] isEqualToString:@"critical"] ? 503 : 200;
        [response setJsonBody:health];
    }];
    
    NSError *error = nil;
    self.serverStarted = [self.server startWithError:&error];
    XCTAssertTrue(self.serverStarted, @"Failed to start server: %@", error);
}

- (void)tearDown {
    [self.server stop];
    [self.controller stopServer];
    self.controller = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (void)testXRPCHealthEndpoint {
    if (!self.serverStarted) {
        return;
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%hu/xrpc/_health", self.server.port]];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Health check"];
    
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        if (error) {
            [expectation fulfill];
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertTrue([httpResponse isKindOfClass:[NSHTTPURLResponse class]]);
        XCTAssertEqual(httpResponse.statusCode, 200);

        XCTAssertNotNil(data);
        if (!data) {
            [expectation fulfill];
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);
        XCTAssertNotNil(json);
        XCTAssertEqualObjects(json[@"status"], @"healthy");
        XCTAssertNotNil(json[@"version"]);
        XCTAssertNotNil(json[@"database_integrity"]);
        
        [expectation fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testRootHealthEndpoint {
    if (!self.serverStarted) {
        return;
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%hu/_health", self.server.port]];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Root health check"];
    
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        if (error) {
            [expectation fulfill];
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertTrue([httpResponse isKindOfClass:[NSHTTPURLResponse class]]);
        XCTAssertEqual(httpResponse.statusCode, 200);

        XCTAssertNotNil(data);
        if (!data) {
            [expectation fulfill];
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);
        XCTAssertNotNil(json);
        XCTAssertEqualObjects(json[@"status"], @"healthy");
        
        [expectation fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end
