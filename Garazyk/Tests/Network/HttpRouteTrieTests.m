// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpRouteTrie.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface HttpRouteTrieTests : XCTestCase
@end

@implementation HttpRouteTrieTests

- (void)testBasicInsertionAndRetrievalReturnsValidHandler {
    HttpRouteTrie *trie = [[HttpRouteTrie alloc] init];
    
    [trie insertRoute:@"GET" pattern:@"/api/v1/status" handler:^(HttpRequest *req, HttpResponse *res){} priority:1];
    
    NSDictionary *params = nil;
    HttpRouteHandler handler = [trie handlerForMethod:@"GET" path:@"/api/v1/status" outParameters:&params];
    
    XCTAssertNotNil(handler);
    XCTAssertEqual(params.count, 0U); // additional assert to avoid FalsePositive
}

- (void)testParameterExtractionMatchesParamsId {
    HttpRouteTrie *trie = [[HttpRouteTrie alloc] init];
    
    [trie insertRoute:@"GET" pattern:@"/users/:id" handler:^(HttpRequest *req, HttpResponse *res){} priority:1];
    
    NSDictionary *params = nil;
    HttpRouteHandler handler = [trie handlerForMethod:@"GET" path:@"/users/123" outParameters:&params];
    
    XCTAssertNotNil(handler);
    XCTAssertEqualObjects(params[@"id"], @"123");
}

- (void)testWildcardMatchingReturnsValidHandler {
    HttpRouteTrie *trie = [[HttpRouteTrie alloc] init];
    
    [trie insertRoute:@"GET" pattern:@"/files/*" handler:^(HttpRequest *req, HttpResponse *res){} priority:1];
    
    NSDictionary *params = nil;
    HttpRouteHandler handler = [trie handlerForMethod:@"GET" path:@"/files/document.txt" outParameters:&params];
    
    XCTAssertNotNil(handler);
    XCTAssertTrue([params isKindOfClass:[NSDictionary class]]);
}

#ifndef GNUSTEP
- (void)testConcurrentAccess {
    // This test attempts to reproduce the segfault logic by stressing the trie
    HttpRouteTrie *trie = [[HttpRouteTrie alloc] init];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Concurrent routes"];
    expectation.expectedFulfillmentCount = 100;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("com.atproto.pds.test.stress", DISPATCH_QUEUE_CONCURRENT);
    
    // Insert initial route
    [trie insertRoute:@"GET" pattern:@"/initial" handler:^(HttpRequest *req, HttpResponse *res){} priority:1];
    
    for (int i = 0; i < 100; i++) {
        dispatch_group_enter(group);
        dispatch_async(queue, ^{
             // Mix of inserts and lookups
            if (i % 2 == 0) {
                [trie insertRoute:@"GET" 
                          pattern:[NSString stringWithFormat:@"/route/%d", i] 
                          handler:^(HttpRequest *req, HttpResponse *res){} 
                         priority:1];
            } else {
                NSDictionary *params = nil;
                [trie handlerForMethod:@"GET" path:@"/initial" outParameters:&params];
                [trie handlerForMethod:@"GET" path:@"/favicon.ico" outParameters:&params]; // The path that caused crash
            }
            
            [expectation fulfill];
            dispatch_group_leave(group);
        });
    }
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}
#endif

@end
