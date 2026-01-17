#import "PLCMockStore.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCMetrics.h"

@interface PLCMockStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<PLCOperation *> *> *storage;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation PLCMockStore

- (instancetype)init {
    self = [super init];
    if (self) {
        _storage = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.atproto.pds.plcmockstore", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (nullable NSArray<PLCOperation *> *)getHistoryForDID:(NSString *)did error:(NSError **)error {
    __block NSArray<PLCOperation *> *history = nil;
    dispatch_sync(self.queue, ^{
        history = self.storage[did];
    });
    
    if (history) {
        [[PLCMetrics sharedMetrics] recordMemcacheHit];
    } else {
        [[PLCMetrics sharedMetrics] recordMemcacheMiss];
    }
    
    return history;
}

- (BOOL)appendOperation:(PLCOperation *)op error:(NSError **)error {
    if (!op.did) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCMockStore" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Operation missing DID"}];
        }
        return NO;
    }

    dispatch_sync(self.queue, ^{
        NSMutableArray<PLCOperation *> *history = self.storage[op.did];
        if (!history) {
            history = [NSMutableArray array];
            self.storage[op.did] = history;
        }
        [history addObject:op];
    });

    return YES;
}

- (nullable NSArray<NSString *> *)getAllDIDsWithError:(NSError **)error {
    __block NSArray<NSString *> *keys = nil;
    dispatch_sync(self.queue, ^{
        keys = [self.storage.allKeys copy];
    });
    return keys ?: @[];
}

@end
