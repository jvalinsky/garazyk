#import "PDSRecordService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"
#import "Core/ATProtoBase32.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoValidator.h"
#import "Core/CID.h"
#import "Core/NSDictionary+CID.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Core/TID.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconError.h"
#import "Core/Repositories/PDSRecordRepository.h"
#import "Core/Repositories/PDSSQLiteRecordRepository.h"
#import "Repository/MST.h"
#import "Repository/CBOR.h"
#import "Core/MSTCacheManager.h"
#import <CommonCrypto/CommonDigest.h>
#import "Repository/RepoCommit.h"
#include <math.h>

NSErrorDomain const PDSRecordServiceErrorDomain = @"com.atproto.pds.record-service";

static const NSTimeInterval kATProtoCreatedAtMaxSkewSeconds = 24.0 * 60.0 * 60.0;

static BOOL validateCreatedAtCoherence(NSString *collection,
                                       NSString *rkey,
                                       NSDictionary *value,
                                       PDSValidationMode mode,
                                       NSError **error) {
    if (mode == PDSValidationModeOff) {
        return YES;
    }
    if (![collection isKindOfClass:[NSString class]] || collection.length == 0) {
        return YES;
    }
    // Guardrail for AppView compatibility: app.bsky.feed.post should have a createdAt
    // timestamp that is reasonably close to the rkey TID timestamp.
    if (![collection isEqualToString:@"app.bsky.feed.post"]) {
        return YES;
    }
    id createdAtValue = value[@"createdAt"];
    if (![createdAtValue isKindOfClass:[NSString class]] || ((NSString *)createdAtValue).length == 0) {
        return YES;
    }
    TID *tid = [TID tidFromString:rkey];
    if (!tid) {
        return YES;
    }
    NSDate *createdAtDate = [NSDateFormatter atproto_dateFromString:(NSString *)createdAtValue];
    if (!createdAtDate) {
        return YES;
    }
    NSDate *rkeyDate = [NSDate dateWithTimeIntervalSince1970:((NSTimeInterval)tid.timestamp / 1000000.0)];
    NSTimeInterval skew = fabs([createdAtDate timeIntervalSinceDate:rkeyDate]);
    if (skew <= kATProtoCreatedAtMaxSkewSeconds) {
        return YES;
    }
    if (error) {
        *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain
                                     code:400
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:
                                                     @"createdAt is too far from rkey timestamp (skew %.0fs > %.0fs)",
                                                     skew, kATProtoCreatedAtMaxSkewSeconds]}];
    }
    return NO;
}

@interface PDSRecordService ()

- (BOOL)checkAuthorizationForDid:(NSString *)targetDid actorDid:(NSString *)actorDid error:(NSError **)error;
- (nullable NSDictionary *)_applyWritesSerialized:(NSArray<NSDictionary *> *)writes
                                         forDid:(NSString *)did
                                       actorDid:(NSString *)actorDid
                                 validationMode:(PDSValidationMode)mode
                                     swapCommit:(nullable NSString *)swapCommit
                                          error:(NSError **)error;
- (nullable MST *)loadRepoMSTForDid:(NSString *)did
                               store:(PDSActorStore *)store
                               error:(NSError **)error;
- (nullable CID *)computeRepoRootCIDForDid:(NSString *)did
                                      store:(PDSActorStore *)store
                                      error:(NSError **)error;
- (nullable NSDictionary<NSString *, NSString *> *)refreshRepoRootMetadataForDid:(NSString *)did
                                                                    preferredRev:(nullable NSString *)preferredRev
                                                              mutationCIDsByKey:(nullable NSDictionary<NSString *, id> *)mutationCIDsByKey
                                                             mutationBlocksByCID:(nullable NSDictionary<NSString *, NSData *> *)mutationBlocksByCID
                                                                     changedKeys:(nullable NSArray<NSString *> *)changedKeys
                                                                           error:(NSError **)error;
- (nullable NSArray<PDSDatabaseBlock *> *)changedMSTBlocksForMST:(MST *)mst
                                                       changedKeys:(NSArray<NSString *> *)changedKeys
                                                              rev:(NSString *)rev
                                                            error:(NSError **)error;

@property (nonatomic, strong) NSMutableDictionary<NSString *, MST *> *mstCacheByDid;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *statsCacheByDid;
#if defined(GNUSTEP)
@property (nonatomic, assign) dispatch_queue_t mstCacheQueue;
@property (nonatomic, assign) dispatch_queue_t writeQueue;
#else
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t mstCacheQueue;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t writeQueue;
#endif

