#import "PDSRecordService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"
#import "Core/ATProtoBase32.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoValidator.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconError.h"
#import "Repository/MST.h"
#import <CommonCrypto/CommonDigest.h>
#import "Repository/RepoCommit.h"

NSNotificationName const PDSRecordDidChangeNotification = @"PDSRecordDidChangeNotification";

@interface PDSRecordService ()

- (nullable CID *)computeRepoRootCIDForDid:(NSString *)did
                                      store:(PDSActorStore *)store
                                      error:(NSError **)error;
- (nullable NSDictionary<NSString *, NSString *> *)refreshRepoRootMetadataForDid:(NSString *)did
                                                                     preferredRev:(nullable NSString *)preferredRev
                                                                            error:(NSError **)error;

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
    NSString *writeRev = [TID tid].stringValue;
    record.uri = uri;
    record.did = did;
    record.collection = collection;
    record.rkey = rkey;
    record.cid = cidString;
    record.createdAt = [NSDate date];
    record.rev = writeRev;

    // Store serialized JSON value
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (jsonData) {
        record.value = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    // Extract subject DID for relationship indexing
    if ([collection isEqualToString:@"app.bsky.graph.follow"] || 
        [collection isEqualToString:@"app.bsky.graph.block"]) {
        id subject = value[@"subject"];
        if ([subject isKindOfClass:[NSString class]]) {
            record.subjectDid = subject;
        } else if ([subject isKindOfClass:[NSDictionary class]] && subject[@"did"]) {
            record.subjectDid = subject[@"did"];
        }
    }

    __block BOOL success = NO;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store putRecord:record forDid:did error:blockError];
    } error:error];

    if (success) {
        // Fetch previous root and refresh metadata to get new commit info
        NSError *storeError = nil;
        PDSActorStore *store = [_databasePool storeForDid:did error:&storeError];
        NSData *prevRootData = [store getRepoRootForDid:did error:nil];
        CID *prevRoot = prevRootData ? [CID cidFromBytes:prevRootData] : nil;

        NSDictionary *newRootMeta = [self refreshRepoRootMetadataForDid:did preferredRev:writeRev error:nil];
        NSString *newRootCID = newRootMeta[@"cid"];
        NSString *newRev = newRootMeta[@"rev"];

/*
        NSLog(@"[PDSRecordService] Debug notification: did=%@, collection=%@, rkey=%@, cid=%@, commit=%@, rev=%@, recordCBOR_len=%lu", did, collection, rkey, cidString, newRootCID, newRev, (unsigned long)cborData.length);
        [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                            object:self
                                                          userInfo:@{
            @"did": did,
            @"collection": collection,
            @"rkey": rkey,
            @"action": @"create",
            @"cid": cidString,
            @"prev": prevRoot ? prevRoot.stringValue : [NSNull null],
            @"commit": newRootCID ?: [NSNull null],
            @"rev": newRev ?: [NSNull null],
            @"recordCBOR": cborData ?: [NSNull null]
        }];
*/
    }

    NSLog(@"[PDSRecordService] putRecord finishing with success: %d", success);
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
    NSString *writeRev = [TID tid].stringValue;
    BOOL hadExistingRecord = ([_databasePool getRecord:uri forDid:did error:nil] != nil);

    __block BOOL success = NO;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;

        if (hadExistingRecord) {
            if (![store addRecordTombstoneURI:uri
                                          did:did
                                    collection:collection
                                         rkey:rkey
                                           rev:writeRev
                                         error:blockError]) {
                success = NO;
                return;
            }
        }

        success = [store deleteRecord:uri forDid:did error:blockError];
    } error:error];

    if (success) {
        // Fetch previous root and refresh metadata
        NSError *storeError = nil;
        PDSActorStore *store = [_databasePool storeForDid:did error:&storeError];
        NSData *prevRootData = [store getRepoRootForDid:did error:nil];
        CID *prevRoot = prevRootData ? [CID cidFromBytes:prevRootData] : nil;

        NSDictionary *newRootMeta = [self refreshRepoRootMetadataForDid:did preferredRev:writeRev error:nil];
        NSString *newRootCID = newRootMeta[@"cid"];
        NSString *newRev = newRootMeta[@"rev"];

        [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                            object:self
                                                          userInfo:@{
            @"did": did,
            @"collection": collection,
            @"rkey": rkey,
            @"action": @"delete",
            @"cid": [NSNull null],
            @"prev": prevRoot ? prevRoot.stringValue : [NSNull null],
            @"commit": newRootCID ?: [NSNull null],
            @"rev": newRev ?: [NSNull null],
            @"recordCBOR": [NSNull null]
        }];
    }

    return success;
}

