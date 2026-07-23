// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRecordService+RecordCRUD.h"
#import "PDSRecordService+Validation.h"
#import "Debug/GZLogger.h"
#import "Core/ATProtoValidator.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Core/Repositories/PDSRecordRepository.h"
#import "Core/Repositories/PDSSQLiteRecordRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"

@implementation PDSRecordService (RecordCRUD)

#pragma mark - Record Operations

- (nullable NSDictionary *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    PDSDatabaseRecord *record = [self.recordRepository recordForUri:uri error:error];

    if (!record) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PDSController" code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }

    NSDictionary *parsedValue = @{};
    if (record.value) {
        if ([record.value respondsToSelector:@selector(dataUsingEncoding:)]) {
            NSData *data = [record.value dataUsingEncoding:NSUTF8StringEncoding];
            if (data) {
                parsedValue = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] ?: @{};
            }
        } else if ([record.value isKindOfClass:[NSDictionary class]]) {
            parsedValue = (NSDictionary *)record.value;
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

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) return nil;

    NSArray<PDSDatabaseRecord *> *records = [self.recordRepository recordsForDid:did
                                                                      collection:collection
                                                                           error:error];
    if (records && records.count > limit) {
        records = [records subarrayWithRange:NSMakeRange(0, limit)];
    }

    NSMutableArray *result = [NSMutableArray array];
    for (PDSDatabaseRecord *record in records) {
        NSDictionary *parsedValue = @{};
        if (record.value) {
            if ([record.value respondsToSelector:@selector(dataUsingEncoding:)]) {
                NSData *data = [record.value dataUsingEncoding:NSUTF8StringEncoding];
                if (data) {
                    parsedValue = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] ?: @{};
                }
            } else if ([record.value isKindOfClass:[NSDictionary class]]) {
                parsedValue = (NSDictionary *)record.value;
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
          actorDid:(NSString *)actorDid
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error {
    
    if (![self checkAuthorizationForDid:did actorDid:actorDid error:error]) {
        return NO;
    }
    
    // Validate collection NSID format
    NSError *nsidError = nil;
    if (![ATProtoValidator validateNSID:collection error:&nsidError]) {
        GZ_LOG_ERROR(@"[PDSRecordService] Invalid collection NSID: %@", collection);
        if (error) *error = nsidError;
        return NO;
    }
    if (rejectUnknownBuiltInCollection(collection, mode, error)) {
        return NO;
    }

    // Validate rkey format
    NSError *rkeyError = nil;
    if (![ATProtoValidator validateRkey:rkey error:&rkeyError]) {
        GZ_LOG_ERROR(@"[PDSRecordService] Invalid rkey: %@", rkey);
        if (error) *error = rkeyError;
        return NO;
    }

    if (mode != PDSValidationModeOff) {
        NSError *shapeError = nil;
        if (!PDSRecordServiceValidateRecordJSONShape(value, &shapeError)) {
            if (error) *error = shapeError;
            return NO;
        }
    }

    // Lexicon validation
    if (mode != PDSValidationModeOff) {
        ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
        GZ_LOG_INFO(@"[PDSRecordService] Using lexicon registry: %p (loaded NSIDs: %lu)", registry, (unsigned long)registry.loadedNSIDs.count);

        ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc]
            initWithRegistry:registry];

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
            GZ_LOG_ERROR(@"[PDSRecordService] Lexicon validation failed for %@: %@",
                          collection, validationError.localizedDescription);
            if (error) *error = validationError;
            return NO;
        }

        GZ_LOG_DEBUG(@"[PDSRecordService] Lexicon validation passed for %@", collection);
    }

    if (!validateCreatedAtCoherence(collection, rkey, value, mode, error)) {
        NSString *message = (error && *error) ? (*error).localizedDescription : @"invalid createdAt";
        GZ_LOG_WARN(@"[PDSRecordService] createdAt coherence check failed for %@/%@: %@",
                     collection, rkey, message);
        return NO;
    }

    if (![self validateThreadgateForReplyRecord:value collection:collection authorDID:did error:error]) {
        return NO;
    }

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

    NSError *cidError;
    // Use DAG-CBOR encoding for CID calculation to match spec
    NSData *cborData = [ATProtoDagCBOR encodeJSONObject:value error:&cidError];
    if (!cborData) {
        if (error) *error = cidError;
        return NO;
    }

    NSString *cidString = [self generateCIDForData:cborData error:&cidError];
    if (!cidString) {
        if (error) *error = cidError;
        return NO;
    }

    PDSDatabaseRecord *existingRecord = [self.databasePool getRecord:uri forDid:did error:nil];
    NSString *previousRecordCID = ([existingRecord.cid isKindOfClass:[NSString class]] &&
                                   existingRecord.cid.length > 0)
                                      ? existingRecord.cid
                                      : nil;
    NSString *firehoseAction =
        previousRecordCID.length > 0 ? @"update" : @"create";

    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    NSString *writeRev = [TID tid].stringValue;
    record.uri = uri;
    GZ_LOG_INFO(@"PDSRecordService putRecord: saving uri=%@ for did=%@", uri, did);
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

    // Serialize DB write + MST update to prevent concurrent repo mutation races
    __block BOOL success = NO;
    __block NSString *newRootCID = nil;
    __block NSString *newRev = nil;
    __block CID *prevRoot = nil;
    __block NSError *writeError = nil;
    NSTimeInterval writeEnter = [NSDate timeIntervalSinceReferenceDate];
    [self _dispatchWriteForDid:did block:^{
        NSTimeInterval writeStart = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval waitMs = (writeStart - writeEnter) * 1000.0;
        GZ_LOG_DEBUG(@"[PDSRecordService] putRecord: writeDispatcher entered (waited %.1fms) did=%@ coll=%@ rkey=%@",
                       waitMs, did, collection, rkey);
        success = [self.recordRepository saveRecord:record error:&writeError];

        if (success) {
            NSTimeInterval saveMs = ([NSDate timeIntervalSinceReferenceDate] - writeStart) * 1000.0;
            GZ_LOG_DEBUG(@"[PDSRecordService] putRecord: saveRecord OK (%.1fms) did=%@", saveMs, did);

            // Fetch previous root and refresh metadata to get new commit info
            NSTimeInterval mstStart = [NSDate timeIntervalSinceReferenceDate];
            PDSActorStore *store = [self.databasePool storeForDid:did error:nil];
            NSData *prevRootData = [store getRepoRootForDid:did error:nil];
            prevRoot = prevRootData ? [CID cidFromBytes:prevRootData] : nil;

            NSString *recordKey = [NSString stringWithFormat:@"%@/%@", collection, rkey];
            NSDictionary<NSString *, id> *mutationCIDsByKey = @{
                recordKey: cidString ?: [NSNull null]
            };

            NSDictionary<NSString *, NSData *> *mutationBlocksByCID = (cidString && cborData) ? @{cidString: cborData} : nil;

            NSDictionary *newRootMeta = [self refreshRepoRootMetadataForDid:did
                                                               preferredRev:writeRev
                                                         mutationCIDsByKey:mutationCIDsByKey
                                                        mutationBlocksByCID:mutationBlocksByCID
                                                                 changedKeys:@[ recordKey ]
                                                                       error:nil];
            newRootCID = newRootMeta[@"cid"];
            newRev = newRootMeta[@"rev"];
            NSTimeInterval mstMs = ([NSDate timeIntervalSinceReferenceDate] - mstStart) * 1000.0;
            GZ_LOG_DEBUG(@"[PDSRecordService] putRecord: refreshRepoRootMetadata OK (%.1fms) did=%@ commit=%@",
                           mstMs, did, newRootCID);
        }
        NSTimeInterval totalMs = ([NSDate timeIntervalSinceReferenceDate] - writeStart) * 1000.0;
        GZ_LOG_DEBUG(@"[PDSRecordService] putRecord: writeDispatcher total %.1fms did=%@ success=%d", totalMs, did, success);
    }];

    if (error && writeError) {
        *error = writeError;
    }

    if (success) {
        GZ_LOG_DEBUG(@"[PDSRecordService] Record changed: did=%@, collection=%@, rkey=%@, cid=%@, commit=%@, rev=%@, recordCBOR_len=%lu", did, collection, rkey, cidString, newRootCID, newRev, (unsigned long)cborData.length);
        [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                            object:self
                                                          userInfo:@{
            @"did": did,
            @"collection": collection,
            @"rkey": rkey,
            @"action": firehoseAction,
            @"cid": cidString,
            @"prev": prevRoot ? prevRoot.stringValue : [NSNull null],
            @"previousRecordCID": previousRecordCID ?: [NSNull null],
            @"commit": newRootCID ?: [NSNull null],
            @"rev": newRev ?: [NSNull null],
            @"recordCBOR": cborData ?: [NSNull null]
        }];

        // Update collection membership index so listReposByCollection
        // can query without scanning per-user actor stores.
        [self.serviceDatabases upsertCollectionMembership:collection forDID:did error:nil];
    }

    GZ_LOG_SERVICE_DEBUG(@"putRecord finishing with success: %d", success);
    return success;
}

- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
             error:(NSError **)error {
    return [self putRecord:collection
                      rkey:rkey
                     value:value
                    forDid:did
                  actorDid:did
            validationMode:PDSValidationModeOptimistic
                     error:error];
}

- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error {
    return [self putRecord:collection
                      rkey:rkey
                     value:value
                    forDid:did
                  actorDid:did
            validationMode:mode
                     error:error];
}

- (BOOL)deleteRecord:(NSString *)collection
                 rkey:(NSString *)rkey
               forDid:(NSString *)did
             actorDid:(NSString *)actorDid
                error:(NSError **)error {
    
    if (![self checkAuthorizationForDid:did actorDid:actorDid error:error]) {
        return NO;
    }

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSString *writeRev = [TID tid].stringValue;
    PDSDatabaseRecord *existingRecord = [self.databasePool getRecord:uri forDid:did error:nil];
    BOOL hadExistingRecord = (existingRecord != nil);
    NSString *previousRecordCID = ([existingRecord.cid isKindOfClass:[NSString class]] &&
                                   existingRecord.cid.length > 0)
                                      ? existingRecord.cid
                                      : nil;

    // Serialize DB write + MST update to prevent concurrent repo mutation races
    __block BOOL success = YES;
    __block NSString *newRootCID = nil;
    __block NSString *newRev = nil;
    __block CID *prevRoot = nil;
    __block NSError *writeError = nil;
    NSTimeInterval writeEnter = [NSDate timeIntervalSinceReferenceDate];
    [self _dispatchWriteForDid:did block:^{
        NSTimeInterval writeStart = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval waitMs = (writeStart - writeEnter) * 1000.0;
        GZ_LOG_DEBUG(@"[PDSRecordService] deleteRecord: writeDispatcher entered (waited %.1fms) did=%@ coll=%@ rkey=%@",
                       waitMs, did, collection, rkey);
        [self.databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            if (hadExistingRecord) {
                if (![transactor addRecordTombstoneURI:uri
                                                   did:did
                                             collection:collection
                                                  rkey:rkey
                                                    rev:writeRev
                                                  error:blockError]) {
                    success = NO;
                    return;
                }
            }

            if (![transactor deleteRecord:uri forDid:did error:blockError]) {
                success = NO;
            }
        } error:&writeError];

        if (success) {
            NSTimeInterval saveMs = ([NSDate timeIntervalSinceReferenceDate] - writeStart) * 1000.0;
            GZ_LOG_DEBUG(@"[PDSRecordService] deleteRecord: DB delete OK (%.1fms) did=%@", saveMs, did);

            // Fetch previous root and refresh metadata
            NSTimeInterval mstStart = [NSDate timeIntervalSinceReferenceDate];
            PDSActorStore *store = [self.databasePool storeForDid:did error:nil];
            NSData *prevRootData = [store getRepoRootForDid:did error:nil];
            prevRoot = prevRootData ? [CID cidFromBytes:prevRootData] : nil;

            NSString *recordKey = [NSString stringWithFormat:@"%@/%@", collection, rkey];
            NSDictionary<NSString *, id> *mutationCIDsByKey = @{
                recordKey: [NSNull null]
            };

            NSDictionary *newRootMeta = [self refreshRepoRootMetadataForDid:did
                                                               preferredRev:writeRev
                                                         mutationCIDsByKey:mutationCIDsByKey
                                                        mutationBlocksByCID:nil
                                                                 changedKeys:@[ recordKey ]
                                                                       error:nil];
            newRootCID = newRootMeta[@"cid"];
            newRev = newRootMeta[@"rev"];
            NSTimeInterval mstMs = ([NSDate timeIntervalSinceReferenceDate] - mstStart) * 1000.0;
            GZ_LOG_DEBUG(@"[PDSRecordService] deleteRecord: refreshRepoRootMetadata OK (%.1fms) did=%@ commit=%@",
                           mstMs, did, newRootCID);
        }
        NSTimeInterval totalMs = ([NSDate timeIntervalSinceReferenceDate] - writeStart) * 1000.0;
        GZ_LOG_DEBUG(@"[PDSRecordService] deleteRecord: writeDispatcher total %.1fms did=%@ success=%d", totalMs, did, success);
    }];

    if (error && writeError) {
        *error = writeError;
    }

    if (!success) {
        return NO;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                        object:self
                                                      userInfo:@{
        @"did": did,
        @"collection": collection,
        @"rkey": rkey,
        @"action": @"delete",
        @"cid": [NSNull null],
        @"prev": prevRoot ? prevRoot.stringValue : [NSNull null],
        @"previousRecordCID": previousRecordCID ?: [NSNull null],
        @"commit": newRootCID ?: [NSNull null],
        @"rev": newRev ?: [NSNull null],
        @"recordCBOR": [NSNull null]
    }];

    // Prune collection membership entry if no records remain in this
    // collection for this DID. Default to YES (conservative): if the
    // actor store check fails, we keep the entry rather than risk a
    // false negative in listReposByCollection.
    if (self.serviceDatabases) {
        __block BOOL hasRemaining = YES;
        [self.databasePool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **readError) {
            hasRemaining = [reader hasRecordsForCollection:collection error:readError];
        } error:nil];
        if (!hasRemaining) {
            [self.serviceDatabases removeCollectionMembership:collection forDID:did error:nil];
        }
    }

    return success;
}

- (BOOL)deleteRecord:(NSString *)collection
                 rkey:(NSString *)rkey
               forDid:(NSString *)did
                error:(NSError **)error {
    return [self deleteRecord:collection rkey:rkey forDid:did actorDid:did error:error];
}

@end
