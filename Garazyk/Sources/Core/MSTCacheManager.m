#import "Core/MSTCacheManager.h"
#import "Core/MSTAtomicReference.h"
#import "Repository/MST.h"
#import "Database/ActorStore/ActorStore.h"
#import "Core/CID.h"
#import "Repository/CBOR.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

@interface MSTCacheManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, MSTAtomicReference *> *cache;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@end

@implementation MSTCacheManager

+ (instancetype)sharedManager {
    static MSTCacheManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[MSTCacheManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.atproto.pds.mstcache", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (nullable MST *)mstForDid:(NSString *)did {
    // Fast path: dictionary lookup on serial queue, then atomic snapshot read
    __block MSTAtomicReference *ref = nil;
    dispatch_sync(self.queue, ^{
        ref = self.cache[did];
    });
    // The atomic reference provides thread-safe snapshot access via pthread_mutex
    // No need to hold the queue while reading the MST
    return [ref currentSnapshot];
}

- (void)setMST:(MST *)mst forDid:(NSString *)did {
    dispatch_sync(self.queue, ^{
        MSTAtomicReference *ref = self.cache[did];
        if (ref) {
            // Atomic swap — readers always see a consistent snapshot
            [ref swapMST:mst];
        } else {
            // Create new reference and store
            ref = [[MSTAtomicReference alloc] initWithMST:mst];
            self.cache[did] = ref;
        }
    });
}

- (void)removeMSTForDid:(NSString *)did {
    dispatch_sync(self.queue, ^{
        MSTAtomicReference *ref = self.cache[did];
        if (ref) {
            [ref clear];  // Release the MST
            [self.cache removeObjectForKey:did];
        }
    });
}

- (void)removeAllMSTs {
    dispatch_sync(self.queue, ^{
        for (MSTAtomicReference *ref in self.cache.allValues) {
            [ref clear];
        }
        [self.cache removeAllObjects];
    });
}

#pragma mark - Incremental MST Loading

+ (nullable MST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error {
    // 1. Read the current repo root CID
    NSData *rootCIDBytes = [store getRepoRootForDid:did error:nil];
    if (!rootCIDBytes) {
        PDS_LOG_INFO(@"MSTCacheManager: no repo root for %@, falling back to full rebuild", did);
        return nil;
    }

    CID *rootCID = [CID cidFromBytes:rootCIDBytes];
    if (!rootCID) {
        PDS_LOG_ERROR(@"MSTCacheManager: invalid root CID bytes for %@", did);
        return nil;
    }

    // 2. Read the commit block to get the data CID (MST root)
    NSData *commitBlockData = [store getBlockForCID:rootCID.bytes forDid:did error:nil];
    if (!commitBlockData) {
        PDS_LOG_INFO(@"MSTCacheManager: no commit block for %@, falling back", did);
        return nil;
    }

    // 3. Parse the commit to extract the data CID
    CBORValue *commitValue = [CBORValue decode:commitBlockData];
    if (!commitValue || commitValue.type != CBORTypeMap) {
        PDS_LOG_ERROR(@"MSTCacheManager: commit block is not a CBOR map for %@", did);
        return nil;
    }

    CBORValue *dataTag = commitValue.map[[CBORValue textString:@"data"]];
    if (!dataTag || dataTag.type != CBORTypeTag) {
        PDS_LOG_ERROR(@"MSTCacheManager: commit block missing 'data' tag for %@", did);
        return nil;
    }

    // The data field is a CID link: tag(42) wrapping a byte string with CID bytes
    NSData *dataCIDBytes = dataTag.tagValue.byteString;
    if (!dataCIDBytes || dataCIDBytes.length <= 1) {
        PDS_LOG_ERROR(@"MSTCacheManager: data CID bytes too short for %@", did);
        return nil;
    }

    // Skip the multibase prefix byte (0x00) to get raw CID bytes
    CID *dataCID = [CID cidFromBytes:[dataCIDBytes subdataWithRange:NSMakeRange(1, dataCIDBytes.length - 1)]];
    if (!dataCID) {
        PDS_LOG_ERROR(@"MSTCacheManager: failed to parse data CID for %@", did);
        return nil;
    }

    // 4. Read the MST root block
    NSData *mstBlockData = [store getBlockForCID:dataCID.bytes forDid:did error:nil];
    if (!mstBlockData) {
        PDS_LOG_INFO(@"MSTCacheManager: no MST root block for %@, falling back", did);
        return nil;
    }

    // 5. Deserialize the MST from CBOR
    MST *mst = [MST deserializeFromCBOR:mstBlockData];
    if (!mst) {
        PDS_LOG_ERROR(@"MSTCacheManager: CBOR deserialization failed for %@, falling back", did);
        return nil;
    }

    PDS_LOG_INFO(@"MSTCacheManager: successfully loaded MST for %@ from repo blocks", did);
    return mst;
}

@end
