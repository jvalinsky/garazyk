#import "Database/Cache/PDSRecordCache.h"
#import "Debug/PDSLogger.h"

// Cache entry structure
@interface PDSRecordCacheEntry : NSObject
@property (nonatomic, strong) NSDictionary *record;
@property (nonatomic, strong) NSString *uri;
@property (nonatomic, strong) NSString *did;
@property (nonatomic, strong) NSString *collection;
@property (nonatomic, assign) NSUInteger memorySize;
@property (nonatomic, strong) NSDate *cachedAt;
@property (nonatomic, assign) NSTimeInterval ttl;
@end

@implementation PDSRecordCacheEntry
@end

@interface PDSRecordCache ()
// Cache storage
@property (nonatomic, strong) NSMutableDictionary<NSString *, PDSRecordCacheEntry *> *storage;
@property (nonatomic, strong) NSMutableArray<NSString *> *accessOrder;  // LRU tracking
@property (nonatomic, assign) NSUInteger currentMemory;

// Statistics
@property (nonatomic, assign) NSUInteger hits;
@property (nonatomic, assign) NSUInteger misses;
@property (nonatomic, assign) NSUInteger evictions;

// Thread safety
@property (nonatomic, strong) dispatch_queue_t cacheQueue;

@end

@implementation PDSRecordCache

- (instancetype)initWithMaxEntries:(NSUInteger)maxEntries {
    return [self initWithMaxEntries:maxEntries maxMemoryBytes:0 defaultTTL:0];
}

- (instancetype)initWithMaxEntries:(NSUInteger)maxEntries
                   maxMemoryBytes:(NSUInteger)maxMemoryBytes {
    return [self initWithMaxEntries:maxEntries maxMemoryBytes:maxMemoryBytes defaultTTL:0];
}

- (instancetype)initWithMaxEntries:(NSUInteger)maxEntries
                   maxMemoryBytes:(NSUInteger)maxMemoryBytes
                        defaultTTL:(NSTimeInterval)defaultTTL {
    if ((self = [super init])) {
        _maxEntries = maxEntries > 0 ? maxEntries : 10000;
        _maxMemoryBytes = maxMemoryBytes;
        _defaultTTL = defaultTTL;
        _enabled = YES;

        _storage = [NSMutableDictionary dictionary];
        _accessOrder = [NSMutableArray array];
        _currentMemory = 0;

        _hits = 0;
        _misses = 0;
        _evictions = 0;

        _cacheQueue = dispatch_queue_create("com.atproto.pds.recordcache",
                                           DISPATCH_QUEUE_SERIAL);

        PDS_LOG_CORE_INFO(@"Record cache initialized: max=%lu, memory=%lu, ttl=%.0fs",
                         (unsigned long)_maxEntries,
                         (unsigned long)_maxMemoryBytes,
                         _defaultTTL);
    }
    return self;
}

#pragma mark - Cache Operations

- (nullable NSDictionary *)getRecordWithURI:(NSString *)uri {
    if (!self.enabled || !uri) return nil;

    __block NSDictionary *result = nil;

    dispatch_sync(self.cacheQueue, ^{
        PDSRecordCacheEntry *entry = self.storage[uri];

        if (entry) {
            // Check TTL
            if (entry.ttl > 0) {
                NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:entry.cachedAt];
                if (age > entry.ttl) {
                    // Expired
                    [self removeEntry:entry];
                    self.misses++;
                    return;
                }
            }

            // Cache hit - move to end of access order
            [self.accessOrder removeObject:uri];
            [self.accessOrder addObject:uri];
            result = entry.record;
            self.hits++;
        } else {
            self.misses++;
        }
    });

    return result;
}

- (void)setRecord:(NSDictionary *)record forURI:(NSString *)uri {
    if (!record || !uri || !self.enabled) return;

    NSString *did = [self extractDIDFromURI:uri];
    NSString *collection = [self extractCollectionFromURI:uri];

    dispatch_sync(self.cacheQueue, ^{
        // Remove existing entry if present
        PDSRecordCacheEntry *existing = self.storage[uri];
        if (existing) {
            [self removeEntry:existing];
        }

        // Create new entry
        PDSRecordCacheEntry *entry = [[PDSRecordCacheEntry alloc] init];
        entry.record = record;
        entry.uri = uri;
        entry.did = did;
        entry.collection = collection;
        entry.memorySize = [self estimateMemorySize:record];
        entry.cachedAt = [NSDate date];
        entry.ttl = self.defaultTTL;

        // Add to cache
        self.storage[uri] = entry;
        [self.accessOrder addObject:uri];
        self.currentMemory += entry.memorySize;

        // Evict if needed
        [self evictIfNeeded];
    });
}

