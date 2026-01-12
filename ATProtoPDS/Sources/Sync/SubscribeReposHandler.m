#import "Sync/SubscribeReposHandler.h"
#import "Sync/WebSocketServer.h"
#import "Sync/WebSocketConnection.h"
#import "App/PDSController.h"
#import "Sync/EventFormatter.h"
#import "Sync/Firehose.h"
#import "Repository/RepoCommit.h"
#import <os/log.h>

NSString * const SubscribeReposHandlerErrorDomain = @"com.atproto.pds.subscribeRepos";
NSInteger const SubscribeReposHandlerErrorCodeConnectionFailed = 3000;

@interface SubscribeReposHandler () <WebSocketServerDelegate>

@property (nonatomic, strong) WebSocketServer *webSocketServer;
@property (nonatomic, strong) EventFormatter *eventFormatter;
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) os_log_t log;
@property (nonatomic, strong) dispatch_queue_t eventQueue;
@property (nonatomic, assign) NSUInteger sequenceNumber;

@end

@implementation SubscribeReposHandler

- (instancetype)initWithController:(PDSController *)controller {
    self = [super init];
    if (self) {
        _controller = controller;
        _eventFormatter = [[EventFormatter alloc] init];
        _log = os_log_create("com.atproto.pds.subscribeRepos", "SubscribeReposHandler");
        _eventQueue = dispatch_queue_create("com.atproto.pds.subscribeRepos.events", DISPATCH_QUEUE_SERIAL);
        _sequenceNumber = 0;
    }
    return self;
}

- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error {
    os_log_info(self.log, "Starting subscribeRepos WebSocket handler on port %d", port);

    self.webSocketServer = [[WebSocketServer alloc] initWithHost:@"localhost" port:port];
    self.webSocketServer.delegate = self;
    self.webSocketServer.subprotocol = @"com.atproto.sync.subscribeRepos";

    if (![self.webSocketServer start:error]) {
        os_log_error(self.log, "Failed to start WebSocket server: %@", *error);
        return NO;
    }

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandlerDidStart:)]) {
        [self.delegate subscribeReposHandlerDidStart:self];
    }

    os_log_info(self.log, "SubscribeRepos WebSocket handler started successfully");
    return YES;
}

- (void)stop {
    os_log_info(self.log, "Stopping subscribeRepos WebSocket handler");

    [self.webSocketServer stop];
    self.webSocketServer = nil;

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandlerDidStop:)]) {
        [self.delegate subscribeReposHandlerDidStop:self];
    }

    os_log_info(self.log, "SubscribeRepos WebSocket handler stopped");
}

#pragma mark - WebSocketServerDelegate

- (void)webSocketServer:(WebSocketServer *)server didAcceptConnection:(WebSocketConnection *)connection {
    os_log_info(self.log, "Accepted new WebSocket connection for subscribeRepos");

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didAcceptConnection:)]) {
        [self.delegate subscribeReposHandler:self didAcceptConnection:connection];
    }

    // Send initial state for all existing repositories
    [self sendInitialRepositoryStateToConnection:connection];
}

- (void)webSocketServer:(WebSocketServer *)server didCloseConnection:(WebSocketConnection *)connection {
    os_log_info(self.log, "Closed WebSocket connection for subscribeRepos");

    if ([self.delegate respondsToSelector:@selector(subscribeReposHandler:didCloseConnection:)]) {
        [self.delegate subscribeReposHandler:self didCloseConnection:connection];
    }
}

- (void)webSocketServer:(WebSocketServer *)server didFailWithError:(NSError *)error {
    os_log_error(self.log, "WebSocket server failed: %@", error);
}

- (void)webSocketServer:(WebSocketServer *)server stateDidChange:(WebSocketServerState)state {
    os_log_info(self.log, "WebSocket server state changed to: %ld", (long)state);
}

#pragma mark - Event Broadcasting

- (void)broadcastRepositoryCommit:(RepoCommit *)commit 
                          forRepo:(NSString *)repoDid 
                              ops:(NSArray<NSDictionary *> *)ops 
                            blobs:(NSArray<CID *> *)blobs {
    dispatch_async(self.eventQueue, ^{
        self.sequenceNumber++;

        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        payload[@"kind"] = @"commit";
        payload[@"seq"] = @(self.sequenceNumber);
        payload[@"time"] = [[NSDate date] description];
        payload[@"repo"] = repoDid;
        payload[@"commit"] = [commit.computeCID stringValue];
        if (commit.prevCID) {
            payload[@"previous"] = [commit.prevCID stringValue];
        }
        
        // Convert ops to suitable format
        NSMutableArray *opsArray = [NSMutableArray array];
        for (NSDictionary *op in ops) {
            [opsArray addObject:op];
        }
        payload[@"ops"] = opsArray;
        
        // Convert blobs to string CIDs
        NSMutableArray *blobsArray = [NSMutableArray array];
        for (CID *blobCID in blobs) {
            [blobsArray addObject:[blobCID stringValue]];
        }
        payload[@"blobs"] = blobsArray;

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeCBORObject:payload error:&error];

        if (!eventData) {
            os_log_error(self.log, "Failed to encode commit event: %@", error);
            return;
        }

        [self.webSocketServer broadcastMessage:eventData toConnectionsMatching:nil];
        os_log_info(self.log, "Broadcast commit event for repo %@, seq %lu", repoDid, (unsigned long)self.sequenceNumber);
    });
}

- (void)broadcastIdentityChange:(NSString *)did handle:(nullable NSString *)handle {
    dispatch_async(self.eventQueue, ^{
        self.sequenceNumber++;

        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        payload[@"kind"] = @"identity";
        payload[@"seq"] = @(self.sequenceNumber);
        payload[@"time"] = [[NSDate date] description];
        payload[@"did"] = did;
        if (handle) {
            payload[@"handle"] = handle;
        }

        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeCBORObject:payload error:&error];

        if (!eventData) {
            os_log_error(self.log, "Failed to encode identity event: %@", error);
            return;
        }

        [self.webSocketServer broadcastMessage:eventData toConnectionsMatching:nil];
        os_log_info(self.log, "Broadcast identity event for DID %@, seq %lu", did, (unsigned long)self.sequenceNumber);
    });
}

#pragma mark - Private Methods

- (void)sendInitialRepositoryStateToConnection:(WebSocketConnection *)connection {
    // TODO: Send current state of all repositories to new connections
    os_log_info(self.log, "Sending initial repository state to new connection");
}

@end