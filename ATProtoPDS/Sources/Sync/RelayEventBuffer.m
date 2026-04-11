#import "Sync/RelayEventBuffer.h"

@interface BufferedEvent : NSObject
@property (nonatomic, strong) id event;
@property (nonatomic, assign) int64_t seq;
@property (nonatomic, strong) NSDate *timestamp;
@end

@implementation BufferedEvent
@end

@interface RelayEventBuffer ()

@property (nonatomic, assign, readwrite) NSUInteger retentionSeconds;
@property (nonatomic, assign, readwrite) NSUInteger maxEvents;
@property (nonatomic, strong) NSMutableArray<BufferedEvent *> *buffer;
dispatch_queue_t _bufferQueue;
@property (nonatomic, assign) int64_t oldestSeq;
@property (nonatomic, assign) int64_t newestSeq;

@end

@implementation RelayEventBuffer

- (instancetype)initWithRetentionHours:(NSUInteger)hours maxEvents:(NSUInteger)maxEvents {
    self = [super init];
    if (self) {
        _retentionSeconds = hours * 3600;
        _maxEvents = maxEvents > 0 ? maxEvents : 100000;
        _buffer = [NSMutableArray arrayWithCapacity:_maxEvents];
        _bufferQueue = dispatch_queue_create("com.atproto.relay.buffer", DISPATCH_QUEUE_SERIAL);
        _oldestSeq = -1;
        _newestSeq = -1;
    }
    return self;
}

+ (instancetype)bufferWithDefaultRetention {
    return [[RelayEventBuffer alloc] initWithRetentionHours:72 maxEvents:100000];
}

- (void)appendEvent:(id)event seq:(int64_t)seq {
    [self appendEvent:event seq:seq timestamp:[NSDate date]];
}

- (void)appendEvent:(id)event seq:(int64_t)seq timestamp:(NSDate *)timestamp {
    dispatch_async(_bufferQueue, ^{
        BufferedEvent *e = [[BufferedEvent alloc] init];
        e.event = event;
        e.seq = seq;
        e.timestamp = timestamp;
        
        if (self.newestSeq < seq) {
            self.newestSeq = seq;
        }
        if (self.oldestSeq < 0 || seq < self.oldestSeq) {
            self.oldestSeq = seq;
        }
        
        [self.buffer addObject:e];
        
        // Prune if over max
        if (self.buffer.count > self.maxEvents) {
            [self.buffer removeObjectAtIndex:0];
            if (self.buffer.count > 0) {
                self.oldestSeq = ((BufferedEvent *)self.buffer[0]).seq;
            }
        }
    });
}

- (nullable NSArray *)eventsAfterCursor:(int64_t)cursor count:(NSUInteger)count {
    __block NSMutableArray *result = [NSMutableArray array];
    dispatch_sync(_bufferQueue, ^{
        for (BufferedEvent *e in self.buffer) {
            if (e.seq > cursor) {
                [result addObject:e.event];
                if (result.count >= count) {
                    break;
                }
            }
        }
    });
    return result.count > 0 ? [result copy] : nil;
}

- (nullable NSArray *)eventsInTimeRange:(NSDate *)start end:(NSDate *)end {
    __block NSMutableArray *result = [NSMutableArray array];
    dispatch_sync(_bufferQueue, ^{
        for (BufferedEvent *e in self.buffer) {
            if ([e.timestamp compare:start] != NSOrderedAscending &&
                [e.timestamp compare:end] != NSOrderedDescending) {
                [result addObject:e.event];
            }
        }
    });
    return result.count > 0 ? [result copy] : nil;
}

- (int64_t)oldestSequence {
    __block int64_t result;
    dispatch_sync(_bufferQueue, ^{
        result = self.oldestSeq;
    });
    return result;
}

- (int64_t)newestSequence {
    __block int64_t result;
    dispatch_sync(_bufferQueue, ^{
        result = self.newestSeq;
    });
    return result;
}

- (NSUInteger)eventCount {
    __block NSUInteger count;
    dispatch_sync(_bufferQueue, ^{
        count = self.buffer.count;
    });
    return count;
}

- (void)pruneExpired {
    dispatch_async(_bufferQueue, ^{
        NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-self.retentionSeconds];
        
        NSMutableArray *toRemove = [NSMutableArray array];
        for (BufferedEvent *e in self.buffer) {
            if ([e.timestamp compare:cutoff] == NSOrderedAscending) {
                [toRemove addObject:e];
            }
        }
        
        [self.buffer removeObjectsInArray:toRemove];
        
        if (self.buffer.count > 0) {
            self.oldestSeq = ((BufferedEvent *)self.buffer[0]).seq;
        } else {
            self.oldestSeq = -1;
            self.newestSeq = -1;
        }
    });
}

- (void)clear {
    dispatch_async(_bufferQueue, ^{
        [self.buffer removeAllObjects];
        self.oldestSeq = -1;
        self.newestSeq = -1;
    });
}

@end