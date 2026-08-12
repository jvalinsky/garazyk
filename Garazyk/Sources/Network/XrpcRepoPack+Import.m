// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcRepoPack+Import.h"
#import "Network/XrpcRepoPack_Internal.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcRoutePackServices.h"
#import "Security/ATProtoPermissionScopeEvaluator.h"
#import "Network/PDSRepoImportValidator.h"
#import "Services/PDS/PDSRecordService.h"
#import "Services/PDS/PDSRecordService+BlobLifecycle.h"
#import "Services/PDS/PDSBlobService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Repository/CAR.h"
#import "Repository/STAR.h"
#import "Repository/RepoCommit.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Debug/GZLogger.h"
#import "Network/Generated/GZXrpcNSID.h"

@implementation ATProtoXrpcRepoPack (Import)

+ (void)registerImportRoutesWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                                  services:(id<XrpcRoutePackServices>)services {
    PDSRecordService *recordService = services.recordService;
    ATProtoServiceConfiguration *config = services.configuration;

#pragma mark - com.atproto.repo.importRepo
    // Route-specific body cap: the import route admits bodies up to
    // maxImportSize while every other XRPC endpoint keeps the generic HTTP
    // parser limit. The dispatcher exposes the cap to the HTTP layer through
    // the per-path provider installed by ATProtoHttpXrpcRoutePack.
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_importRepo
                  maxBodyBytes:config.maxImportSize
                       handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [ATProtoXrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }
        if (![ATProtoPermissionScopeEvaluator evaluateAccountScopes:request.permissionScopes ?: @[]
                                                        forAttribute:@"repo"
                                                              action:@"manage"]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{ @"error": @"InsufficientScope", @"message": @"account:repo?action=manage scope is required" }];
            return;
        }

        // Feature-flag style kill switch, mirroring upstream
        // (cfg.service.acceptingImports): checked before the body is read.
        if (!config.acceptingImports) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": @"Import is not currently accepted"
            }];
            return;
        }

        NSData *repoData = request.body;
        if (!repoData || repoData.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repository body"}];
            return;
        }
        if (repoData.length > config.maxImportSize) {
            response.statusCode = HttpStatusPayloadTooLarge;
            [response setJsonBody:@{@"error": @"PayloadTooLarge", @"message": @"Repository import body too large"}];
            return;
        }

        if (![request headerForKey:@"Content-Length"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing Content-Length header"}];
            return;
        }

        NSString *contentType = [[request headerForKey:@"Content-Type"] lowercaseString];
        BOOL isSTAR = [contentType hasPrefix:@"application/vnd.atproto.star"];
        BOOL isCAR = [contentType hasPrefix:@"application/vnd.ipld.car"];
        if (contentType.length > 0 && !isCAR && !isSTAR) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Content-Type must be application/vnd.ipld.car or application/vnd.atproto.star"}];
            return;
        }

        // Convert STAR to CAR if needed
        NSData *carData = repoData;
        if (isSTAR || STARDetectFormatFromData(repoData)) {
            NSError *starErr = nil;
            carData = [ATProtoSTARConverter carDataFromSTARData:repoData error:&starErr];
            if (!carData) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{
                    @"error": @"InvalidRequest",
                    @"message": starErr.localizedDescription ?: @"Failed to convert STAR to CAR"
                }];
                return;
            }
        }

        // Caller-supplied archive: a strict streaming reader verifies the
        // header (canonical DRISL, version, roots) and every block's CID
        // against its payload as it streams, without materializing a full
        // block array. The reader keeps a CID index as blocks stream so the
        // MST walk below can resolve nodes/records by CID.
        NSError *carError = nil;
        ATProtoCARStreamReader *stream =
            [[ATProtoCARStreamReader alloc] initWithData:carData strict:YES error:&carError];
        if (!stream || !stream.rootCID) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": carError.localizedDescription ?: @"Invalid CAR payload"
            }];
            return;
        }

        NSError *commitError = nil;
        ATProtoRepoCommit *commit = [ATProtoRepoCommit fromCARData:carData error:&commitError];
        if (!commit) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": commitError.localizedDescription ?: @"CAR root is not a valid repo commit"
            }];
            return;
        }

        if (![commit.did isKindOfClass:[NSString class]] || ![commit.did isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{
                @"error": @"Forbidden",
                @"message": @"Imported repository DID must match the authenticated account"
            }];
            return;
        }
        if (!commit.dataCID || commit.dataCID.bytes.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": @"Commit is missing a data CID"
            }];
            return;
        }

        PDSDatabasePool *databasePool = recordService.databasePool;
        if (!databasePool) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": @"Record database pool is unavailable"}];
            return;
        }

        BOOL allowLocalKeyFallback = [services.configuration.plcURL containsString:@"mock"] || [services.configuration.plcURL containsString:@"skip"];
        NSError *importValidationError = nil;
        PDSRepoImportValidationResult *importValidation =
            [PDSRepoImportValidator validateCARData:carData
                                             reader:stream
                                             commit:commit
                                                did:did
                                      databasePool:databasePool
                             allowLocalKeyFallback:allowLocalKeyFallback
                                     maxImportSize:config.maxImportSize
                                              error:&importValidationError];
        if (!importValidation) {
            response.statusCode = (importValidationError.code == PDSRepoPackValidationErrorPayloadTooLarge)
                ? HttpStatusPayloadTooLarge
                : HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": (response.statusCode == HttpStatusPayloadTooLarge) ? @"PayloadTooLarge" : @"InvalidRequest",
                @"message": importValidationError.localizedDescription ?: @"Invalid repository import"
            }];
            return;
        }

        NSArray<PDSDatabaseRecord *> *records = importValidation.records;

        // Lexicon validation for imported records
        // Per spec: records must conform to their declared lexicon type
        ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc]
            initWithRegistry:[ATProtoLexiconRegistry sharedRegistry]];

        NSMutableArray<PDSDatabaseRecord *> *validatedRecords = [NSMutableArray arrayWithCapacity:records.count];
        for (PDSDatabaseRecord *record in records) {
            // Parse record value to extract $type
            NSData *valueData = [record.value dataUsingEncoding:NSUTF8StringEncoding];
            if (!valueData) {
                GZ_LOG_DEBUG(@"[importRepo] Skipping record with invalid value encoding: %@", record.uri);
                continue;
            }

            NSError *parseError = nil;
            NSDictionary *recordValue = [NSJSONSerialization JSONObjectWithData:valueData
                                                                        options:0
                                                                          error:&parseError];
            if (!recordValue || ![recordValue isKindOfClass:[NSDictionary class]]) {
                GZ_LOG_DEBUG(@"[importRepo] Skipping record with invalid JSON: %@ - %@",
                              record.uri, parseError.localizedDescription);
                continue;
            }

            NSString *recordType = recordValue[@"$type"];
            if (![recordType isKindOfClass:[NSString class]]) {
                // No $type - this may be a raw CBOR-style record without lexicon
                // Accept it but log warning
                GZ_LOG_DEBUG(@"[importRepo] Record missing $type: %@", record.uri);
                [validatedRecords addObject:record];
                continue;
            }

            // Validate record against lexicon
            // Use ATProtoValidationModeOptimistic: validate if lexicon known, accept if unknown
            NSError *validationError = nil;
            if (![validator validateRecord:recordValue
                                 collection:recordType
                                       mode:ATProtoValidationModeOptimistic
                                      error:&validationError]) {
                GZ_LOG_WARN(@"[importRepo] Lexicon validation failed for %@: %@",
                             record.uri, validationError.localizedDescription);
                // For import: reject records that fail validation for known lexicons
                // This prevents importing malformed data
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{
                    @"error": @"InvalidRecord",
                    @"message": [NSString stringWithFormat:
                                 @"Record %@ failed lexicon validation: %@",
                                 record.uri, validationError.localizedDescription]
                }];
                return;
            }

            [validatedRecords addObject:record];
        }

        GZ_LOG_DEBUG(@"[importRepo] Validated %lu/%lu records",
                      (unsigned long)validatedRecords.count, (unsigned long)records.count);

        NSError *storeError = nil;
        PDSActorStore *store = [databasePool storeForDid:did error:&storeError];
        if (!store) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{
                @"error": @"StoreUnavailable",
                @"message": storeError.localizedDescription ?: @"Failed to open actor store"
            }];
            return;
        }

        __block BOOL committed = NO;
        __block NSUInteger addedCount = 0;
        __block NSUInteger updatedCount = 0;
        __block NSUInteger deletedCount = 0;
        NSError *writeError = nil;
        [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **error) {
            // Diff mode (ADR 0035 B4, matching upstream): when the target
            // store already holds a repo root, re-imports apply only the
            // deltas instead of a from-scratch overwrite — records missing
            // from the incoming CAR are deleted (with tombstones and blob-ref
            // cleanup), records whose CID changed are updated, and unchanged
            // records are left alone. Reads and writes share this single
            // transaction, so the diff is race-free. A fresh store (no root)
            // takes the initial-import path: every record is added.
            PDSActorStore *actorStore = (PDSActorStore *)transactor;
            NSData *currentRoot = [actorStore getRepoRootForDid:did error:error];
            if (*error) {
                return;
            }

            NSMutableDictionary<NSString *, NSString *> *currentByURI = [NSMutableDictionary dictionary];
            if (currentRoot) {
                NSUInteger recordOffset = 0;
                const NSUInteger kReadPage = 5000;
                while (YES) {
                    NSArray<PDSDatabaseRecord *> *page = [actorStore listRecordsForDid:did collection:nil limit:kReadPage offset:recordOffset error:error];
                    if (*error || !page) {
                        return;
                    }
                    if (page.count == 0) {
                        break;
                    }
                    for (PDSDatabaseRecord *record in page) {
                        currentByURI[record.uri ?: @""] = record.cid;
                    }
                    if (page.count < kReadPage) {
                        break;
                    }
                    recordOffset += page.count;
                }
            }

            NSMutableDictionary<NSString *, PDSDatabaseRecord *> *importedByURI = [NSMutableDictionary dictionary];
            for (PDSDatabaseRecord *record in validatedRecords) {
                importedByURI[record.uri ?: @""] = record;
            }

            // Records present locally but absent from the imported CAR.
            NSMutableArray<NSString *> *urisToDelete = [NSMutableArray array];
            for (NSString *uri in currentByURI) {
                if (!importedByURI[uri]) {
                    [urisToDelete addObject:uri];
                }
            }
            for (NSString *uri in urisToDelete) {
                PDSDatabaseRecord *currentRecord = [actorStore getRecord:uri forDid:did error:error];
                if (*error || !currentRecord) {
                    return;
                }
                if (![transactor deleteRecord:uri forDid:did error:error]) {
                    return;
                }
                if (![transactor addRecordTombstoneURI:uri
                                                   did:did
                                             collection:currentRecord.collection ?: @""
                                                  rkey:currentRecord.rkey ?: @""
                                                    rev:commit.rev ?: @""
                                                 error:error]) {
                    return;
                }
                if (![recordService removeBlobReferencesForRecordURI:uri
                                                              forDid:did
                                                          transactor:transactor
                                                               error:error]) {
                    return;
                }
                deletedCount++;
            }

            // Records to write: new, or existing with a different CID.
            NSMutableArray<PDSDatabaseRecord *> *recordsToPut = [NSMutableArray array];
            for (PDSDatabaseRecord *record in validatedRecords) {
                NSString *previousCID = currentByURI[record.uri ?: @""];
                if (previousCID == nil) {
                    addedCount++;
                } else if (![previousCID isEqualToString:record.cid]) {
                    updatedCount++;
                } else {
                    continue; // unchanged: row and blob refs already in place
                }
                [recordsToPut addObject:record];
            }
            if (recordsToPut.count > 0) {
                if (![transactor putRecords:recordsToPut forDid:did error:error]) {
                    return;
                }
                for (PDSDatabaseRecord *record in recordsToPut) {
                    NSData *valueData = [record.value dataUsingEncoding:NSUTF8StringEncoding];
                    NSDictionary *recordValue = valueData ? [NSJSONSerialization JSONObjectWithData:valueData options:0 error:nil] : nil;
                    if (![recordValue isKindOfClass:[NSDictionary class]] ||
                        ![recordService syncBlobReferencesForRecordURI:record.uri
                                                            recordValue:recordValue
                                                                 forDid:did
                                                            transactor:transactor
                                                                 error:error]) {
                        return;
                    }
                }
            }

            // Write blocks in bounded batches inside the single transaction:
            // peak memory is bounded by the batch size rather than a full
            // PDSDatabaseBlock array. putBlock: is INSERT OR IGNORE, so
            // re-writing blocks that are already present is a no-op.
            const NSUInteger kBatchSize = [PDSRepoImportValidator importBlockBatchSize];
            [stream reset];
            NSMutableArray<PDSDatabaseBlock *> *batch = [NSMutableArray arrayWithCapacity:kBatchSize];
            NSError *streamError = nil;
            BOOL streamed = [stream enumerateBlocksWithError:&streamError handler:^BOOL(ATProtoCARBlock *block, NSError **stopError) {
                PDSDatabaseBlock *dbBlock = [[PDSDatabaseBlock alloc] init];
                dbBlock.cid = block.cid.bytes;
                dbBlock.blockData = block.data;
                dbBlock.size = (NSInteger)block.data.length;
                dbBlock.rev = commit.rev ?: @"";
                [batch addObject:dbBlock];
                if (batch.count >= kBatchSize) {
                    if (![transactor putBlocks:batch forDid:did error:stopError]) {
                        return NO;
                    }
                    [batch removeAllObjects];
                }
                return YES;
            }];
            if (!streamed) {
                if (error) {
                    *error = streamError ?: [NSError errorWithDomain:@"com.atproto.repo"
                                                                code:1
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to stream imported blocks"}];
                }
                return;
            }
            if (batch.count > 0 && ![transactor putBlocks:batch forDid:did error:error]) {
                return;
            }
            if (![transactor updateRepoRoot:did rootCid:stream.rootCID.bytes rev:(commit.rev ?: @"") error:error]) {
                return;
            }
            committed = YES;
        } error:&writeError];

        if (!committed) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{
                @"error": @"ImportFailed",
                @"message": writeError.localizedDescription ?: @"Failed to import repository"
            }];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"rootCid": stream.rootCID.stringValue ?: @"",
            @"rev": commit.rev ?: @"",
            @"recordCount": @(validatedRecords.count),
            @"skippedCount": @((NSInteger)records.count - (NSInteger)validatedRecords.count),
            @"addedCount": @(addedCount),
            @"updatedCount": @(updatedCount),
            @"deletedCount": @(deletedCount)
        }];
    }];
}

@end