@end

@implementation PDSRecordService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        self.databasePool = databasePool;
        self.recordRepository = [[PDSSQLiteRecordRepository alloc] initWithDatabasePool:databasePool];
        _mstCacheByDid = [NSMutableDictionary dictionary];
        _statsCacheByDid = [NSMutableDictionary dictionary];
        _mstCacheQueue = dispatch_queue_create("com.atproto.pds.recordservice.mstcache", DISPATCH_QUEUE_SERIAL);
        _writeQueue = dispatch_queue_create("com.atproto.pds.recordservice.write", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Authorization

- (BOOL)checkAuthorizationForDid:(NSString *)targetDid actorDid:(NSString *)actorDid error:(NSError **)error {
    if (!actorDid || !targetDid) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain
                                          code:PDSRecordServiceErrorUnauthorized
                                      userInfo:@{NSLocalizedDescriptionKey: @"Authorization required: missing actor or target DID"}];
        }
        return NO;
    }
    
    if (![actorDid isEqualToString:targetDid]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain
                                          code:PDSRecordServiceErrorUnauthorized
                                      userInfo:@{NSLocalizedDescriptionKey: @"Cannot modify another user's repository"}];
        }
        return NO;
    }
    
    return YES;
}

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
        PDS_LOG_ERROR(@"[PDSRecordService] Invalid collection NSID: %@", collection);
        if (error) *error = nsidError;
        return NO;
    }

    // Validate rkey format
    NSError *rkeyError = nil;
    if (![ATProtoValidator validateRkey:rkey error:&rkeyError]) {
        PDS_LOG_ERROR(@"[PDSRecordService] Invalid rkey: %@", rkey);
        if (error) *error = rkeyError;
        return NO;
    }

    // Lexicon validation
    if (mode != PDSValidationModeOff) {
        ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
        PDS_LOG_INFO(@"[PDSRecordService] Using lexicon registry: %p (loaded NSIDs: %lu)", registry, (unsigned long)registry.loadedNSIDs.count);

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
            PDS_LOG_ERROR(@"[PDSRecordService] Lexicon validation failed for %@: %@",
                          collection, validationError.localizedDescription);
            if (error) *error = validationError;
            return NO;
        }

        PDS_LOG_DEBUG(@"[PDSRecordService] Lexicon validation passed for %@", collection);
    }

    if (!validateCreatedAtCoherence(collection, rkey, value, mode, error)) {
        NSString *message = (error && *error) ? (*error).localizedDescription : @"invalid createdAt";
        PDS_LOG_WARN(@"[PDSRecordService] createdAt coherence check failed for %@/%@: %@",
                     collection, rkey, message);
        return NO;
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
        }
    }

    // Serialize DB write + MST update to prevent concurrent repo mutation races
    __block BOOL success = NO;
    __block NSString *newRootCID = nil;
    __block NSString *newRev = nil;
    __block CID *prevRoot = nil;
    __block NSError *writeError = nil;
    NSTimeInterval writeQueueEnter = [NSDate timeIntervalSinceReferenceDate];
    dispatch_sync(self.writeQueue, ^{
        NSTimeInterval writeQueueStart = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval waitMs = (writeQueueStart - writeQueueEnter) * 1000.0;
        PDS_LOG_DEBUG(@"[PDSRecordService] putRecord: writeQueue entered (waited %.1fms) did=%@ coll=%@ rkey=%@",
                       waitMs, did, collection, rkey);
        success = [self.recordRepository saveRecord:record error:&writeError];

        if (success) {
            NSTimeInterval saveMs = ([NSDate timeIntervalSinceReferenceDate] - writeQueueStart) * 1000.0;
            PDS_LOG_DEBUG(@"[PDSRecordService] putRecord: saveRecord OK (%.1fms) did=%@", saveMs, did);

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
            PDS_LOG_DEBUG(@"[PDSRecordService] putRecord: refreshRepoRootMetadata OK (%.1fms) did=%@ commit=%@",
                           mstMs, did, newRootCID);
        }
        NSTimeInterval totalMs = ([NSDate timeIntervalSinceReferenceDate] - writeQueueStart) * 1000.0;
        PDS_LOG_DEBUG(@"[PDSRecordService] putRecord: writeQueue total %.1fms did=%@ success=%d", totalMs, did, success);
    });

    if (error && writeError) {
        *error = writeError;
    }

    if (success) {
        PDS_LOG_DEBUG(@"[PDSRecordService] Record changed: did=%@, collection=%@, rkey=%@, cid=%@, commit=%@, rev=%@, recordCBOR_len=%lu", did, collection, rkey, cidString, newRootCID, newRev, (unsigned long)cborData.length);
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
    }

    PDS_LOG_SERVICE_DEBUG(@"putRecord finishing with success: %d", success);
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
    NSTimeInterval writeQueueEnter = [NSDate timeIntervalSinceReferenceDate];
    dispatch_sync(self.writeQueue, ^{
        NSTimeInterval writeQueueStart = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval waitMs = (writeQueueStart - writeQueueEnter) * 1000.0;
        PDS_LOG_DEBUG(@"[PDSRecordService] deleteRecord: writeQueue entered (waited %.1fms) did=%@ coll=%@ rkey=%@",
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
            NSTimeInterval saveMs = ([NSDate timeIntervalSinceReferenceDate] - writeQueueStart) * 1000.0;
            PDS_LOG_DEBUG(@"[PDSRecordService] deleteRecord: DB delete OK (%.1fms) did=%@", saveMs, did);

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
            PDS_LOG_DEBUG(@"[PDSRecordService] deleteRecord: refreshRepoRootMetadata OK (%.1fms) did=%@ commit=%@",
                           mstMs, did, newRootCID);
        }
        NSTimeInterval totalMs = ([NSDate timeIntervalSinceReferenceDate] - writeQueueStart) * 1000.0;
        PDS_LOG_DEBUG(@"[PDSRecordService] deleteRecord: writeQueue total %.1fms did=%@ success=%d", totalMs, did, success);
    });

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

    return success;
}

