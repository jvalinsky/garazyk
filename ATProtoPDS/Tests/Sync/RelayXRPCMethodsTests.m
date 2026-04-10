#import <XCTest/XCTest.h>
#import "Sync/RelayXRPCMethods.h"
#import "Sync/RelayConfiguration.h"
#import "Sync/RelayRepoStateManager.h"
#import "Sync/RelayEventBuffer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcMethodRegistry.h"

@interface RelayXRPCMethodsTests : XCTestCase
@property (nonatomic, strong) RelayConfiguration *config;
@property (nonatomic, strong) RelayRepoStateManager *repoManager;
@property (nonatomic, strong) RelayEventBuffer *eventBuffer;
@property (nonatomic, strong) RelayXRPCMethods *methods;
@end

@implementation RelayXRPCMethodsTests

- (void)setUp {
    _config = [[RelayConfiguration alloc] initWithUpstreamURLs:@[@"pds.example.com"]
                                                 downstreamPort:2584
                                                  retentionHours:72
                                                validationMode:RelayValidationModeLogOnly];
    _repoManager = [[RelayRepoStateManager alloc] init];
    _eventBuffer = [[RelayEventBuffer alloc] initWithRetentionHours:72 maxEvents:100000];
    _methods = [[RelayXRPCMethods alloc] initWithConfiguration:_config
                                                repoStateManager:_repoManager
                                                     eventBuffer:_eventBuffer];
}

- (void)testGetHeadReturnsRootForKnownRepo {
    [_repoManager handleCommitForRepo:@"did:plc:test" root:@"bafyrexxx" rev:@"3" seq:100];
    
    XCTAssertEqualObjects([_repoManager rootCIDForRepo:@"did:plc:test"], @"bafyrexxx");
}

- (void)testRepoStateTracksMultipleRepos {
    [_repoManager handleCommitForRepo:@"did:plc:a" root:@"bafyrea" rev:@"1" seq:1];
    [_repoManager handleCommitForRepo:@"did:plc:b" root:@"bafyreb" rev:@"2" seq:2];
    
    XCTAssertEqual([_repoManager repoCount], 2);
}

- (void)testEventBufferAcceptsEvents {
    RelayEventBuffer *buffer = [RelayEventBuffer bufferWithDefaultRetention];
    NSDictionary *event = @{@"repo": @"did:plc:test", @"commit": @{@"rev": @"3"}};
    [buffer appendEvent:event seq:1 timestamp:[NSDate date]];
    
    XCTAssertEqual(buffer.eventCount, 1);
}

- (void)testRepoStateManagerStatusEnum {
    [_repoManager handleCommitForRepo:@"did:plc:active" root:@"bafyre1" rev:@"1" seq:1];
    [_repoManager handleTombstoneForRepo:@"did:plc:tombstoned"];
    
    XCTAssertEqual([_repoManager statusForRepo:@"did:plc:active"], RelayRepoStatusActive);
    XCTAssertEqual([_repoManager statusForRepo:@"did:plc:tombstoned"], RelayRepoStatusTombstoned);
}

@end