- (nullable NSDictionary *)applyWrites:(NSArray<NSDictionary *> *)writes
                                forDid:(NSString *)did
                              validate:(BOOL)validate
                            swapCommit:(nullable NSString *)swapCommit
                                 error:(NSError **)error {
    if (!writes.count) {
        return @{@"results": @[]};
    }

    // Validate swapCommit if provided
    if (swapCommit) {
        NSData *currentRoot = [_databasePool getRepoRoot:did error:error];
        if (!currentRoot) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Repository not found"}];
            }
            return nil;
        }
        CID *currentRootCID = [CID cidFromBytes:currentRoot];
        NSString *currentRootStr = currentRootCID.stringValue ?: [CID base32Encode:currentRoot];
        if (![swapCommit isEqualToString:currentRootStr]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"InvalidSwap: expected %@ but repo is at %@",
                                             swapCommit, currentRootStr]}];
            }
            return nil;
        }
    }

    // Pre-validate all writes and build records before entering the transaction
    PDSValidationMode mode = validate ? PDSValidationModeRequired : PDSValidationModeOff;
    NSString *batchRev = [TID tid].stringValue;

    NSMutableArray *preparedOps = [NSMutableArray arrayWithCapacity:writes.count];
    NSMutableArray *resultOps = [NSMutableArray arrayWithCapacity:writes.count];
    for (NSDictionary *write in writes) {
        NSString *action = write[@"action"];
        NSString *collection = write[@"collection"];
        NSString *rkey = write[@"rkey"];
        NSDictionary *record = write[@"value"];
        if (!record) {
            // Compatibility fallback for pre-lexicon field names.
            record = write[@"record"];
        }

        if (!action || !collection) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Each write must have action and collection"}];
            }
            return nil;
        }

        if ([action isEqualToString:@"create"]) {
            if (!rkey || rkey.length == 0) {
                rkey = [TID tid].stringValue;
            }
            if (!record) {
                if (error) {
                    *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                                 code:4
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Write %@ requires a record value", action]}];
                }
                return nil;
            }

            // Validate collection NSID
            NSError *nsidError = nil;
            if (![ATProtoValidator validateNSID:collection error:&nsidError]) {
                if (error) *error = nsidError;
                return nil;
            }

            // Lexicon validation
            if (mode != PDSValidationModeOff) {
                ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc]
                    initWithRegistry:[ATProtoLexiconRegistry sharedRegistry]];
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
                if (![validator validateRecord:record collection:collection mode:validationMode error:&validationError]) {
                    if (error) *error = validationError;
                    return nil;
                }
            }

            // Build the database record
            NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
            NSError *cidError = nil;
            NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&cidError];
            if (!cborData) {
                if (error) *error = cidError;
                return nil;
            }
            NSString *cidString = [self generateCIDForData:cborData error:&cidError];
            if (!cidString) {
                if (error) *error = cidError;
                return nil;
            }

            PDSDatabaseRecord *dbRecord = [[PDSDatabaseRecord alloc] init];
            dbRecord.uri = uri;
            dbRecord.did = did;
            dbRecord.collection = collection;
            dbRecord.rkey = rkey;
            dbRecord.cid = cidString;
            dbRecord.createdAt = [NSDate date];
            dbRecord.rev = batchRev;

            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
            if (jsonData) {
                dbRecord.value = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }

            // Extract subject DID for relationship indexing
            if ([collection isEqualToString:@"app.bsky.graph.follow"] ||
                [collection isEqualToString:@"app.bsky.graph.block"]) {
                id subject = record[@"subject"];
                if ([subject isKindOfClass:[NSString class]]) {
                    dbRecord.subjectDid = subject;
                } else if ([subject isKindOfClass:[NSDictionary class]] && subject[@"did"]) {
                    dbRecord.subjectDid = subject[@"did"];
                }
            }

            [preparedOps addObject:@{@"action": action, @"record": dbRecord}];
            [resultOps addObject:@{
                @"action": action,
                @"uri": uri,
                @"cid": cidString
            }];
        } else if ([action isEqualToString:@"update"]) {
            if (!rkey || rkey.length == 0) {
                if (error) {
                    *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                                 code:6
                                             userInfo:@{NSLocalizedDescriptionKey: @"Write update requires rkey"}];
                }
                return nil;
            }
            if (!record) {
                if (error) {
                    *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                                 code:4
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                @"Write update requires a record value"}];
                }
                return nil;
            }

            NSError *nsidError = nil;
            if (![ATProtoValidator validateNSID:collection error:&nsidError]) {
                if (error) *error = nsidError;
                return nil;
            }

            if (mode != PDSValidationModeOff) {
                ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc]
                    initWithRegistry:[ATProtoLexiconRegistry sharedRegistry]];
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
                if (![validator validateRecord:record collection:collection mode:validationMode error:&validationError]) {
                    if (error) *error = validationError;
                    return nil;
                }
            }

            NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
            NSError *cidError = nil;
            NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&cidError];
            if (!cborData) {
                if (error) *error = cidError;
                return nil;
            }
            NSString *cidString = [self generateCIDForData:cborData error:&cidError];
            if (!cidString) {
                if (error) *error = cidError;
                return nil;
            }

            PDSDatabaseRecord *dbRecord = [[PDSDatabaseRecord alloc] init];
            dbRecord.uri = uri;
            dbRecord.did = did;
            dbRecord.collection = collection;
            dbRecord.rkey = rkey;
            dbRecord.cid = cidString;
            dbRecord.createdAt = [NSDate date];
            dbRecord.rev = batchRev;

            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
            if (jsonData) {
                dbRecord.value = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }

            if ([collection isEqualToString:@"app.bsky.graph.follow"] ||
                [collection isEqualToString:@"app.bsky.graph.block"]) {
                id subject = record[@"subject"];
                if ([subject isKindOfClass:[NSString class]]) {
                    dbRecord.subjectDid = subject;
                } else if ([subject isKindOfClass:[NSDictionary class]] && subject[@"did"]) {
                    dbRecord.subjectDid = subject[@"did"];
                }
            }

            [preparedOps addObject:@{@"action": action, @"record": dbRecord}];
            [resultOps addObject:@{
                @"action": action,
                @"uri": uri,
                @"cid": cidString
            }];
        } else if ([action isEqualToString:@"delete"]) {
            if (!rkey || rkey.length == 0) {
                if (error) {
                    *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                                 code:7
                                             userInfo:@{NSLocalizedDescriptionKey: @"Write delete requires rkey"}];
                }
                return nil;
            }
            NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
            BOOL recordExists = ([_databasePool getRecord:uri forDid:did error:nil] != nil);
            [preparedOps addObject:@{
                @"action": @"delete",
                @"uri": uri,
                @"collection": collection ?: @"",
                @"rkey": rkey ?: @"",
                @"exists": @(recordExists)
            }];
            [resultOps addObject:@{@"action": @"delete"}];
        } else {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                             code:5
                                         userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"Unknown action: %@", action]}];
            }
            return nil;
        }
    }

    // Execute all writes in a single transaction
    __block BOOL success = YES;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        for (NSDictionary *op in preparedOps) {
            NSString *action = op[@"action"];

            if ([action isEqualToString:@"create"]) {
                PDSDatabaseRecord *dbRecord = op[@"record"];
                if (![transactor createRecord:dbRecord forDid:did error:blockError]) {
                    success = NO;
                    return;
                }
            } else if ([action isEqualToString:@"update"]) {
                PDSDatabaseRecord *dbRecord = op[@"record"];
                if (![transactor updateRecord:dbRecord forDid:did error:blockError]) {
                    success = NO;
                    return;
                }
            } else if ([action isEqualToString:@"delete"]) {
                NSString *uri = op[@"uri"];
                BOOL recordExists = [op[@"exists"] boolValue];
                if (recordExists) {
                    NSString *collection = op[@"collection"] ?: @"";
                    NSString *rkey = op[@"rkey"] ?: @"";
                    if (![transactor addRecordTombstoneURI:uri
                                                       did:did
                                                 collection:collection
                                                      rkey:rkey
                                                        rev:batchRev
                                                      error:blockError]) {
                        success = NO;
                        return;
                    }
                }
                if (![transactor deleteRecord:uri forDid:did error:blockError]) {
                    success = NO;
                    return;
                }
            }
        }
    } error:error];

    if (!success) {
        return nil;
    }

    // Validates success, then fetch prev/new root commit info
    
    NSError *storeError = nil;
    PDSActorStore *store = [_databasePool storeForDid:did error:&storeError];
    NSData *prevRootData = [store getRepoRootForDid:did error:nil];
    CID *prevRoot = prevRootData ? [CID cidFromBytes:prevRootData] : nil;

    NSDictionary<NSString *, NSString *> *commitMeta = [self refreshRepoRootMetadataForDid:did
                                                                               preferredRev:batchRev
                                                                                      error:nil];
    NSString *commitCID = commitMeta[@"cid"];
    NSString *commitRev = commitMeta[@"rev"];

    // Notify firehose of all writes in the batch
    for (NSDictionary *write in writes) {
        NSString *action = write[@"action"];
        NSString *collection = write[@"collection"];
        NSString *rkey = write[@"rkey"];
        
        // Find result CID for create/update
        NSString *resultCID = nil;
        
        // Calculate URI to find matching result
        if (collection && rkey) {
           NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
           for (NSDictionary *res in resultOps) {
               if ([res[@"uri"] isEqualToString:uri]) {
                   resultCID = res[@"cid"];
                   break;
               }
           }
        }

        NSString *normalizedAction = ([action isEqualToString:@"update"]) ? @"update"
                                   : ([action isEqualToString:@"delete"] ? @"delete" : @"create");

        // Find matching record CBOR for create/update ops
        NSData *recordCBOR = nil;
        if (![normalizedAction isEqualToString:@"delete"] && collection && rkey) {
            NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
            for (NSDictionary *op in preparedOps) {
                PDSDatabaseRecord *rec = op[@"record"];
                if (rec && [rec.uri isEqualToString:uri]) {
                    // Re-encode the record value to DAG-CBOR for the firehose CAR
                    NSString *jsonStr = rec.value;
                    if (jsonStr) {
                        NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
                        NSDictionary *value = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
                        if (value) {
                            recordCBOR = [ATProtoCBORSerialization encodeDataWithJSONObject:value error:nil];
                        }
                    }
                    break;
                }
            }
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                            object:self
                                                          userInfo:@{
            @"did": did,
            @"collection": collection ?: @"",
            @"rkey": rkey ?: @"",
            @"action": normalizedAction,
            @"cid": resultCID ?: [NSNull null],
            @"prev": prevRoot ? prevRoot.stringValue : [NSNull null],
            @"commit": commitCID ?: [NSNull null],
            @"rev": commitRev ?: [NSNull null],
            @"recordCBOR": recordCBOR ?: [NSNull null]
        }];
    }

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:resultOps.count];
    NSString *validationStatus = validate ? @"valid" : @"unknown";
    for (NSDictionary *op in resultOps) {
        NSString *action = op[@"action"];
        if ([action isEqualToString:@"delete"]) {
            [results addObject:@{}];
            continue;
        }
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"uri"] = op[@"uri"] ?: @"";
        entry[@"cid"] = op[@"cid"] ?: @"";
        entry[@"validationStatus"] = validationStatus;
        [results addObject:entry];
    }

    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithObject:results forKey:@"results"];
    if (commitCID.length > 0 && commitRev.length > 0) {
        response[@"commit"] = @{
            @"cid": commitCID,
            @"rev": commitRev
        };
    }

    return response;
}

