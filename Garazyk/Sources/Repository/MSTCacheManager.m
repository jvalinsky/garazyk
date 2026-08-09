// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Repository/MSTCacheManager.h"
#import "Repository/MSTAtomicReference.h"
#import "Repository/MST.h"
#import "Database/ActorStore/ActorStore.h"
#import "Core/CID.h"
#import "Core/CBOR.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"

@interface ATProtoMSTCacheManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, ATProtoMSTAtomicReference *> *cache;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@end

@implementation ATProtoMSTCacheManager

+ (instancetype)sharedManager {
    static ATProtoMSTCacheManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ATProtoMSTCacheManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
        // Use a concurrent queue with barrier writes for better read parallelism.
        // Multiple DIDs can read their MSTs concurrently without blocking each other.
        _queue = dispatch_queue_create("com.atproto.pds.mstcache", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (nullable ATProtoMST *)mstForDid:(NSString *)did {
    // Fast path: concurrent read from dictionary, then atomic snapshot read
    __block ATProtoMSTAtomicReference *ref = nil;
    dispatch_sync(self.queue, ^{
        ref = self.cache[did];
    });
    // The atomic reference provides thread-safe snapshot access via pthread_mutex
    // No need to hold the queue while reading the ATProtoMST
    return [ref currentSnapshot];
}

- (void)setMST:(ATProtoMST *)mst forDid:(NSString *)did {
    // Barrier write: exclusive access while updating the cache dictionary
    dispatch_barrier_sync(self.queue, ^{
        ATProtoMSTAtomicReference *ref = self.cache[did];
        if (ref) {
            // Atomic swap — readers always see a consistent snapshot
            [ref swapMST:mst];
        } else {
            // Create new reference and store
            ref = [[ATProtoMSTAtomicReference alloc] initWithMST:mst];
            self.cache[did] = ref;
        }
    });
}

- (void)removeMSTForDid:(NSString *)did {
    // Barrier write: exclusive access while removing from cache
    dispatch_barrier_sync(self.queue, ^{
        ATProtoMSTAtomicReference *ref = self.cache[did];
        if (ref) {
            [ref clear];  // Release the ATProtoMST
            [self.cache removeObjectForKey:did];
        }
    });
}

- (void)removeAllMSTs {
    // Barrier write: exclusive access while clearing cache
    dispatch_barrier_sync(self.queue, ^{
        for (ATProtoMSTAtomicReference *ref in self.cache.allValues) {
            [ref clear];
        }
        [self.cache removeAllObjects];
    });
}

#pragma mark - Incremental ATProtoMST Loading

+ (nullable ATProtoMST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error {
    // 1. Read the current repo root ATProtoCID
    NSData *rootCIDBytes = [store getRepoRootForDid:did error:nil];
    if (!rootCIDBytes) {
        GZ_LOG_INFO(@"MSTCacheManager: no repo root for %@, falling back to full rebuild", did);
        return nil;
    }

    ATProtoCID *rootCID = [ATProtoCID cidFromBytes:rootCIDBytes];
    if (!rootCID) {
        GZ_LOG_ERROR(@"MSTCacheManager: invalid root CID bytes for %@", did);
        return nil;
    }

    // 2. Read the commit block to get the data ATProtoCID (ATProtoMST root)
    NSData *commitBlockData = [store getBlockForCID:rootCID.bytes forDid:did error:nil];
    if (!commitBlockData) {
        GZ_LOG_INFO(@"MSTCacheManager: no commit block for %@, falling back", did);
        return nil;
    }

    // 3. Parse the commit to extract the data ATProtoCID
    ATProtoCBORValue *commitValue = [ATProtoCBORValue decode:commitBlockData];
    if (!commitValue || commitValue.type != CBORTypeMap) {
        GZ_LOG_ERROR(@"MSTCacheManager: commit block is not a CBOR map for %@", did);
        return nil;
    }

    ATProtoCBORValue *dataTag = commitValue.map[[ATProtoCBORValue textString:@"data"]];
    if (!dataTag || dataTag.type != CBORTypeTag) {
        GZ_LOG_ERROR(@"MSTCacheManager: commit block missing 'data' tag for %@", did);
        return nil;
    }

    // The data field is a ATProtoCID link: tag(42) wrapping a byte string with ATProtoCID bytes
    NSData *dataCIDBytes = dataTag.tagValue.byteString;
    if (!dataCIDBytes || dataCIDBytes.length <= 1) {
        GZ_LOG_ERROR(@"MSTCacheManager: data CID bytes too short for %@", did);
        return nil;
    }

    // Skip the multibase prefix byte (0x00) to get raw ATProtoCID bytes
    ATProtoCID *dataCID = [ATProtoCID cidFromBytes:[dataCIDBytes subdataWithRange:NSMakeRange(1, dataCIDBytes.length - 1)]];
    if (!dataCID) {
        GZ_LOG_ERROR(@"MSTCacheManager: failed to parse data CID for %@", did);
        return nil;
    }

    // 4. Read the ATProtoMST root block
    NSData *mstBlockData = [store getBlockForCID:dataCID.bytes forDid:did error:nil];
    if (!mstBlockData) {
        GZ_LOG_INFO(@"MSTCacheManager: no MST root block for %@, falling back", did);
        return nil;
    }

    // 5. Deserialize the ATProtoMST from CBOR
    ATProtoMST *mst = [ATProtoMST deserializeFromCBOR:mstBlockData];
    if (!mst) {
        GZ_LOG_ERROR(@"MSTCacheManager: CBOR deserialization failed for %@, falling back", did);
        return nil;
    }

    GZ_LOG_INFO(@"MSTCacheManager: successfully loaded MST for %@ from repo blocks", did);
    return mst;
}

@end
