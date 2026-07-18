// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Admin/Diagnostics/PDSSequencerHealthHandler.h"

@interface PDSSequencerHealthHandlerTests : XCTestCase
@property (nonatomic, strong) PDSSequencerHealthHandler *handler;
@end

@implementation PDSSequencerHealthHandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [[PDSSequencerHealthHandler alloc] init];
}

- (void)testSharedHandlerReturnsSameInstance {
    PDSSequencerHealthHandler *first = [PDSSequencerHealthHandler sharedHandler];
    PDSSequencerHealthHandler *second = [PDSSequencerHealthHandler sharedHandler];
    XCTAssertNotNil(first);
    XCTAssertEqual(first, second);
}

- (void)testStatsEndpointReturnsValidJSON {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/stats"
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
    XCTAssertTrue(dict[@"currentSeq"] != nil);
    XCTAssertTrue(dict[@"eventsPerSecond"] != nil);
    XCTAssertTrue(dict[@"subscriberCount"] != nil);
    XCTAssertTrue(dict[@"healthStatus"] != nil);
}

- (void)testStatsEndpointReturnsStubValuesWithoutCollector {
    NSInteger statusCode = 0;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/stats"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:NULL];
    NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    XCTAssertEqualObjects(dict[@"currentSeq"], @0);
    XCTAssertEqualObjects(dict[@"eventsPerSecond"], @0.0);
    XCTAssertEqualObjects(dict[@"subscriberCount"], @0);
    XCTAssertEqualObjects(dict[@"healthStatus"], @"unknown");
}

- (void)testHistoryEndpointReturnsDataPointsArray {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/history"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 200);
    XCTAssertEqualObjects(contentType, @"application/json");
    NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    XCTAssertNotNil(dict);
    XCTAssertNotNil(dict[@"dataPoints"]);
    XCTAssertTrue([dict[@"dataPoints"] isKindOfClass:[NSArray class]]);
    XCTAssertEqualObjects(dict[@"hours"], @24);
}

- (void)testHistoryEndpointParsesCustomHours {
    NSInteger statusCode = 0;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/history?hours=12"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:NULL];
    NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    XCTAssertEqualObjects(dict[@"hours"], @12);
}

- (void)testUnknownPathReturns404 {
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

- (void)testGetMethodAcceptedForStats {
    NSInteger statusCode = 0;
    NSString *body = [self.handler handleRequestWithMethod:0
                                                     path:@"/stats"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:NULL];
    XCTAssertEqual(statusCode, 200);
    XCTAssertNotNil(body);
}

- (void)testHistoryIncludesStartTime {
    NSInteger statusCode = 0;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/history?hours=24"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:NULL];
    NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    XCTAssertNotNil(dict[@"startTime"]);
    NSTimeInterval startTime = [dict[@"startTime"] doubleValue];
    XCTAssertTrue(startTime > 0, @"startTime should be a positive unix timestamp");
}

@end