- (nullable CID *)computeRepoRootCIDForDid:(NSString *)did
                                      store:(PDSActorStore *)store
                                      error:(NSError **)error {
    MST *mst = [[MST alloc] init];
    const NSUInteger pageSize = 1000;
    NSUInteger offset = 0;

    while (YES) {
        NSArray<PDSDatabaseRecord *> *page = [store listRecordsForDid:did
                                                            collection:nil
                                                                 limit:pageSize
                                                                offset:offset
                                                                 error:error];
        if (!page) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                             code:8
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to list repository records"}];
            }
            return nil;
        }

        for (PDSDatabaseRecord *record in page) {
            if (record.collection.length == 0 || record.rkey.length == 0 || record.cid.length == 0) {
                continue;
            }
            CID *recordCID = [CID cidFromString:record.cid];
            if (!recordCID) {
                continue;
            }
            NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
            [mst put:key valueCID:recordCID subKey:nil];
        }

        if (page.count < pageSize) {
            break;
        }
        offset += pageSize;
    }

    CID *rootCID = mst.rootCID;
    if (!rootCID && error && !*error) {
        *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                     code:9
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute repository root"}];
    }
    return rootCID;
}

- (nullable NSDictionary<NSString *, NSString *> *)refreshRepoRootMetadataForDid:(NSString *)did
                                                                     preferredRev:(nullable NSString *)preferredRev
                                                                            error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) {
        PDS_LOG_ERROR(@"refreshRepoRootMetadata: Failed to get store for DID %@", did);
        return nil;
    }

    // 1. Compute MST Root (Data CID)
    CID *dataCID = [self computeRepoRootCIDForDid:did store:store error:error];
    if (!dataCID) {
        PDS_LOG_ERROR(@"refreshRepoRootMetadata: Failed to compute repo root for DID %@", did);
        return nil;
    }

    // 2. Resolve Revision
    NSString *rev = [store latestMutationRevisionWithError:nil];
    if (rev.length == 0) {
        rev = preferredRev;
    }
    if (rev.length == 0) {
        rev = [TID tid].stringValue;
    }

    // 3. Get Previous Commit CID (Head)
    NSData *prevCommitBytes = [store getRepoRootForDid:did error:nil];
    CID *prevCommitCID = prevCommitBytes ? [CID cidFromBytes:prevCommitBytes] : nil;

    // 4. Create Commit Object
    RepoCommit *commit = [RepoCommit createCommitWithDid:did
                                                    data:dataCID
                                                     rev:rev
                                                    prev:prevCommitCID];
    
    // 5. Sign Commit
    NSData *signingKey = [store signingKeyPrivateBytesWithError:error];
    if (!signingKey) {
        PDS_LOG_ERROR(@"refreshRepoRootMetadata: Failed to get signing key for DID %@", did);
        return nil;
    }
    
    NSError *signError = nil;
    if (![commit signWithPrivateKey:signingKey error:&signError]) {
        if (error) *error = signError;
        return nil;
    }
    
    // 6. Store Commit Block
    CID *commitCID = [commit computeCID];
    NSData *commitData = [commit serializeSigned];
    if (!commitData) {
        if (error) *error = [NSError errorWithDomain:@"PDSRecordService" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize commit"}];
        return nil;
    }

    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = [commitCID bytes];
    block.blockData = commitData;
    block.size = commitData.length;

    // 7. Update Repo Root and Store Block in Transaction
    __block BOOL updated = NO;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        if (![transactor putBlock:block forDid:did error:blockError]) {
             return;
        }
        updated = [transactor updateRepoRoot:did rootCid:[commitCID bytes] rev:rev error:blockError];
    } error:error];

    if (!updated) {
        NSLog(@"[PDSRecordService] refreshRepoRootMetadata: FAILED to update database for DID %@", did);
        return nil;
    }

    NSLog(@"[PDSRecordService] refreshRepoRootMetadata: SUCCESS for DID %@, CID: %@", did, commitCID.stringValue);
    return @{
        @"cid": commitCID.stringValue ?: @"",
        @"rev": rev ?: @""
    };
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
    
    [store readWithBlock:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *actorStore = (PDSActorStore *)reader;
        NSString *sql = @"SELECT collection, COUNT(*) as count FROM records GROUP BY collection ORDER BY collection";
        sqlite3_stmt *stmt = [actorStore prepareStatement:sql error:blockError];
        
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
        } else {
             if (blockError && *blockError) {
                PDS_LOG_DB_ERROR(@"[PDSRecordService] Failed to prepare stats statement: %@", *blockError);
             }
        }
    } error:error];
    
    if (error && *error) {
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
