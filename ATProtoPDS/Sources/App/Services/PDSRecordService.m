#import "PDSRecordService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"
#import "Core/ATProtoBase32.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoValidator.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconError.h"
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

    NSDictionary *parsedValue = @{};
    if (record.value) {
        NSData *data = [record.value dataUsingEncoding:NSUTF8StringEncoding];
        if (data) {
            parsedValue = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] ?: @{};
        }
    }

    return @{
        @"uri": record.uri,
        @"cid": record.cid,
        @"collection": record.collection,
        @"rkey": record.rkey,
        @"value": parsedValue
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
        NSDictionary *parsedValue = @{};
        if (record.value) {
            NSData *data = [record.value dataUsingEncoding:NSUTF8StringEncoding];
            if (data) {
                parsedValue = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] ?: @{};
            }
        }
        
        [result addObject:@{
            @"uri": record.uri,
            @"cid": record.cid,
            @"collection": record.collection,
            @"rkey": record.rkey,
            @"value": parsedValue
        }];
    }

    return result;
}

- (BOOL)putRecord:(NSString *)collection
             rkey:(NSString *)rkey
            value:(NSDictionary *)value
           forDid:(NSString *)did
   validationMode:(PDSValidationMode)mode
            error:(NSError **)error {
    // Validate collection NSID format
    NSError *nsidError = nil;
    if (![ATProtoValidator validateNSID:collection error:&nsidError]) {
        PDS_LOG_ERROR(@"[PDSRecordService] Invalid collection NSID: %@", collection);
        if (error) *error = nsidError;
        return NO;
    }

    // Lexicon validation
    if (mode != PDSValidationModeOff) {
        ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc]
            initWithRegistry:[ATProtoLexiconRegistry sharedRegistry]];

        // Map PDSValidationMode to ATProtoValidationMode
        ATProtoValidationMode validationMode;
        switch (mode) {
            case PDSValidationModeRequired:
                validationMode = ATProtoValidationModeRequired;
                break;
            case PDSValidationModeOptimistic:
                validationMode = ATProtoValidationModeOptimistic;
                break;
            case PDSValidationModeOff:
                validationMode = ATProtoValidationModeOff;
                break;
        }

        NSError *validationError = nil;
        if (![validator validateRecord:value
                            collection:collection
                                  mode:validationMode
                                 error:&validationError]) {
            PDS_LOG_ERROR(@"[PDSRecordService] Lexicon validation failed for %@: %@",
                          collection, validationError.localizedDescription);
            if (error) *error = validationError;
            return NO;
        }

        PDS_LOG_DEBUG(@"[PDSRecordService] Lexicon validation passed for %@", collection);
    }

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

    // Store serialized JSON value
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (jsonData) {
        record.value = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

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

- (BOOL)putRecord:(NSString *)collection
             rkey:(NSString *)rkey
            value:(NSDictionary *)value
           forDid:(NSString *)did
            error:(NSError **)error {
    // Convenience method with default required validation
    return [self putRecord:collection
                      rkey:rkey
                     value:value
                    forDid:did
            validationMode:PDSValidationModeRequired
                     error:error];
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

- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) {
        PDS_LOG_DB_ERROR(@"[PDSRecordService] Failed to get store for DID: %@", did);
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.recordservice" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to get store"}];
        return nil;
    }
    
    __block NSMutableArray *results = [NSMutableArray array];
    __block NSInteger totalCount = 0;
    __block NSError *blockError = nil;
    
    [store readWithBlock:^(id<PDSActorStoreReader> reader) {
        PDSActorStore *actorStore = (PDSActorStore *)reader;
        NSString *sql = @"SELECT collection, COUNT(*) as count FROM records GROUP BY collection ORDER BY collection";
        sqlite3_stmt *stmt = [actorStore prepareStatement:sql error:&blockError];
        
        if (stmt) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *colName = (const char *)sqlite3_column_text(stmt, 0);
                int count = sqlite3_column_int(stmt, 1);
                
                if (colName) {
                    [results addObject:@{
                        @"collection": [NSString stringWithUTF8String:colName],
                        @"count": @(count)
                    }];
                    totalCount += count;
                }
            }
            [actorStore finalizeStatement:stmt];
            if (blockError) {
                PDS_LOG_DB_ERROR(@"[PDSRecordService] Failed to prepare stats statement: %@", blockError);
            }
        }
    } error:&blockError];
    
    if (blockError) {
        PDS_LOG_DB_ERROR(@"[PDSRecordService] Error during stats read: %@", blockError);
        if (error) *error = blockError;
        return nil;
    }
    
    return @{
        @"did": did,
        @"collections": results,
        @"recordCount": @(totalCount)
    };
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
