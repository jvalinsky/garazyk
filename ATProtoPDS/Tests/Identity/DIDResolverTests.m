#import <XCTest/XCTest.h>
#import "Core/DID.h"

@interface DIDResolverTests : XCTestCase

@property (nonatomic, strong) DIDResolver *resolver;

@end

@implementation DIDResolverTests

- (void)setUp {
    [super setUp];
    self.resolver = [[DIDResolver alloc] init];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testDIDResolutionCaching {
    DIDResolver *resolver = [[DIDResolver alloc] init];

    // First resolution should cache
    XCTestExpectation *expectation = [self expectationWithDescription:@"First resolution"];
    [resolver resolveDID:@"did:plc:test" completion:^(NSDictionary *document, NSError *error) {
        XCTAssertNotNil(document);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // Second resolution should use cache
    expectation = [self expectationWithDescription:@"Cached resolution"];
    [resolver resolveDID:@"did:plc:test" completion:^(NSDictionary *document, NSError *error) {
        XCTAssertNotNil(document);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil]; // Should be fast
}

- (void)testBatchResolution {
    DIDResolver *resolver = [[DIDResolver alloc] init];
    NSArray *dids = @[@"did:plc:test1", @"did:plc:test2"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Batch resolution"];
    [resolver resolveMultipleDIDs:dids completion:^(NSDictionary<NSString *, id> *results, NSError *error) {
        XCTAssertNotNil(results);
        XCTAssertEqual(results.count, 2);

        // Check that results contain either documents or error info
        for (NSString *did in dids) {
            NSDictionary *result = results[did];
            XCTAssertNotNil(result);
            XCTAssertTrue([result[@"document"] isKindOfClass:[NSDictionary class]] ||
                         [result[@"error"] isKindOfClass:[NSError class]]);
        }

        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testTTLCaching {
    DIDResolver *resolver = [[DIDResolver alloc] init];

    // Mock a cached document
    NSDictionary *mockDocument = @{@"id": @"did:test:123", @"test": @"data"};
    [resolver.cache setObject:mockDocument forKey:@"did:test:123"];

    // Set a timestamp that's within stale TTL but beyond fresh TTL
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval staleTime = currentTime - (resolver->_staleTTL + 60); // 1 hour + 1 min ago
    resolver->_cacheTimestamps[@"did:test:123"] = @(staleTime);

    XCTestExpectation *expectation = [self expectationWithDescription:@"TTL caching"];
    [resolver resolveDID:@"did:test:123" completion:^(NSDictionary *document, NSError *error) {
        XCTAssertNotNil(document);
        XCTAssertEqualObjects(document[@"id"], @"did:test:123");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testExpiredCacheEviction {
    DIDResolver *resolver = [[DIDResolver alloc] init];

    // Mock a cached document
    NSDictionary *mockDocument = @{@"id": @"did:test:expired", @"test": @"data"};
    [resolver.cache setObject:mockDocument forKey:@"did:test:expired"];

    // Set a timestamp that's beyond max TTL
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval expiredTime = currentTime - (resolver->_maxTTL + 60); // 1 day + 1 min ago
    resolver->_cacheTimestamps[@"did:test:expired"] = @(expiredTime);

    // This should trigger a fresh resolution since cache is expired
    XCTestExpectation *expectation = [self expectationWithDescription:@"Expired cache"];
    [resolver resolveDID:@"did:test:expired" completion:^(NSDictionary *document, NSError *error) {
        // Since this is a test DID that doesn't exist, we expect an error
        XCTAssertNil(document);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end
