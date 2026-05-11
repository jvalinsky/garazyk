// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/MSTViewer/MSTViewerHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface MSTViewerHandlerTests : XCTestCase
@property (nonatomic, strong) MSTViewerHandler *handler;
@end

@implementation MSTViewerHandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [MSTViewerHandler sharedHandler];
}

- (void)testCanHandleRequest {
    HttpRequest *req1 = [[HttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET" path:@"/mst-viewer" queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:@{} body:nil remoteAddress:nil];
    XCTAssertTrue([self.handler canHandleRequest:req1]);

    HttpRequest *req2 = [[HttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET" path:@"/api/mst/tree" queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:@{} body:nil remoteAddress:nil];
    XCTAssertTrue([self.handler canHandleRequest:req2]);

    HttpRequest *req3 = [[HttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET" path:@"/other" queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:@{} body:nil remoteAddress:nil];
    XCTAssertFalse([self.handler canHandleRequest:req3]);
}

- (void)testHandleRequestIndexReturns200HtmlContent {
    HttpRequest *req = [[HttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET" path:@"/mst-viewer" queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:@{} body:nil remoteAddress:nil];
    HttpResponse *res = [[HttpResponse alloc] init];
    
    [self.handler handleRequest:req response:res];
    
    XCTAssertEqual(res.statusCode, 200);
    XCTAssertTrue([[res headerForKey:@"Content-Type"] containsString:@"text/html"]);
}

@end
