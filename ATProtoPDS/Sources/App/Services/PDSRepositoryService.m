#import "PDSRepositoryService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Repository/MST.h"
#import "Core/CID.h"

@implementation PDSRepositoryService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - Repo Operations

- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;
    
    // Load all records to rebuild MST
    // Assuming 10000 limit for now (should be paginated in real implementation)
    NSArray<PDSDatabaseRecord *> *records = [store listRecordsForDid:did collection:nil limit:10000 offset:0 error:error];
    
    // Always return an empty MST instead of nil if no records found or error occurs during listing,
    // so we don't crash the viewer for empty repos.
    MST *mst = [[MST alloc] init];
    if (!records) {
        return mst;
    }
    
    for (PDSDatabaseRecord *record in records) {
        if (!record.cid || !record.collection || !record.rkey) {
            continue;
        }
        
        // Parse CID from string
        CID *cid = [CID cidFromString:record.cid];
        if (cid) {
            NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
            [mst put:key valueCID:cid subKey:nil];
        }
    }
    
    return mst;
}

- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable CID *)cid error:(NSError **)error {
    MST *mst = [self loadMSTForDid:did error:error];
    if (!mst) return NO;
    
    if (cid) {
        [mst put:key valueCID:cid subKey:nil];
    } else {
        [mst delete:key];
    }
    
    NSData *cbor = [mst serializeToCBOR];
    NSData *digest = [CID sha256Digest:cbor];
    CID *repoRoot = [CID cidWithMultihash:digest codec:0x71];
    
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return NO;
    
    __block BOOL success = NO;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor updateRepoRoot:did rootCid:[repoRoot bytes] error:blockError];
    } error:error];
    
    return success;
}

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    return [_databasePool getRepoRoot:did error:error];
}

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSData *)sinceCid error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;
    return [store getRepoRootForDid:did error:error];
}

- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error {
    return NO;
}

@end
