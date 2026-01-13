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
    if (!records) return nil;
    
    MST *mst = [[MST alloc] init];
    for (PDSDatabaseRecord *record in records) {
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
    __block NSError *innerError = nil;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
        success = [transactor updateRepoRoot:did rootCid:[repoRoot bytes] error:&innerError];
    } error:error];
    
    if (innerError && error) *error = innerError;
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

- (nullable NSData *)getRecordWithProof:(NSString *)did
                             collection:(NSString *)collection
                                   rkey:(NSString *)rkey
                                  error:(NSError **)error {
    // Get the actor store for this DID
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;
    
    // Get the record
    NSString *key = [NSString stringWithFormat:@"%@/%@", collection, rkey];
    PDSDatabaseRecord *record = [store getRecordByKey:did collection:collection rkey:rkey error:error];
    if (!record) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }
    
    // Build a CAR file with the record
    // CAR format: header + blocks
    // Header: DAG-CBOR encoded {version: 1, roots: [rootCid]}
    
    NSMutableData *carData = [NSMutableData data];
    
    // Get the record CID
    CID *recordCid = [CID cidFromString:record.cid];
    if (!recordCid) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRepositoryService"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid record CID"}];
        }
        return nil;
    }
    
    // For a minimal CAR, we include:
    // 1. CAR header with the record CID as root
    // 2. The record block itself
    
    // Build CAR header: {version: 1, roots: [cid]}
    // Simplified CBOR encoding for header
    NSData *cidBytes = [recordCid bytes];
    
    // Manual minimal CAR v1 header construction
    // Map with 2 keys: "roots" and "version"
    NSMutableData *headerData = [NSMutableData data];
    
    // CBOR map with 2 items (0xa2)
    uint8_t mapHeader = 0xa2;
    [headerData appendBytes:&mapHeader length:1];
    
    // Key "roots" (0x65 = text string length 5)
    uint8_t rootsKeyLen = 0x65;
    [headerData appendBytes:&rootsKeyLen length:1];
    [headerData appendData:[@"roots" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Value: array with 1 CID (0x81 = array length 1)
    uint8_t arrayHeader = 0x81;
    [headerData appendBytes:&arrayHeader length:1];
    
    // CID as CBOR tag 42 + bytes
    uint8_t cidTag = 0xd8; // tag in next byte
    uint8_t cidTagValue = 0x2a; // 42
    [headerData appendBytes:&cidTag length:1];
    [headerData appendBytes:&cidTagValue length:1];
    
    // CID bytes with length prefix
    // Add null byte prefix for CIDv1 in CBOR
    NSMutableData *cidWithPrefix = [NSMutableData dataWithBytes:"\x00" length:1];
    [cidWithPrefix appendData:cidBytes];
    
    if (cidWithPrefix.length < 24) {
        uint8_t bytesHeader = 0x40 + cidWithPrefix.length; // bytes major type + length
        [headerData appendBytes:&bytesHeader length:1];
    } else {
        uint8_t bytesHeader = 0x58; // bytes with 1-byte length
        [headerData appendBytes:&bytesHeader length:1];
        uint8_t len = (uint8_t)cidWithPrefix.length;
        [headerData appendBytes:&len length:1];
    }
    [headerData appendData:cidWithPrefix];
    
    // Key "version" (0x67 = text string length 7)
    uint8_t versionKeyLen = 0x67;
    [headerData appendBytes:&versionKeyLen length:1];
    [headerData appendData:[@"version" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Value: 1 (0x01)
    uint8_t versionValue = 0x01;
    [headerData appendBytes:&versionValue length:1];
    
    // Write header length as varint
    uint64_t headerLen = headerData.length;
    NSMutableData *varintData = [NSMutableData data];
    while (headerLen >= 0x80) {
        uint8_t byte = (headerLen & 0x7F) | 0x80;
        [varintData appendBytes:&byte length:1];
        headerLen >>= 7;
    }
    uint8_t finalByte = (uint8_t)headerLen;
    [varintData appendBytes:&finalByte length:1];
    
    [carData appendData:varintData];
    [carData appendData:headerData];
    
    // Add record block: CID + data
    // For now, we don't have the raw block data, so return what we have
    // A full implementation would store and retrieve the actual DAG-CBOR block
    
    // The record value as JSON -> CBOR would go here
    // For now, this CAR is incomplete but structurally valid
    
    return carData;
}

@end
