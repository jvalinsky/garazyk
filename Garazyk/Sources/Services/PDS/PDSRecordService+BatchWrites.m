// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRecordService+BatchWrites.h"
#import "PDSRecordService+Validation.h"
#import "Debug/GZLogger.h"
#import "Core/ATProtoValidator.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Core/NSDictionary+CID.h"
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
#import "Core/NSDateFormatter+ATProto.h"

@implementation PDSRecordService (BatchWrites)

#pragma mark - Apply Writes (Batch Operations)

- (nullable NSDictionary *)applyWrites:(NSArray<NSDictionary *> *)writes
                                 forDid:(NSString *)did
                               actorDid:(NSString *)actorDid
                         validationMode:(PDSValidationMode)mode
                             swapCommit:(nullable NSString *)swapCommit
                                  error:(NSError **)error {
    
    if (![self checkAuthorizationForDid:did actorDid:actorDid error:error]) {
        return nil;
    }
    
    if (!writes.count) {
        return @{@"results": @[]};
    }

    // Serialize per-DID repo writes to prevent concurrent SQLite access
    // and MST mutation races that cause segfaults under load.
    // The per-DID dispatcher allows writes for different DIDs to proceed
    // concurrently while serializing writes for the same DID.
    __block NSDictionary *response = nil;
    __block NSError *writeError = nil;
    NSTimeInterval writeEnter = [NSDate timeIntervalSinceReferenceDate];
    [self _dispatchWriteForDid:did block:^{
        NSTimeInterval writeStart = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval waitMs = (writeStart - writeEnter) * 1000.0;
        GZ_LOG_DEBUG(@"[PDSRecordService] applyWrites: writeDispatcher entered (waited %.1fms) did=%@ writes=%lu",
                       waitMs, did, (unsigned long)writes.count);
        response = [self _applyWritesSerialized:writes
                                        forDid:did
                                      actorDid:actorDid
                                validationMode:mode
                                    swapCommit:swapCommit
                                         error:&writeError];
        NSTimeInterval totalMs = ([NSDate timeIntervalSinceReferenceDate] - writeStart) * 1000.0;
        GZ_LOG_DEBUG(@"[PDSRecordService] applyWrites: writeDispatcher total %.1fms did=%@ response=%@",
                       totalMs, did, response ? @"OK" : @"FAILED");
    }];
    if (error && writeError) {
        *error = writeError;
    }
    return response;
}

