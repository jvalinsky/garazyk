// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Admin/Diagnostics/PDSBlobAuditHandler.h"

@interface PDSBlobAuditHandlerTests : XCTestCase
@property (nonatomic, strong) PDSBlobAuditHandler *handler;
@end

@implementation PDSBlobAuditHandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [[PDSBlobAuditHandler alloc] init];
}

- (void)testSharedHandlerReturnsSameInstance {
    PDSBlobAuditHandler *first = [PDSBlobAuditHandler sharedHandler];
    PDSBlobAuditHandler *second = [PDSBlobAuditHandler sharedHandler];
    XCTAssertNotNil(first);
    XCTAssertEqual(first, second);
}

- (void)testAuditEndpointReturnsUnavailableWithoutManager {
    NSInteger statusCode = 0;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/audit"
                                                  headers:@{}
                                                     body:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                               statusCode:&statusCode
                                              contentType:NULL];
    XCTAssertEqual(statusCode, 503);
    XCTAssertTrue([body containsString:@"Unavailable"] || [body containsString:@"error"],
                  @"Expected unavailable or error response, got %@", body);
}

- (void)testStatusEndpointReturnsErrorWithoutManager {
    NSInteger statusCode = 0;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/status?jobId=fake-id"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:NULL];
    XCTAssertEqual(statusCode, 503);
    XCTAssertNotNil(body);
}

- (void)testUnknownSubpathReturns404 {
    NSInteger statusCode = 0;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/nonexistent"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:NULL];
    XCTAssertEqual(statusCode, 404);
    XCTAssertTrue([body containsString:@"Not Found"]);
}

- (void)testAuditEndpointRequiresPOST {
    NSInteger statusCode = 0;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/audit"
                                                  headers:@{}
                                                     body:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
                                               statusCode:&statusCode
                                              contentType:NULL];
    XCTAssertEqual(statusCode, 503);
    XCTAssertNotNil(body);
}

@end
