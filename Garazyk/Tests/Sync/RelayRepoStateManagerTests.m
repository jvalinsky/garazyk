#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayRepoStateManager.h"

@interface RelayRepoStateManagerTests : XCTestCase
@end

@implementation RelayRepoStateManagerTests

- (void)testDefaultInitializes {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    XCTAssertNotNil(manager);
}

- (void)testHandleCommitForRepo {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:test" root:@"bafyrexxx" rev:@"3" seq:100];
    
    XCTAssertEqualObjects([manager rootCIDForRepo:@"did:plc:test"], @"bafyrexxx");
    XCTAssertEqualObjects([manager revForRepo:@"did:plc:test"], @"3");
    XCTAssertEqual([manager cursorForRepo:@"did:plc:test"], 100);
}

- (void)testGetNonExistentRepoState {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    XCTAssertNil([manager rootCIDForRepo:@"did:plc:nonexistent"]);
}

- (void)testHandleTombstone {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:test" root:@"bafyrexxx" rev:@"3" seq:100];
    [manager handleTombstoneForRepo:@"did:plc:test"];
    
    XCTAssertEqual([manager statusForRepo:@"did:plc:test"], RelayRepoStatusTombstoned);
}

- (void)testRepoCount {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:a" root:@"bafyrea" rev:@"1" seq:1];
    [manager handleCommitForRepo:@"did:plc:b" root:@"bafyreb" rev:@"2" seq:2];
    
    XCTAssertEqual([manager repoCount], 2);
}

- (void)testAllRepos {
    RelayRepoStateManager *manager = [[RelayRepoStateManager alloc] init];
    [manager handleCommitForRepo:@"did:plc:a" root:@"bafyrea" rev:@"1" seq:1];
    [manager handleCommitForRepo:@"did:plc:b" root:@"bafyreb" rev:@"2" seq:2];
    
    NSArray *repos = [manager allRepos];
    XCTAssertEqual(repos.count, 2);
}

@end