- (nullable NSDictionary *)_applyWritesSerialized:(NSArray<NSDictionary *> *)writes
                                           forDid:(NSString *)did
                                         actorDid:(NSString *)actorDid
                                   validationMode:(PDSValidationMode)mode
                                       swapCommit:(nullable NSString *)swapCommit
                                            error:(NSError **)error {

    // Validate swapCommit if provided
    if (swapCommit) {
        NSData *currentRoot = [self.databasePool getRepoRoot:did error:error];
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
    NSString *batchRev = [TID tid].stringValue;

    NSMutableArray *preparedOps = [NSMutableArray arrayWithCapacity:writes.count];
    NSMutableArray *resultOps = [NSMutableArray arrayWithCapacity:writes.count];
    for (NSDictionary *write in writes) {
        NSString *action = write[@"action"];
        if (!action) {
            // Spec-compliant clients use $type union discriminator
            // e.g. "com.atproto.repo.applyWrites#create" -> "create"
            NSString *type = write[@"$type"];
            if (type) {
                NSRange hashRange = [type rangeOfString:@"#" options:NSBackwardsSearch];
                if (hashRange.location != NSNotFound) {
                    action = [type substringFromIndex:hashRange.location + 1];
                } else if ([type hasPrefix:@"com.atproto.repo.applyWrites"]) {
                    // Fallback for missing hash if it looks like the correct Lexicon
                    if ([type hasSuffix:@"create"]) action = @"create";
                    else if ([type hasSuffix:@"update"]) action = @"update";
                    else if ([type hasSuffix:@"delete"]) action = @"delete";
                }
            }
        }
        NSString *collection = write[@"collection"];
        NSString *rkey = write[@"rkey"];
        NSString *swapRecord = write[@"swapRecord"];
        NSDictionary *record = write[@"value"];
        if (!record) {
            // Compatibility fallback for pre-lexicon field names.
            record = write[@"record"];
        }
        
        if (!action || !collection) {
            GZ_LOG_ERROR(@"[PDSRecordService] applyWrites: missing action (%@) or collection (%@) for write with rkey: %@", 
                          action ?: @"nil", collection ?: @"nil", rkey ?: @"nil");
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: 
                                            [NSString stringWithFormat:@"Each write must have action and collection (got action=%@, collection=%@)", 
                                             action ?: @"nil", collection ?: @"nil"]}];
            }
            return nil;
        }

        if ([action isEqualToString:@"create"]) {
            if (!rkey || rkey.length == 0) {
                rkey = [TID tid].stringValue;
            }
            if (!record) {
                GZ_LOG_ERROR(@"[PDSRecordService] applyWrites: create write missing record value for collection: %@ rkey: %@", collection ?: @"nil", rkey ?: @"nil");
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
            if (rejectUnknownBuiltInCollection(collection, mode, error)) {
                return nil;
            }

            // Validate rkey format
            NSError *rkeyError = nil;
            if (![ATProtoValidator validateRkey:rkey error:&rkeyError]) {
                if (error) *error = rkeyError;
                return nil;
            }

            if (mode != PDSValidationModeOff) {
                NSError *shapeError = nil;
                if (!PDSRecordServiceValidateRecordJSONShape(record, &shapeError)) {
                    if (error) *error = shapeError;
                    return nil;
                }
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

            NSError *coherenceError = nil;
            if (!validateCreatedAtCoherence(collection, rkey, record, mode, &coherenceError)) {
                if (error && !*error) *error = coherenceError;
                return nil;
            }

            if (![self validateThreadgateForReplyRecord:record collection:collection authorDID:did error:error]) {
                return nil;
            }

            // Build the database record
            NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
            GZ_LOG_INFO(@"PDSRecordService _applyWritesSerialized: building uri=%@ for did=%@", uri, did);
            NSError *cidError = nil;
            NSData *cborData = [ATProtoDagCBOR encodeJSONObject:record error:&cidError];
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

            [preparedOps addObject:@{
                @"action": action,
                @"record": dbRecord,
                @"recordCBOR": cborData,
                @"previousRecordCID": [NSNull null]
            }];
            [resultOps addObject:@{
                @"action": action,
                @"collection": collection ?: @"",
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

            // Validate rkey format
            NSError *rkeyError = nil;
            if (![ATProtoValidator validateRkey:rkey error:&rkeyError]) {
                if (error) *error = rkeyError;
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
            if (rejectUnknownBuiltInCollection(collection, mode, error)) {
                return nil;
            }

            if (mode != PDSValidationModeOff) {
                NSError *shapeError = nil;
                if (!PDSRecordServiceValidateRecordJSONShape(record, &shapeError)) {
                    if (error) *error = shapeError;
                    return nil;
                }
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

            NSError *coherenceError = nil;
            if (!validateCreatedAtCoherence(collection, rkey, record, mode, &coherenceError)) {
                if (error && !*error) *error = coherenceError;
                return nil;
            }

            if (![self validateThreadgateForReplyRecord:record collection:collection authorDID:did error:error]) {
                return nil;
            }

            NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
            GZ_LOG_INFO(@"PDSRecordService _applyWritesSerialized: building uri=%@ for did=%@", uri, did);
            PDSDatabaseRecord *existingRecord = [self.databasePool getRecord:uri forDid:did error:nil];
            if (!existingRecord) {
                if (error) {
                    *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                                 code:12
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Record not found: %@", uri]}];
                }
                return nil;
            }
            NSString *previousRecordCID =
                ([existingRecord.cid isKindOfClass:[NSString class]] &&
                 existingRecord.cid.length > 0)
                    ? existingRecord.cid
                    : nil;

            if (swapRecord && ![swapRecord isEqual:[NSNull null]]) {
                if (![swapRecord isEqualToString:previousRecordCID ?: @""]) {
                    if (error) {
                        *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                                     code:11
                                                 userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"InvalidSwap: record %@ CID mismatch (expected %@, got %@)",
                                                     uri, swapRecord, previousRecordCID ?: @"nil"]}];
                    }
                    return nil;
                }
            }

            NSError *cidError = nil;
            NSData *cborData = [ATProtoDagCBOR encodeJSONObject:record error:&cidError];
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

            [preparedOps addObject:@{
                @"action": action,
                @"record": dbRecord,
                @"recordCBOR": cborData,
                @"previousRecordCID": previousRecordCID ?: [NSNull null]
            }];
            [resultOps addObject:@{
                @"action": action,
                @"collection": collection ?: @"",
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

            // Validate rkey format
            NSError *rkeyError = nil;
            if (![ATProtoValidator validateRkey:rkey error:&rkeyError]) {
                if (error) *error = rkeyError;
                return nil;
            }

            NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
            GZ_LOG_INFO(@"PDSRecordService _applyWritesSerialized: building uri=%@ for did=%@", uri, did);
            PDSDatabaseRecord *existingRecord = [self.databasePool getRecord:uri forDid:did error:nil];
            BOOL recordExists = (existingRecord != nil);
            NSString *previousRecordCID =
                ([existingRecord.cid isKindOfClass:[NSString class]] &&
                 existingRecord.cid.length > 0)
                    ? existingRecord.cid
                    : nil;

            if (swapRecord && ![swapRecord isEqual:[NSNull null]]) {
                if (![swapRecord isEqualToString:previousRecordCID ?: @""]) {
                    if (error) {
                        *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                                     code:12
                                                 userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"InvalidSwap: record %@ CID mismatch for delete (expected %@, got %@)",
                                                     uri, swapRecord, previousRecordCID ?: @"nil"]}];
                    }
                    return nil;
                }
            }

            [preparedOps addObject:@{
                @"action": @"delete",
                @"uri": uri,
                @"collection": collection ?: @"",
                @"rkey": rkey ?: @"",
                @"exists": @(recordExists),
                @"previousRecordCID": previousRecordCID ?: [NSNull null]
            }];
            [resultOps addObject:@{@"action": @"delete", @"collection": collection ?: @""}];
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
    [self.databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        for (NSDictionary *op in preparedOps) {
            NSString *action = op[@"action"];

            if ([action isEqualToString:@"create"]) {
                PDSDatabaseRecord *dbRecord = op[@"record"];
                if (![transactor createRecord:dbRecord forDid:did error:blockError]) {
                    success = NO;
                    return;
                }
                NSData *recordCBOR = [op[@"recordCBOR"] isKindOfClass:[NSData class]] ? op[@"recordCBOR"] : nil;
                CID *recordCID = dbRecord.cid.length > 0 ? [CID cidFromString:dbRecord.cid] : nil;
                if (recordCBOR.length > 0 && recordCID) {
                    PDSDatabaseBlock *recordBlock = [[PDSDatabaseBlock alloc] init];
                    recordBlock.cid = recordCID.bytes;
                    recordBlock.repoDid = did;
                    recordBlock.blockData = recordCBOR;
                    recordBlock.contentType = @"application/vnd.ipld.dag-cbor";
                    recordBlock.size = (NSInteger)recordCBOR.length;
                    recordBlock.createdAt = [NSDate date];
                    recordBlock.rev = batchRev;
                    if (![transactor putBlock:recordBlock forDid:did error:blockError]) {
                        success = NO;
                        return;
                    }
                }
            } else if ([action isEqualToString:@"update"]) {
                PDSDatabaseRecord *dbRecord = op[@"record"];
                if (![transactor updateRecord:dbRecord forDid:did error:blockError]) {
                    success = NO;
                    return;
                }
                NSData *recordCBOR = [op[@"recordCBOR"] isKindOfClass:[NSData class]] ? op[@"recordCBOR"] : nil;
                CID *recordCID = dbRecord.cid.length > 0 ? [CID cidFromString:dbRecord.cid] : nil;
                if (recordCBOR.length > 0 && recordCID) {
                    PDSDatabaseBlock *recordBlock = [[PDSDatabaseBlock alloc] init];
                    recordBlock.cid = recordCID.bytes;
                    recordBlock.repoDid = did;
                    recordBlock.blockData = recordCBOR;
                    recordBlock.contentType = @"application/vnd.ipld.dag-cbor";
                    recordBlock.size = (NSInteger)recordCBOR.length;
                    recordBlock.createdAt = [NSDate date];
                    recordBlock.rev = batchRev;
                    if (![transactor putBlock:recordBlock forDid:did error:blockError]) {
                        success = NO;
                        return;
                    }
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
    PDSActorStore *store = [self.databasePool storeForDid:did error:&storeError];
    NSData *prevRootData = [store getRepoRootForDid:did error:nil];
    CID *prevRoot = prevRootData ? [CID cidFromBytes:prevRootData] : nil;

    NSMutableDictionary<NSString *, id> *mutationCIDsByKey = [NSMutableDictionary dictionary];
    NSMutableOrderedSet<NSString *> *changedKeys = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *op in preparedOps) {
        NSString *action = [op[@"action"] isKindOfClass:[NSString class]] ? op[@"action"] : @"";
        if ([action isEqualToString:@"delete"]) {
            NSString *collection = [op[@"collection"] isKindOfClass:[NSString class]] ? op[@"collection"] : nil;
            NSString *rkey = [op[@"rkey"] isKindOfClass:[NSString class]] ? op[@"rkey"] : nil;
            if (collection.length == 0 || rkey.length == 0) {
                continue;
            }
            NSString *key = [NSString stringWithFormat:@"%@/%@", collection, rkey];
            mutationCIDsByKey[key] = [NSNull null];
            [changedKeys addObject:key];
            continue;
        }

        PDSDatabaseRecord *record = op[@"record"];
        if (!record || record.collection.length == 0 || record.rkey.length == 0) {
            continue;
        }
        NSString *key = [NSString stringWithFormat:@"%@/%@", record.collection, record.rkey];
        mutationCIDsByKey[key] = record.cid ?: [NSNull null];
        [changedKeys addObject:key];
    }

    NSMutableDictionary<NSString *, NSData *> *mutationBlocksByCID = [NSMutableDictionary dictionary];
    for (NSDictionary *op in preparedOps) {
        NSString *action = op[@"action"];
        if ([action isEqualToString:@"delete"]) continue;
        
        PDSDatabaseRecord *record = op[@"record"];
        NSData *recordCBOR = [op[@"recordCBOR"] isKindOfClass:[NSData class]] ? op[@"recordCBOR"] : nil;
        if (record && record.cid && recordCBOR) {
            mutationBlocksByCID[record.cid] = recordCBOR;
        }
    }

    NSDictionary<NSString *, NSString *> *commitMeta = [self refreshRepoRootMetadataForDid:did
                                                                               preferredRev:batchRev
                                                                        mutationCIDsByKey:mutationCIDsByKey
                                                                       mutationBlocksByCID:mutationBlocksByCID
                                                                                changedKeys:changedKeys.array
                                                                                      error:nil];
    NSString *commitCID = commitMeta[@"cid"];
    NSString *commitRev = commitMeta[@"rev"];

    NSMutableDictionary<NSString *, NSString *> *resultCIDByURI = [NSMutableDictionary dictionaryWithCapacity:resultOps.count];
    for (NSDictionary *res in resultOps) {
        NSString *uri = [res[@"uri"] isKindOfClass:[NSString class]] ? res[@"uri"] : nil;
        NSString *cid = [res[@"cid"] isKindOfClass:[NSString class]] ? res[@"cid"] : nil;
        if (uri.length > 0 && cid.length > 0) {
            resultCIDByURI[uri] = cid;
        }
    }

    NSMutableDictionary<NSString *, NSData *> *recordCBORByURI = [NSMutableDictionary dictionaryWithCapacity:preparedOps.count];
    for (NSDictionary *op in preparedOps) {
        NSString *action = op[@"action"];
        if ([action isEqualToString:@"delete"]) {
            continue;
        }

        PDSDatabaseRecord *rec = op[@"record"];
        if (!rec || rec.uri.length == 0) {
            continue;
        }

        NSData *recordCBOR = [op[@"recordCBOR"] isKindOfClass:[NSData class]] ? op[@"recordCBOR"] : nil;
        if (!recordCBOR && rec.value.length > 0) {
            NSData *jsonData = [rec.value dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *value = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
            if (value) {
                recordCBOR = [ATProtoDagCBOR encodeJSONObject:value error:nil];
            }
        }

        if (recordCBOR.length > 0) {
            recordCBORByURI[rec.uri] = recordCBOR;
        }
    }

    // Track collections with deletes for membership index pruning.
    NSMutableSet<NSString *> *deletedCollectionKeys = [NSMutableSet set];

    // Notify firehose of all writes in the batch
    for (NSUInteger idx = 0; idx < writes.count; idx++) {
        NSDictionary *write = writes[idx];
        NSDictionary *prepared = (idx < preparedOps.count) ? preparedOps[idx] : nil;
        NSString *action = write[@"action"];
        NSString *collection = write[@"collection"];
        NSString *rkey = write[@"rkey"];
        NSString *previousRecordCID =
            [prepared[@"previousRecordCID"] isKindOfClass:[NSString class]]
                ? prepared[@"previousRecordCID"]
                : nil;

        NSString *uri = (collection && rkey)
            ? [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey]
            : nil;
        NSString *resultCID = (uri.length > 0) ? resultCIDByURI[uri] : nil;

        NSString *normalizedAction = ([action isEqualToString:@"update"]) ? @"update"
                                   : ([action isEqualToString:@"delete"] ? @"delete" : @"create");

        NSData *recordCBOR = (![normalizedAction isEqualToString:@"delete"] && uri.length > 0)
            ? recordCBORByURI[uri]
            : nil;

        PDSDatabaseRecord *preparedRecord = prepared[@"record"];
        NSString *actualRkey = (preparedRecord && preparedRecord.rkey) ? preparedRecord.rkey : rkey;

        [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                            object:self
                                                          userInfo:@{
            @"did": did,
            @"collection": collection ?: @"",
            @"rkey": actualRkey ?: @"",
            @"action": normalizedAction,
            @"cid": resultCID ?: [NSNull null],
            @"prev": prevRoot ? prevRoot.stringValue : [NSNull null],
            @"previousRecordCID": previousRecordCID ?: [NSNull null],
            @"commit": commitCID ?: [NSNull null],
            @"rev": commitRev ?: [NSNull null],
            @"recordCBOR": recordCBOR ?: [NSNull null]
        }];

        // Update collection membership index for create/update writes.
        if (![normalizedAction isEqualToString:@"delete"] && collection.length > 0) {
            [self.serviceDatabases upsertCollectionMembership:collection forDID:did error:nil];
        }

        // Track deleted collections for post-batch pruning.
        if ([normalizedAction isEqualToString:@"delete"] && collection.length > 0) {
            NSString *key = [NSString stringWithFormat:@"%@|%@", did, collection];
            [deletedCollectionKeys addObject:key];
        }
    }

    // Prune membership entries for collections that had deletes, if no
    // records remain.
    if (self.serviceDatabases && deletedCollectionKeys.count > 0) {
        for (NSString *key in deletedCollectionKeys) {
            NSArray *parts = [key componentsSeparatedByString:@"|"];
            if (parts.count != 2) continue;
            NSString *deleteDid = parts[0];
            NSString *deleteCollection = parts[1];
            __block BOOL hasRemaining = YES;
            [self.databasePool readWithDid:deleteDid block:^(id<PDSActorStoreReader> reader, NSError **readError) {
                hasRemaining = [reader hasRecordsForCollection:deleteCollection error:readError];
            } error:nil];
            if (!hasRemaining) {
                [self.serviceDatabases removeCollectionMembership:deleteCollection forDID:deleteDid error:nil];
            }
        }
    }

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:resultOps.count];
    for (NSDictionary *op in resultOps) {
        NSString *action = op[@"action"];
        NSString *collection = op[@"collection"];
        if ([action isEqualToString:@"delete"]) {
            [results addObject:@{}];
            continue;
        }
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"uri"] = op[@"uri"] ?: @"";
        entry[@"cid"] = [op cidStringForKey:@"cid"] ?: @"";
        NSString *validationStatus = @"unknown";
        if (mode != PDSValidationModeOff &&
            [collection isKindOfClass:[NSString class]] &&
            collection.length > 0) {
            BOOL hasSchema = [[ATProtoLexiconRegistry sharedRegistry] schemaForNSID:collection] != nil;
            validationStatus = hasSchema ? @"valid" : @"unknown";
        }
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

- (nullable NSDictionary *)applyWrites:(NSArray<NSDictionary *> *)writes
                                 forDid:(NSString *)did
                         validationMode:(PDSValidationMode)mode
                             swapCommit:(nullable NSString *)swapCommit
                                  error:(NSError **)error {
    return [self applyWrites:writes forDid:did actorDid:did validationMode:mode swapCommit:swapCommit error:error];
}

@end
