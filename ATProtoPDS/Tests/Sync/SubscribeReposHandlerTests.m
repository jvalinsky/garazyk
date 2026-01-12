#import <XCTest/XCTest.h>
#import "Sync/SubscribeReposHandler.h"
#import "App/PDSController.h"
#import "Repository/RepoCommit.h"
#import "Sync/WebSocketConnection.h"
#import "Sync/WebSocketServer.h"

@interface SubscribeReposHandlerTests : XCTestCase
@property (nonatomic, strong) SubscribeReposHandler *handler;
@property (nonatomic, strong) PDSController *controller;
@end

@implementation SubscribeReposHandlerTests

- (void)setUp {
    [super setUp];
    // Use a real controller but it might need a real database
    self.controller = [[PDSController alloc] init];
    self.handler = [[SubscribeReposHandler alloc] initWithController:self.controller];
}

- (void)tearDown {
    self.handler = nil;
    self.controller = nil;
    [super tearDown];
}

- (void)testBroadcastCommitWithOps {
    RepoCommit *commit = [RepoCommit createCommitWithDid:@"did:plc:test" 
                                                   data:[CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"] 
                                                    rev:@"3l66k7pp33p" 
                                                   prev:nil];
    
    NSArray *ops = @[
        @{
            @"action": @"create",
            @"path": @"app.bsky.feed.post/3jqfcqzm3fo2j",
            @"cid": @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"
        }
    ];
    
    NSArray *blobs = @[
        [CID cidFromString:@"bafkreidmv76shvthv2m762sk26atksnk7v7hxuvrk6kk6kk6kk6kk6k"]
    ];
    
    // This is a minimal test to ensure we can pass ops and blobs
    // and that they are handled without crashing.
    XCTAssertNoThrow([self.handler broadcastRepositoryCommit:commit 
                                                     forRepo:@"did:plc:test" 
                                                         ops:ops 
                                                       blobs:blobs], 
                     @"Should handle broadcast with ops and blobs");
}

@end
