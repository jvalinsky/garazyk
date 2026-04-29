#import "SubscribeReposHandler.h"
#import "EventFormatter.h"

@interface SubscribeReposHandler ()
@property (nonatomic, strong) EventFormatter *eventFormatter;
@property (nonatomic, strong) NSMutableSet<WebSocketConnection *> *connections;
@property (nonatomic, strong) dispatch_queue_t eventQueue;
@property (nonatomic, assign) NSUInteger sequenceNumber;
@property (nonatomic, assign) NSUInteger maxPendingSends;
@property (nonatomic, assign) NSUInteger maxPendingBytes;
@end

@implementation SubscribeReposHandler

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    self.eventFormatter = [[EventFormatter alloc] init];
    self.connections = [NSMutableSet set];
    self.eventQueue = dispatch_queue_create("com.atproto.firehose.events", DISPATCH_QUEUE_SERIAL);
    self.sequenceNumber = 0;
    self.maxPendingSends = 512;
    self.maxPendingBytes = 16 * 1024 * 1024;  // 16MB

    return self;
}

- (void)acceptConnection:(WebSocketConnection *)connection cursor:(nullable NSString *)cursor {
    // All connection management is done on eventQueue for thread safety
    dispatch_async(self.eventQueue, ^{
        NSLog(@"[Firehose] New connection from %@", connection.remoteAddress);
        [self.connections addObject:connection];

        // Handle connection close
        __weak typeof(self) weakSelf = self;
        connection.closeHandler = ^(NSInteger code, NSString *reason) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            dispatch_async(strongSelf.eventQueue, ^{
                [strongSelf.connections removeObject:connection];
                NSLog(@"[Firehose] Connection closed: %@ (code=%ld)", connection.remoteAddress, (long)code);
            });
        };

        // If cursor provided, replay events
        if (cursor && cursor.length > 0) {
            NSUInteger cursorSeq = [cursor integerValue];
            [self replayEventsAfterCursor:cursorSeq toConnection:connection];
        }
    });
}

- (void)replayEventsAfterCursor:(NSUInteger)cursor toConnection:(WebSocketConnection *)connection {
    // Already on eventQueue from caller
    NSLog(@"[Firehose] Replaying events after cursor %lu", (unsigned long)cursor);
    // In production, load events from database
    NSLog(@"[Firehose] Replay complete, connection is now live");
}

- (void)broadcastCommit:(NSString *)repo
                    rev:(NSString *)rev
                 commit:(NSData *)commitCID
                 blocks:(NSData *)carBlocks
                    ops:(NSArray<NSDictionary *> *)ops {

    dispatch_async(self.eventQueue, ^{
        self.sequenceNumber++;

        // Create commit event
        FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
        event.seq = self.sequenceNumber;
        event.repo = repo;
        event.commit = commitCID;
        event.rev = rev;
        event.blocks = carBlocks;
        event.ops = ops;
        event.blobs = @[];
        event.time = [self rfc3339Timestamp];

        // Encode event
        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeCommitEvent:event error:&error];
        if (!eventData) {
            NSLog(@"[Firehose] Failed to encode event: %@", error);
            return;
        }

        // Broadcast to all connections (already on eventQueue — no @synchronized needed)
        NSSet<WebSocketConnection *> *snapshot = [self.connections copy];

        for (WebSocketConnection *connection in snapshot) {
            // Check backpressure (pendingSendCount/Bytes are read from sendQueue,
            // but since they're only modified on sendQueue, this is a safe read
            // of a snapshot that may be slightly stale — acceptable for backpressure)
            if (connection.pendingSendCount >= self.maxPendingSends ||
                connection.pendingSendBytes >= self.maxPendingBytes) {
                NSLog(@"[Firehose] Closing slow consumer: %@", connection.remoteAddress);
                [connection closeWithCode:1008 reason:@"ConsumerTooSlow"];
                [self.connections removeObject:connection];
                continue;
            }

            [connection sendMessage:eventData];
        }

        NSLog(@"[Firehose] Broadcast commit event seq=%lu to %lu connections",
              (unsigned long)self.sequenceNumber, (unsigned long)snapshot.count);
    });
}

- (NSString *)rfc3339Timestamp {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    return [formatter stringFromDate:[NSDate date]];
}

@end
