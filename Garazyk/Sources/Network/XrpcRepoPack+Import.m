// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcRepoPack+Import.h"
#import "Network/XrpcRepoPack_Internal.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/PDSRepoImportValidator.h"
#import "Services/PDS/PDSRecordService.h"
#import "Services/PDS/PDSBlobService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "App/PDSController.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Repository/CAR.h"
#import "Repository/STAR.h"
#import "Repository/RepoCommit.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Debug/GZLogger.h"
#import "Network/Generated/GZXrpcNSID.h"

static const NSUInteger kPDSImportRepoMaxBodyBytes = 16 * 1024 * 1024;

@implementation XrpcRepoPack (Import)

+ (void)registerImportRoutesWithDispatcher:(XrpcDispatcher *)dispatcher
                                  services:(id<XrpcRoutePackServices>)services {
    PDSRecordService *recordService = services.recordService;

#pragma mark - com.atproto.repo.importRepo
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_importRepo handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSData *repoData = request.body;
        if (!repoData || repoData.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repository body"}];
            return;
        }
        if (repoData.length > kPDSImportRepoMaxBodyBytes) {
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
            carData = [STARConverter carDataFromSTARData:repoData error:&starErr];
            if (!carData) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{
                    @"error": @"InvalidRequest",
                    @"message": starErr.localizedDescription ?: @"Failed to convert STAR to CAR"
                }];
                return;
            }
        }

        NSError *carError = nil;
        CARReader *reader = [CARReader readFromData:carData error:&carError];
        if (!reader || !reader.rootCID) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": carError.localizedDescription ?: @"Invalid CAR payload"
            }];
            return;
        }

        NSError *commitError = nil;
        RepoCommit *commit = [RepoCommit fromCARData:carData error:&commitError];
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
                                             reader:reader
                                             commit:commit
                                                did:did
                                      databasePool:databasePool
                             allowLocalKeyFallback:allowLocalKeyFallback
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

        NSArray<PDSDatabaseBlock *> *blocks = importValidation.blocks;
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
        NSError *writeError = nil;
        [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **error) {
            if (blocks.count > 0 && ![transactor putBlocks:blocks forDid:did error:error]) {
                return;
            }
            if (validatedRecords.count > 0 && ![transactor putRecords:validatedRecords forDid:did error:error]) {
                return;
            }
            if (![transactor updateRepoRoot:did rootCid:reader.rootCID.bytes rev:(commit.rev ?: @"") error:error]) {
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
            @"rootCid": reader.rootCID.stringValue ?: @"",
            @"rev": commit.rev ?: @"",
            @"recordCount": @(validatedRecords.count),
            @"skippedCount": @((NSInteger)records.count - (NSInteger)validatedRecords.count)
        }];
    }];
}

@end