- (void)invalidateURI:(NSString *)uri {
    if (!uri) return;

    dispatch_sync(self.cacheQueue, ^{
        PDSRecordCacheEntry *entry = self.storage[uri];
        if (entry) {
            [self removeEntry:entry];
        }
    });
}

- (void)invalidateDID:(NSString *)did {
    if (!did) return;

    dispatch_sync(self.cacheQueue, ^{
        NSMutableArray *toRemove = [NSMutableArray array];
        for (NSString *uri in self.storage) {
            PDSRecordCacheEntry *entry = self.storage[uri];
            if ([entry.did isEqualToString:did]) {
                [toRemove addObject:entry];
            }
        }
        for (PDSRecordCacheEntry *entry in toRemove) {
            [self removeEntry:entry];
        }
    });
}

- (void)invalidateCollection:(NSString *)collection did:(NSString *)did {
    if (!collection || !did) return;

    dispatch_sync(self.cacheQueue, ^{
        NSMutableArray *toRemove = [NSMutableArray array];
        for (NSString *uri in self.storage) {
            PDSRecordCacheEntry *entry = self.storage[uri];
            if ([entry.did isEqualToString:did] &&
                [entry.collection isEqualToString:collection]) {
                [toRemove addObject:entry];
            }
        }
        for (PDSRecordCacheEntry *entry in toRemove) {
            [self removeEntry:entry];
        }
    });
}

- (void)clear {
    dispatch_sync(self.cacheQueue, ^{
        [self.storage removeAllObjects];
        [self.accessOrder removeAllObjects];
        self.currentMemory = 0;
    });
}

#pragma mark - Statistics

- (NSUInteger)hitCount {
    return self.hits;
}

- (NSUInteger)missCount {
    return self.misses;
}

- (double)hitRate {
    NSUInteger total = self.hits + self.misses;
    if (total == 0) return 0.0;
    return (double)self.hits / (double)total;
}

- (NSUInteger)currentEntryCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.cacheQueue, ^{
        count = self.storage.count;
    });
    return count;
}

- (NSUInteger)currentMemoryUsage {
    return self.currentMemory;
}

- (NSUInteger)evictionCount {
    return self.evictions;
}

- (void)resetStatistics {
    dispatch_sync(self.cacheQueue, ^{
        self.hits = 0;
        self.misses = 0;
        self.evictions = 0;
    });
}

#pragma mark - Private Methods

- (void)removeEntry:(PDSRecordCacheEntry *)entry {
    [self.storage removeObjectForKey:entry.uri];
    [self.accessOrder removeObject:entry.uri];
    self.currentMemory -= entry.memorySize;
}

- (void)evictIfNeeded {
    // Evict by entry count
    while (self.accessOrder.count > self.maxEntries) {
        NSString *oldestURI = self.accessOrder.firstObject;
        PDSRecordCacheEntry *entry = self.storage[oldestURI];
        if (entry) {
            [self removeEntry:entry];
            self.evictions++;
        }
    }

    // Evict by memory limit
    if (self.maxMemoryBytes > 0) {
        while (self.currentMemory > self.maxMemoryBytes && self.accessOrder.count > 0) {
            NSString *oldestURI = self.accessOrder.firstObject;
            PDSRecordCacheEntry *entry = self.storage[oldestURI];
            if (entry) {
                [self removeEntry:entry];
                self.evictions++;
            }
        }
    }
}

- (NSUInteger)estimateMemorySize:(NSDictionary *)record {
    // Rough estimate: count characters in JSON representation
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:record options:0 error:&error];
    return jsonData ? jsonData.length : record.description.length;
}

- (NSString *)extractDIDFromURI:(NSString *)uri {
    NSArray *parts = [uri componentsSeparatedByString:@"/"];
    return parts.count > 2 ? parts[2] : @"";
}

- (NSString *)extractCollectionFromURI:(NSString *)uri {
    NSArray *parts = [uri componentsSeparatedByString:@"/"];
    return parts.count > 3 ? parts[3] : @"";
}

// Remove database-dependent methods from header (simplified cache)

@end
