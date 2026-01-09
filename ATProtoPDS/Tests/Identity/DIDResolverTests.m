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
    [resolver resolveMultipleDIDs:dids completion:^(NSDictionary<NSString *, NSDictionary *> *results, NSError *error) {
        XCTAssertNotNil(results);
        XCTAssertEqual(results.count, 2);
        XCTAssertNotNil(results[@"did:plc:test1"]);
        XCTAssertNotNil(results[@"did:plc:test2"]);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end
