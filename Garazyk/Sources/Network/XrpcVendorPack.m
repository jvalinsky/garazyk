// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcVendorPack.m
//  ATProtoPDS
//
//  Domain module for tools.garazyk.* vendor XRPC endpoints.
//

#import "Network/XrpcVendorPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Core/ATProtoValidator.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Database/Pool/DatabasePool.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Metrics/GZMetrics.h"
#import "Debug/GZLogger.h"
#import "Network/Generated/GZXrpcNSID.h"

@implementation XrpcVendorPack

+ (NSString *)routePackIdentifier {
  return @"tools.garazyk";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
    
    JWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    PDSRepositoryService *repositoryService = services.repositoryService;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;

    // Register tools.garazyk.sync.getRepoFiltered
    [dispatcher registerMethod:kGZXrpcNSID_tools_garazyk_sync_getRepoFiltered
                       handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            [XrpcErrorHelper setMethodNotAllowedError:response
                                       allowedMethod:@"GET"
                                             message:@"Expected GET"];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *authenticatedDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!authenticatedDid) {
            return;
        }
        (void)authenticatedDid;

        NSString *did = [request queryParamForKey:@"did"];
        NSArray<NSString *> *collections = [request queryParamsForKey:@"collections"];
        NSString *since = [request queryParamForKey:@"since"];
        if (since.length == 0) {
            since = nil;
        }
        if (did.length == 0 || collections.count == 0) {
            [XrpcErrorHelper setInvalidRequestError:response
                                            message:@"Missing did or collections parameter"];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:did error:&didError]) {
            [XrpcErrorHelper setInvalidRequestError:response
                                            message:didError.localizedDescription ?: @"Invalid DID format"];
            return;
        }

        NSMutableArray<NSString *> *validatedCollections = [NSMutableArray arrayWithCapacity:collections.count];
        for (NSString *collection in collections) {
            if (![collection isKindOfClass:[NSString class]] || collection.length == 0) {
                [XrpcErrorHelper setInvalidRequestError:response
                                                message:@"Each collections parameter must be a non-empty NSID"];
                return;
            }

            NSError *collectionError = nil;
            if (![ATProtoValidator validateNSID:collection error:&collectionError]) {
                [XrpcErrorHelper setInvalidRequestError:response
                                                message:collectionError.localizedDescription ?: [NSString stringWithFormat:@"Invalid collection NSID: %@", collection]];
                return;
            }
            [validatedCollections addObject:collection];
        }

        NSError *exportError = nil;
        PDSRepoChunkProducer producer = [repositoryService filteredRepoContentsChunkProducer:did
                                                                                      since:since
                                                                                collections:validatedCollections
                                                                                      error:&exportError];
        if (!producer) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound",
                                    @"message": exportError.localizedDescription ?: @"Repository not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = @"application/vnd.ipld.car";
        [response setBodyChunkProducer:producer chunkedTransferEncoding:YES];
    }];

    // Register tools.garazyk.admin.getCollectionMembershipStats
    // GET action=stats → returns collection_membership row count
    // POST action=prune → triggers stale-entry cleanup
    [dispatcher registerMethod:kGZXrpcNSID_tools_garazyk_admin_getCollectionMembershipStats
                       handler:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                           response:response
                                   serviceDatabases:serviceDatabases
                                          jwtMinter:jwtMinter
                                    adminController:adminController]) {
            return;
        }

        NSString *action = [request queryParamForKey:@"action"] ?: @"stats";

        if ([action isEqualToString:@"stats"]) {
            if (request.method != HttpMethodGET) {
                [XrpcErrorHelper setMethodNotAllowedError:response
                                           allowedMethod:@"GET"
                                                 message:@"Expected GET for stats"];
                return;
            }

            NSError *countError = nil;
            NSInteger count = [serviceDatabases collectionMembershipCountWithError:&countError];
            if (count < 0) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"QueryFailed",
                                        @"message": countError.localizedDescription ?: @"Failed to query collection_membership size"}];
                return;
            }

            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"count": @(count)}];
        } else if ([action isEqualToString:@"prune"]) {
            if (request.method != HttpMethodPOST) {
                [XrpcErrorHelper setMethodNotAllowedError:response
                                           allowedMethod:@"POST"
                                                 message:@"Expected POST for prune"];
                return;
            }

            PDSDatabasePool *userPool = services.userDatabasePool;
            NSError *pruneError = nil;
            NSInteger pruned = [serviceDatabases pruneStaleCollectionMembershipsWithUserDatabasePool:userPool
                                                                                               error:&pruneError];
            if (pruned < 0) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"PruneFailed",
                                        @"message": pruneError.localizedDescription ?: @"Failed to prune stale entries"}];
                return;
            }

            NSInteger count = [serviceDatabases collectionMembershipCountWithError:nil];
            if (count < 0) count = 0;
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"count": @(count), @"pruned": @(pruned)}];
        } else {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest",
                                    @"message": @"action must be stats or prune"}];
        }
    }];

    // Register tools.garazyk.account.getUsage
    [dispatcher registerMethod:kGZXrpcNSID_tools_garazyk_account_getUsage
                       handler:^(HttpRequest *request, HttpResponse *response) {
        // Require authenticated user
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == 0) {
                response.statusCode = 401;
                [response setJsonBody:@{@"error": @"AuthenticationRequired",
                                       @"message": @"Authentication required"}];
            }
            return;
        }

        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed",
                                    @"message": @"Expected GET"}];
            return;
        }

        // Query account_usage from actor store
        PDSActorStore *store = [repositoryService.databasePool storeForDid:did error:nil];
        NSDictionary *usage;
        if (store) {
            __block NSDictionary *usageResult = nil;
            [store readWithBlock:^(id<PDSActorStoreReader> reader, NSError **blockError) {
                PDSActorStore *actorStore = (PDSActorStore *)reader;
                NSString *sql = @"SELECT blob_bytes, blob_count, repo_bytes, record_count "
                                 @"FROM account_usage WHERE did = ?";
                sqlite3_stmt *stmt = [actorStore prepareStatement:sql error:blockError];
                if (!stmt) return;
                sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) == SQLITE_ROW) {
                    usageResult = @{
                        @"blobBytes": @(sqlite3_column_int64(stmt, 0)),
                        @"blobCount": @(sqlite3_column_int(stmt, 1)),
                        @"repoBytes": @(sqlite3_column_int64(stmt, 2)),
                        @"recordCount": @(sqlite3_column_int(stmt, 3))
                    };
                }
                [actorStore finalizeStatement:stmt];
            } error:nil];
            if (usageResult) {
                NSMutableDictionary *mutable = [usageResult mutableCopy];
                mutable[@"did"] = did;
                usage = [mutable copy];
            } else {
                usage = @{
                    @"did": did,
                    @"blobBytes": @(0),
                    @"blobCount": @(0),
                    @"repoBytes": @(0),
                    @"recordCount": @(0)
                };
            }
        } else {
            usage = @{
                @"did": did,
                @"blobBytes": @(0),
                @"blobCount": @(0),
                @"repoBytes": @(0),
                @"recordCount": @(0)
            };
        }

        // Check soft quotas and emit metrics if configured
        ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
        GZMetrics *metrics = [GZMetrics sharedMetrics];

        unsigned long long blobBytes = [usage[@"blobBytes"] unsignedLongLongValue];
        NSUInteger recordCount = [usage[@"recordCount"] unsignedIntegerValue];
        unsigned long long repoBytes = [usage[@"repoBytes"] unsignedLongLongValue];

        if (config.softQuotaBlobBytes > 0 && blobBytes > config.softQuotaBlobBytes) {
            GZ_LOG_WARN(@"Soft quota exceeded for blob bytes: %@ (%llu > %llu)",
                         did, blobBytes, config.softQuotaBlobBytes);
            [metrics incrementQuotaExceeded:@"blob_bytes"];
        }
        if (config.softQuotaRecordCount > 0 && recordCount > config.softQuotaRecordCount) {
            GZ_LOG_WARN(@"Soft quota exceeded for record count: %@ (%lu > %lu)",
                         did, (unsigned long)recordCount, (unsigned long)config.softQuotaRecordCount);
            [metrics incrementQuotaExceeded:@"record_count"];
        }
        if (config.softQuotaRepoBytes > 0 && repoBytes > config.softQuotaRepoBytes) {
            GZ_LOG_WARN(@"Soft quota exceeded for repo bytes: %@ (%llu > %llu)",
                         did, repoBytes, config.softQuotaRepoBytes);
            [metrics incrementQuotaExceeded:@"repo_bytes"];
        }

        // Per-account Prometheus labels (gated by config)
        if (config.metricsPerAccountLabels) {
            [metrics setAccountBlobBytes:blobBytes forDid:did];
            [metrics setAccountRepoBytes:repoBytes forDid:did];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:usage];
    }];
}

@end
