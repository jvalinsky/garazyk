#import <XCTest/XCTest.h>
#import "Network/Http1PipelinePolicy.h"

@interface Http1PipelinePolicyTests : XCTestCase
@property (nonatomic, strong) Http1PipelinePolicy *policy;
@end

@implementation Http1PipelinePolicyTests

- (void)setUp {
    [super setUp];
    self.policy = [[Http1PipelinePolicy alloc] init];
    // Default maxPipelinedRequests = 4
}

- (void)tearDown {
    self.policy = nil;
    [super tearDown];
}

- (void)testInitialStatePendingDispatchCountIsZero {
    XCTAssertEqual(self.policy.pendingDispatchCount, 0);
    XCTAssertTrue([self.policy shouldReadMoreData]);
}

- (void)testRequestParsedUnderLimitMatchesDispatchAction {
    Http1PipelineAction action = [self.policy requestParsed];
    XCTAssertEqual(action, Http1PipelineActionDispatch);
}

- (void)testDispatchIncrementsCount {
    [self.policy requestDispatched];
    XCTAssertEqual(self.policy.pendingDispatchCount, 1);
    XCTAssertTrue([self.policy shouldReadMoreData]);
}

- (void)testQueueWhenAtLimit {
    for (int i = 0; i < 4; i++) {
        [self.policy requestDispatched];
    }
    
    XCTAssertEqual(self.policy.pendingDispatchCount, 4);
    XCTAssertFalse([self.policy shouldReadMoreData], @"Should not read more when pipeline is full");
    
    Http1PipelineAction action = [self.policy requestParsed];
    XCTAssertEqual(action, Http1PipelineActionQueue, @"Should queue when limit is reached");
}

- (void)testResponseCompletedDecrementsCount {
    [self.policy requestDispatched]; // 1
    [self.policy requestDispatched]; // 2
    
    XCTAssertEqual(self.policy.pendingDispatchCount, 2);
    
    [self.policy responseCompleted];
    XCTAssertEqual(self.policy.pendingDispatchCount, 1);
    
    [self.policy responseCompleted];
    XCTAssertEqual(self.policy.pendingDispatchCount, 0);
    
    // Should not underflow
    [self.policy responseCompleted];
    XCTAssertEqual(self.policy.pendingDispatchCount, 0);
}

- (void)testCustomLimitFailsToReadMoreData {
    self.policy.maxPipelinedRequests = 2;
    
    [self.policy requestDispatched];
    [self.policy requestDispatched];
    
    XCTAssertEqual([self.policy requestParsed], Http1PipelineActionQueue);
    XCTAssertFalse([self.policy shouldReadMoreData]);
}

@end
