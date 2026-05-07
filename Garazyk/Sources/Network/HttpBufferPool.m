#import "HttpBufferPool.h"
#import "Compat/PDSTypes.h"
#import "HttpRequest.h"
#import "HttpResponse.h"

static const NSUInteger kDefaultMaxPoolSize = 64;
static const NSUInteger kDefaultBufferSize = 4096;

@interface HttpBufferPool ()

@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<NSMutableData *> *> *bufferPools;
@property (nonatomic, strong) NSMutableArray<HttpRequest *> *requestPool;
@property (nonatomic, strong) NSMutableArray<HttpResponse *> *responsePool;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t poolQueue;
@property (nonatomic, strong) NSArray<NSNumber *> *sizeClasses;

@end

@implementation HttpBufferPool

+ (instancetype)sharedPool {
    static HttpBufferPool *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[HttpBufferPool alloc] init];
    });
    return shared;
}

- (instancetype)init {
    return [self initWithSizeClasses:@[@(256), @(1024), @(4096), @(16384)]];
}

- (instancetype)initWithSizeClasses:(NSArray<NSNumber *> *)sizeClasses {
    self = [super init];
    if (self) {
        _sizeClasses = [sizeClasses sortedArrayUsingSelector:@selector(compare:)];
        _bufferPools = [NSMutableDictionary dictionaryWithCapacity:sizeClasses.count];
        _requestPool = [NSMutableArray array];
        _responsePool = [NSMutableArray array];
        _poolQueue = dispatch_queue_create("com.atproto.pds.bufferpool", DISPATCH_QUEUE_SERIAL);
        _maxPoolSize = kDefaultMaxPoolSize;

        for (NSNumber *size in _sizeClasses) {
            _bufferPools[size] = [NSMutableArray array];
        }
        
        [self setupAutoPrune];
    }
    return self;
}

- (void)setupAutoPrune {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_SEC)), 
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        HttpBufferPool *strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf autoPrune];
            [strongSelf setupAutoPrune];
        }
    });
}

- (void)autoPrune {
    dispatch_async(self.poolQueue, ^{
        for (NSMutableArray *pool in self.bufferPools.allValues) {
            if (pool.count > 4) { // Keep a small minimum
                [pool removeObjectsInRange:NSMakeRange(0, pool.count / 2)];
            }
        }
        if (self.requestPool.count > 4) {
            [self.requestPool removeObjectsInRange:NSMakeRange(0, self.requestPool.count / 2)];
        }
        if (self.responsePool.count > 4) {
            [self.responsePool removeObjectsInRange:NSMakeRange(0, self.responsePool.count / 2)];
        }
    });
}

- (NSMutableData *)acquireBufferOfSize:(NSUInteger)size {
    if (size == 0) {
        return [NSMutableData data];
    }

    __block NSMutableData *buffer = nil;
    __block NSNumber *bestSize = nil;

    dispatch_sync(self.poolQueue, ^{
        for (NSNumber *sizeClass in self.sizeClasses) {
            if ([sizeClass unsignedIntegerValue] >= size) {
                bestSize = sizeClass;
                break;
            }
        }

        if (!bestSize) {
            bestSize = @(kDefaultBufferSize);
            while ([bestSize unsignedIntegerValue] < size) {
                bestSize = @([bestSize unsignedIntegerValue] * 2);
            }
        }

        NSMutableArray *pool = self.bufferPools[bestSize];
        if (pool.count > 0) {
            buffer = pool.lastObject;
            [pool removeLastObject];
            [buffer setLength:0];
        }
    });

    if (!buffer) {
        buffer = [NSMutableData dataWithCapacity:[bestSize unsignedIntegerValue]];
    }

    return buffer;
}

- (void)releaseBuffer:(NSMutableData *)buffer {
    if (!buffer) return;

    dispatch_sync(self.poolQueue, ^{
        NSUInteger length = buffer.length;

        NSNumber *matchingSize = nil;
        for (NSNumber *sizeClass in self.sizeClasses) {
            if ([sizeClass unsignedIntegerValue] >= length) {
                matchingSize = sizeClass;
                break;
            }
        }

        if (!matchingSize) {
            matchingSize = @(kDefaultBufferSize);
        }

        NSMutableArray *pool = self.bufferPools[matchingSize];
        if (pool.count < self.maxPoolSize) {
            [buffer setLength:0];
            [pool addObject:buffer];
        }
    });
}

- (nullable HttpRequest *)acquireRequest {
    __block HttpRequest *request = nil;

    dispatch_sync(self.poolQueue, ^{
        if (self.requestPool.count > 0) {
            request = self.requestPool.lastObject;
            [self.requestPool removeLastObject];
        }
    });

    return request;
}

- (void)releaseRequest:(HttpRequest *)request {
    if (!request) return;

    dispatch_sync(self.poolQueue, ^{
        if (self.requestPool.count < self.maxPoolSize) {
            [self.requestPool addObject:request];
        }
    });
}

- (nullable HttpResponse *)acquireResponse {
    __block HttpResponse *response = nil;

    dispatch_sync(self.poolQueue, ^{
        if (self.responsePool.count > 0) {
            response = self.responsePool.lastObject;
            [self.responsePool removeLastObject];
        }
    });

    return response;
}

- (void)releaseResponse:(HttpResponse *)response {
    if (!response) return;

    dispatch_sync(self.poolQueue, ^{
        if (self.responsePool.count < self.maxPoolSize) {
            [self.responsePool addObject:response];
        }
    });
}

- (NSUInteger)bufferCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.poolQueue, ^{
        for (NSMutableArray *pool in self.bufferPools.allValues) {
            count += pool.count;
        }
    });
    return count;
}

- (NSUInteger)requestCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.poolQueue, ^{
        count = self.requestPool.count;
    });
    return count;
}

- (NSUInteger)responseCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.poolQueue, ^{
        count = self.responsePool.count;
    });
    return count;
}

- (void)drainPools {
    dispatch_sync(self.poolQueue, ^{
        for (NSMutableArray *pool in self.bufferPools.allValues) {
            [pool removeAllObjects];
        }
        [self.requestPool removeAllObjects];
        [self.responsePool removeAllObjects];
    });
}

@end