- (BOOL)deleteRecord:(NSString *)collection
                 rkey:(NSString *)rkey
               forDid:(NSString *)did
                error:(NSError **)error {
    return [self deleteRecord:collection rkey:rkey forDid:did actorDid:did error:error];
}

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

    // Serialize all repo writes to prevent concurrent SQLite access
    // and MST mutation races that cause segfaults under load.
    __block NSDictionary *response = nil;
    __block NSError *writeError = nil;
    NSTimeInterval writeQueueEnter = [NSDate timeIntervalSinceReferenceDate];
    dispatch_sync(self.writeQueue, ^{
        NSTimeInterval writeQueueStart = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval waitMs = (writeQueueStart - writeQueueEnter) * 1000.0;
        PDS_LOG_DEBUG(@"[PDSRecordService] applyWrites: writeQueue entered (waited %.1fms) did=%@ writes=%lu",
                       waitMs, did, (unsigned long)writes.count);
        response = [self _applyWritesSerialized:writes
                                        forDid:did
                                      actorDid:actorDid
                                validationMode:mode
                                    swapCommit:swapCommit
                                         error:&writeError];
        NSTimeInterval totalMs = ([NSDate timeIntervalSinceReferenceDate] - writeQueueStart) * 1000.0;
        PDS_LOG_DEBUG(@"[PDSRecordService] applyWrites: writeQueue total %.1fms did=%@ response=%@",
                       totalMs, did, response ? @"OK" : @"FAILED");
    });
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
            PDS_LOG_ERROR(@"[PDSRecordService] applyWrites: missing action (%@) or collection (%@) in write: %@", 
                          action ?: @"nil", collection ?: @"nil", write);
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
                PDS_LOG_ERROR(@"[PDSRecordService] applyWrites: create write missing record value: %@", write);
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

            // Validate rkey format
            NSError *rkeyError = nil;
            if (![ATProtoValidator validateRkey:rkey error:&rkeyError]) {
                if (error) *error = rkeyError;
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

            NSError *coherenceError = nil;
            if (!validateCreatedAtCoherence(collection, rkey, record, mode, &coherenceError)) {
                if (error && !*error) *error = coherenceError;
                return nil;
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

            NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
            PDSDatabaseRecord *existingRecord = [self.databasePool getRecord:uri forDid:did error:nil];
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
                recordCBOR = [ATProtoCBORSerialization encodeDataWithJSONObject:value error:nil];
            }
        }

        if (recordCBOR.length > 0) {
            recordCBORByURI[rec.uri] = recordCBOR;
        }
    }

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

