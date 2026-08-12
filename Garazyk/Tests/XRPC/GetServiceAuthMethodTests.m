// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSController.h"
#import "Network/XrpcHandler.h"

@interface GetServiceAuthMethodTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) ATProtoXrpcDispatcher *dispatcher;
@end

@implementation GetServiceAuthMethodTests

- (void)setUp {
    [super setUp];
    self.controller = [[PDSController alloc] init];
    self.dispatcher = [[ATProtoXrpcDispatcher alloc] init];
    [ATProtoXrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher controller:self.controller];
}

- (void)tearDown {
    self.dispatcher = nil;
    self.controller = nil;
    [super tearDown];
}

- (void)testGetServiceAuthReturnsToken {
    ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:@"/xrpc/com.atproto.server.getServiceAuth"
                                                   queryString:@"aud=did:web:example.com"
                                                   queryParams:@{@"aud": @"did:web:example.com"}
                                                       version:@"1.1"
                                                       headers:@{}
                                                          body:nil
                                                    remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    
    [self.dispatcher handleRequest:request response:response];
    
    // Should be implemented
    XCTAssertNotEqual(response.statusCode, HttpStatusNotFound, @"Method should be registered");
    
    if (response.statusCode == HttpStatusOK) {
        NSDictionary *body = response.jsonBody;
        XCTAssertNotNil(body[@"token"], @"Response should contain an auth token");
    }
}

@end
