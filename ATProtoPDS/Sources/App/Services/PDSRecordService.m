#import "PDSRecordService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Core/ATProtoBase32.h"
#import "Core/ATProtoCBORSerialization.h"
#import <CommonCrypto/CommonDigest.h>

@interface PDSRecordService ()

@end

@implementation PDSRecordService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - Record Operations

- (nullable NSDictionary *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    PDSDatabaseRecord *record = [_databasePool getRecord:uri forDid:did error:error];

    if (!record) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }

    return @{
        @"uri": record.uri,
        @"cid": record.cid,
        @"collection": record.collection,
        @"rkey": record.rkey
    };
}

- (nullable NSArray *)listRecords:(NSString *)collection
                          forDid:(NSString *)did
                           limit:(NSUInteger)limit
                          cursor:(nullable NSString *)cursor
                          error:(NSError **)error {

    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;

    NSArray<PDSDatabaseRecord *> *records = [store listRecordsForDid:did
                                                          collection:collection
                                                               limit:limit
                                                              offset:0
                                                               error:error];

    NSMutableArray *result = [NSMutableArray array];
    for (PDSDatabaseRecord *record in records) {
        [result addObject:@{
            @"uri": record.uri,
            @"cid": record.cid,
            @"collection": record.collection,
            @"rkey": record.rkey
        }];
    }

    return result;
}

- (BOOL)putRecord:(NSString *)collection
             rkey:(NSString *)rkey
            value:(NSDictionary *)value
           forDid:(NSString *)did
            error:(NSError **)error {

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

    NSError *cidError;
    // Use DAG-CBOR encoding for CID calculation to match spec
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:value error:&cidError];
    if (!cborData) {
        if (error) *error = cidError;
        return NO;
    }
    
    NSString *cidString = [self generateCIDForData:cborData error:&cidError];
    if (!cidString) {
        if (error) *error = cidError;
        return NO;
    }

    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = uri;
    record.did = did;
    record.collection = collection;
    record.rkey = rkey;
    record.cid = cidString;
    record.createdAt = [NSDate date];

    __block BOOL success = NO;
    __block NSError *blockError = nil;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store putRecord:record forDid:did error:&blockError];
    } error:nil];

    if (error && blockError) {
        *error = blockError;
    }

    return success;
}

- (BOOL)deleteRecord:(NSString *)collection
                rkey:(NSString *)rkey
              forDid:(NSString *)did
               error:(NSError **)error {

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

    __block BOOL success = NO;
    __block NSError *blockError = nil;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteRecord:uri forDid:did error:&blockError];
    } error:nil];

    if (error && blockError) {
        *error = blockError;
    }

    return success;
}

#pragma mark - Private Helpers

- (NSString *)generateCIDForData:(NSData *)data error:(NSError **)error {
    // CIDv1 = version(0x01) + codec(0x71 dag-cbor) + hash_alg(0x12 sha2-256) + hash_len(0x20) + hash
    // Prefix bytes: 0x01 0x71 0x12 0x20
    
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);

    NSMutableData *cidData = [NSMutableData dataWithCapacity:4 + CC_SHA256_DIGEST_LENGTH];
    const unsigned char prefix[] = {0x01, 0x71, 0x12, 0x20};
    [cidData appendBytes:prefix length:4];
    [cidData appendBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    // Multibase 'b' prefix + base32 encoded data
    NSString *base32 = [ATProtoBase32 encodeData:cidData];
    return [NSString stringWithFormat:@"b%@", base32];
}

@end