- (nullable CID *)computeRepoRootCIDForDid:(NSString *)did
                                      store:(PDSActorStore *)store
                                      error:(NSError **)error {
    MST *mst = [self loadRepoMSTForDid:did store:store error:error];
    if (!mst) {
        return nil;
    }

    CID *rootCID = mst.rootCID;
    if (!rootCID && error && !*error) {
        *error = [NSError errorWithDomain:@"com.atproto.repo.applyWrites"
                                     code:9
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute repository root"}];
    }
    return rootCID;
}

- (nullable MST *)loadMSTFromRepoBlocksForDid:(NSString *)did
                                        store:(PDSActorStore *)store
                                        error:(NSError **)error {
    return [MSTCacheManager loadMSTFromRepoBlocksForDid:did store:store error:error];
}

- (nullable MST *)loadRepoMSTForDid:(NSString *)did
                               store:(PDSActorStore *)store
                               error:(NSError **)error {
    MST *mst = [[MST alloc] init];
    const NSUInteger pageSize = 1000;
    NSUInteger offset = 0;
    const NSUInteger maxIterations = 1000; // Safety: max 1M records
    NSUInteger iterations = 0;

    while (iterations++ < maxIterations) {
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

    return mst;
}

- (nullable NSArray<PDSDatabaseBlock *> *)changedMSTBlocksForMST:(MST *)mst
                                                       changedKeys:(NSArray<NSString *> *)changedKeys
                                                              rev:(NSString *)rev
                                                            error:(NSError **)error {
    if (!mst) {
        return @[];
    }

    NSMutableDictionary<NSString *, PDSDatabaseBlock *> *blocksByCID = [NSMutableDictionary dictionary];

    BOOL (^appendBlock)(CID *, NSData *) = ^BOOL(CID *cid, NSData *data) {
        NSString *cidString = cid.stringValue ?: @"";
        if (cidString.length == 0 || data.length == 0) {
            return YES;
        }
        if (blocksByCID[cidString]) {
            return YES;
        }
        PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
        block.cid = cid.bytes;
        block.blockData = data;
        block.size = (NSInteger)data.length;
        block.createdAt = [NSDate date];
        block.rev = rev;
        blocksByCID[cidString] = block;
        return YES;
    };

    CID *rootCID = mst.rootCID;
    NSData *rootData = [mst serializeToCBOR];
    if (!rootCID || rootData.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRecordService"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize MST root"}];
        }
        return nil;
    }
    appendBlock(rootCID, rootData);

    for (NSString *key in changedKeys ?: @[]) {
        if (key.length == 0) {
            continue;
        }
        NSArray<MSTNode *> *proofNodes = [mst getProofNodesForKey:key];
        for (MSTNode *node in proofNodes ?: @[]) {
            NSData *nodeData = [mst serializeNode:node];
            if (nodeData.length == 0) {
                continue;
            }
            CID *nodeCID = [CID cidWithDigest:[CID sha256Digest:nodeData] codec:0x71];
            if (!nodeCID) {
                continue;
            }
            appendBlock(nodeCID, nodeData);
        }
    }

    return [blocksByCID.allValues copy];
}

