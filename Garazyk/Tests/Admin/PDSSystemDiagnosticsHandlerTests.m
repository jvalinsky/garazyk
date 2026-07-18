// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Admin/Diagnostics/PDSSystemDiagnosticsHandler.h"
#import "Admin/Diagnostics/PDSSequencerHealthHandler.h"
#import "Admin/Diagnostics/PDSBlobAuditHandler.h"
#import "Admin/Diagnostics/PDSRateLimitAdminHandler.h"

@interface PDSSystemDiagnosticsHandlerTests : XCTestCase
@property (nonatomic, strong) PDSSystemDiagnosticsHandler *handler;
@end

@implementation PDSSystemDiagnosticsHandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [[PDSSystemDiagnosticsHandler alloc] init];
}

- (void)testSharedHandlerReturnsSameInstance {
    PDSSystemDiagnosticsHandler *first = [PDSSystemDiagnosticsHandler sharedHandler];
    PDSSystemDiagnosticsHandler *second = [PDSSystemDiagnosticsHandler sharedHandler];
    XCTAssertNotNil(first);
    XCTAssertEqual(first, second);
}

- (void)testUnknownPathReturns404 {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/unknown"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 404);
    XCTAssertEqualObjects(contentType, @"application/json");
    XCTAssertTrue([body containsString:@"Not Found"]);
}

- (void)testSequencerPathRoutesToSequencerHandler {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/sequencer/stats"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 200);
    XCTAssertEqualObjects(contentType, @"application/json");
    NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNotNil(jsonData);
    NSError *jsonError = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    XCTAssertNil(jsonError);
    XCTAssertNotNil(dict);
    XCTAssertTrue(dict[@"currentSeq"] != nil, @"Response should contain currentSeq");
}

- (void)testBlobsPathRoutesToBlobAuditHandler {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSData *requestBody = [NSJSONSerialization dataWithJSONObject:@{@"auditType": @"orphans", @"dryRun": @YES}
                                                          options:0
                                                            error:nil];
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/blobs/audit"
                                                  headers:@{}
                                                     body:requestBody
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 200);
    XCTAssertEqualObjects(contentType, @"application/json");
    XCTAssertTrue([body containsString:@"jobId"], @"Expected job response from blob audit route");
}

- (void)testRateLimitsPathRoutesToRateLimitHandler {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/ratelimits/top"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 200);
    XCTAssertEqualObjects(contentType, @"application/json");
    XCTAssertNotNil(body);
}

- (void)testAuditManagerIsForwardedToBlobHandler {
    NSInteger statusCode = 0;
    NSData *requestBody = [NSJSONSerialization dataWithJSONObject:@{@"auditType": @"orphans", @"dryRun": @YES}
                                                          options:0
                                                            error:nil];
    [self.handler handleRequestWithMethod:1
                                     path:@"/blobs/audit"
                                  headers:@{}
                                     body:requestBody
                               statusCode:&statusCode
                              contentType:NULL];
    XCTAssertEqual(statusCode, 200);
}

- (void)testSequencerHistoryRoutePassesHoursParameter {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/sequencer/history?hours=48"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 200);
    NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    XCTAssertNotNil(dict);
    XCTAssertEqualObjects(dict[@"hours"], @48);
    XCTAssertNotNil(dict[@"dataPoints"]);
}

@end