- (nullable NSDictionary<NSString *, NSString *> *)refreshRepoRootMetadataForDid:(NSString *)did
                                                                    preferredRev:(nullable NSString *)preferredRev
                                                              mutationCIDsByKey:(nullable NSDictionary<NSString *, id> *)mutationCIDsByKey
                                                             mutationBlocksByCID:(nullable NSDictionary<NSString *, NSData *> *)mutationBlocksByCID
                                                                     changedKeys:(nullable NSArray<NSString *> *)changedKeys
                                                                           error:(NSError **)error {
    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        PDS_LOG_ERROR(@"refreshRepoRootMetadata: Failed to get store for DID %@", did);
        return nil;
    }

    __block NSDictionary<NSString *, NSString *> *result = nil;
    __block NSError *queueError = nil;

    dispatch_sync(self.mstCacheQueue, ^{
        MST *mst = [[MSTCacheManager sharedManager] mstForDid:did];
        if (!mst) {
            // Try incremental loading from stored repo blocks first
            mst = [self loadMSTFromRepoBlocksForDid:did store:store error:&queueError];
            if (!mst) {
                // Fallback: full rebuild from records
                mst = [self loadRepoMSTForDid:did store:store error:&queueError];
            }
            if (!mst) {
                return;
            }
        }

        [mutationCIDsByKey enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
            (void)stop;
            if (key.length == 0) {
                return;
            }

            if ([obj isKindOfClass:[NSNull class]]) {
                [mst delete:key];
                return;
            }

            NSString *cidString = [obj isKindOfClass:[NSString class]] ? (NSString *)obj : nil;
            CID *recordCID = (cidString.length > 0) ? [CID cidFromString:cidString] : nil;
            if (!recordCID) {
                return;
            }
            [mst put:key valueCID:recordCID subKey:nil];
        }];

        CID *dataCID = mst.rootCID;
        if (!dataCID) {
            queueError = [NSError errorWithDomain:@"PDSRecordService"
                                             code:-3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute updated MST root"}];
            [[MSTCacheManager sharedManager] removeMSTForDid:did];
            [self.statsCacheByDid removeObjectForKey:did];
            return;
        }

        // Always invalidate stats cache on successful write
        [self.statsCacheByDid removeObjectForKey:did];

        NSString *rev = [store latestMutationRevisionWithError:nil];
        if (rev.length == 0) {
            rev = preferredRev;
        }
        if (rev.length == 0) {
            rev = [TID tid].stringValue;
        }

        NSData *prevCommitBytes = [store getRepoRootForDid:did error:nil];
        CID *prevCommitCID = prevCommitBytes ? [CID cidFromBytes:prevCommitBytes] : nil;

        RepoCommit *commit = [RepoCommit createCommitWithDid:did
                                                        data:dataCID
                                                         rev:rev
                                                        prev:prevCommitCID];

        NSData *signature = [store signData:[commit serialize] error:&queueError];
        if (!signature) {
            [[MSTCacheManager sharedManager] removeMSTForDid:did];
            return;
        }
        commit.signature = signature;

        CID *commitCID = [commit computeCID];
        NSData *commitData = [commit serializeSigned];
        if (!commitCID || commitData.length == 0) {
            queueError = [NSError errorWithDomain:@"PDSRecordService"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize signed commit"}];
            [[MSTCacheManager sharedManager] removeMSTForDid:did];
            return;
        }

        PDSDatabaseBlock *commitBlock = [[PDSDatabaseBlock alloc] init];
        commitBlock.cid = [commitCID bytes];
        commitBlock.blockData = commitData;
        commitBlock.size = commitData.length;
        commitBlock.createdAt = [NSDate date];
        commitBlock.rev = rev;

        NSArray<PDSDatabaseBlock *> *mstBlocks = [self changedMSTBlocksForMST:mst
                                                                    changedKeys:changedKeys ?: @[]
                                                                           rev:rev
                                                                         error:&queueError];
        if (!mstBlocks) {
            [[MSTCacheManager sharedManager] removeMSTForDid:did];
            return;
        }

        NSMutableArray<PDSDatabaseBlock *> *blocksToPersist = [NSMutableArray arrayWithObject:commitBlock];
        [blocksToPersist addObjectsFromArray:mstBlocks];

        // Add mutation blocks (the actual records)
        [mutationBlocksByCID enumerateKeysAndObjectsUsingBlock:^(NSString *cidStr, NSData *data, BOOL *stop) {
            CID *cid = [CID cidFromString:cidStr];
            if (cid && data.length > 0) {
                PDSDatabaseBlock *recordBlock = [[PDSDatabaseBlock alloc] init];
                recordBlock.cid = [cid bytes];
                recordBlock.blockData = data;
                recordBlock.size = data.length;
                recordBlock.createdAt = [NSDate date];
                recordBlock.rev = rev;
                [blocksToPersist addObject:recordBlock];
            }
        }];

        __block BOOL updated = NO;
        [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            if (![transactor putBlocks:blocksToPersist forDid:did error:blockError]) {
                return;
            }
            updated = [transactor updateRepoRoot:did rootCid:[commitCID bytes] rev:rev error:blockError];
        } error:&queueError];

        if (!updated) {
            [[MSTCacheManager sharedManager] removeMSTForDid:did];
            if (!queueError) {
                queueError = [NSError errorWithDomain:@"PDSRecordService"
                                                 code:-4
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to update repository head"}];
            }
            return;
        }

        [[MSTCacheManager sharedManager] setMST:mst forDid:did];
        result = @{
            @"cid": commitCID.stringValue ?: @"",
            @"rev": rev ?: @""
        };
    });

    if (!result && error && queueError) {
        *error = queueError;
    }
    return result;
}

- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did error:(NSError **)error {
    __block NSDictionary *cached = nil;
    dispatch_sync(self.mstCacheQueue, ^{
        cached = self.statsCacheByDid[did];
    });
    if (cached) return cached;

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
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
    
    NSDictionary *result = @{
        @"did": did,
        @"collections": results,
        @"recordCount": @(totalCount)
    };

    dispatch_sync(self.mstCacheQueue, ^{
        self.statsCacheByDid[did] = result;
    });

    return result;
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
