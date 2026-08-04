// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcRepoPack+Records.h"
#import "Network/XrpcRepoPack_Internal.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcRoutePackServices.h"
#import "Services/PDS/PDSRecordService.h"
#import "Services/PDS/PDSAccountService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabaseAccount.h"
#import "Identity/HandleResolver.h"
#import "Security/ATProtoPermissionScopeEvaluator.h"
#import "Debug/GZLogger.h"
#import "Network/Generated/GZXrpcNSID.h"

@implementation XrpcRepoPack (Records)

static BOOL authorizeRepositoryWrite(HttpRequest *request, HttpResponse *response,
                                     NSString *collection, NSString *action) {
    if ([ATProtoPermissionScopeEvaluator evaluateRepoScopes:request.permissionScopes ?: @[]
                                               forCollection:collection
                                                      action:action]) {
        return YES;
    }
    response.statusCode = HttpStatusForbidden;
    [response setJsonBody:@{
        @"error": @"InsufficientScope",
        @"message": @"Token scope does not permit this repository write"
    }];
    return NO;
}

+ (void)registerRecordRoutesWithDispatcher:(XrpcDispatcher *)dispatcher
                                  services:(id<XrpcRoutePackServices>)services {
    id<PDSAdminController> adminController = services.adminController;
    PDSRecordService *recordService = services.recordService;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;

#pragma mark - com.atproto.repo.listRecords
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_listRecords handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = [request queryParamForKey:@"repo"];
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];

        if (!repo) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo parameter"}];
            return;
        }

        if (!collection) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection parameter"}];
            return;
        }

        NSString *did = nil;
        if ([repo hasPrefix:@"did:"]) {
            did = repo;
        } else {
            PDSDatabaseAccount *account = [serviceDatabases getAccountByHandle:repo error:nil];
            if (account) {
                did = account.did;
            } else {
                HandleResolver *handleResolver = [[HandleResolver alloc] init];
                __block NSString *resolvedDid = nil;
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [handleResolver resolveHandle:repo completion:^(NSString * _Nullable resolved, NSError * _Nullable error) {
                    resolvedDid = resolved;
                    dispatch_semaphore_signal(semaphore);
                }];
                dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
                did = resolvedDid;
            }
        }

        if (!did) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": [NSString stringWithFormat:@"Could not find repo: %@", repo]}];
            return;
        }

        if (rejectUnavailableRepoDid(did, services, response)) {
            return;
        }

        NSUInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit > 100) limit = 100;

        NSError *error = nil;
        NSArray *records = [recordService listRecords:collection forDid:did limit:limit cursor:cursor error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ListRecordsFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"records": records ?: @[]}];
    }];

#pragma mark - com.atproto.repo.getRecord
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_getRecord handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = [request queryParamForKey:@"repo"];
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *rkey = [request queryParamForKey:@"rkey"];

        if (!repo) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo parameter"}];
            return;
        }

        if (!collection || !rkey) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection or rkey parameter"}];
            return;
        }

        NSString *did = nil;
        if ([repo hasPrefix:@"did:"]) {
            did = repo;
        } else {
            PDSDatabaseAccount *account = [serviceDatabases getAccountByHandle:repo error:nil];
            if (account) {
                did = account.did;
            } else {
                HandleResolver *handleResolver = [[HandleResolver alloc] init];
                __block NSString *resolvedDid = nil;
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [handleResolver resolveHandle:repo completion:^(NSString * _Nullable resolved, NSError * _Nullable error) {
                    resolvedDid = resolved;
                    dispatch_semaphore_signal(semaphore);
                }];
                dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
                did = resolvedDid;
            }
        }

        if (!did) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": [NSString stringWithFormat:@"Could not find repo: %@", repo]}];
            return;
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        if (rejectRecordTakedown(uri, services, response)) {
            return;
        }
        GZ_LOG_INFO(@"getRecord: resolving uri=%@ for did=%@", uri, did);
        NSError *error = nil;
        NSDictionary *record = [recordService getRecord:uri forDid:did error:&error];

        if (error || !record) {
            GZ_LOG_INFO(@"getRecord: not found uri=%@ (error=%@)", uri, error.localizedDescription);
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RecordNotFound", @"message": @"Record not found"}];
            return;
        }

        if (rejectUnavailableRepoDidIfKnown(did, services, response)) {
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:record];
    }];

#pragma mark - com.atproto.repo.createRecord
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_createRecord handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSString *collection = [request stringBodyForKey:@"collection"];
        NSDictionary *record = [request stringBodyForKey:@"record"] ? nil : request.jsonBody[@"record"];
        NSString *rkey = [request stringBodyForKey:@"rkey"];
        NSString *repo = [request stringBodyForKey:@"repo"];
        NSString *swapCommit = [request stringBodyForKey:@"swapCommit"];
        NSString *swapRecord = [request stringBodyForKey:@"swapRecord"];
        PDSValidationMode mode = validationModeFromValidateParameter(request.jsonBody[@"validate"]);

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot create record for another user"}];
            return;
        }

        if (rejectUnavailableRepoDid(did, services, response)) {
            return;
        }

        if (!collection || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection or record"}];
            return;
        }
        if (!authorizeRepositoryWrite(request, response, collection, @"create")) return;

        NSDictionary *write = @{
            @"action": @"create",
            @"collection": collection,
            @"rkey": rkey ?: @"",
            @"value": record
        };

        NSError *error = nil;
        NSDictionary *result = [recordService applyWrites:@[write]
                                                   forDid:did
                                           validationMode:mode
                                               swapCommit:swapCommit
                                                    error:&error];
        if (!result) {
            response.statusCode = HttpStatusBadRequest;
            if (isReplyNotAllowedError(error)) {
                [response setJsonBody:@{@"error": @"ReplyNotAllowed", @"message": @"Reply not allowed by threadgate"}];
            } else {
                [response setJsonBody:@{@"error": @"RecordCreationFailed", @"message": error.localizedDescription ?: @"Failed to create record"}];
            }
            return;
        }

        NSArray *resultsArray = result[@"results"];
        NSDictionary *firstResult = resultsArray.count > 0 ? resultsArray.firstObject : nil;
        
        NSMutableDictionary *resBody = [NSMutableDictionary dictionary];
        if (firstResult[@"uri"]) resBody[@"uri"] = firstResult[@"uri"];
        if (firstResult[@"cid"]) resBody[@"cid"] = firstResult[@"cid"];
        if (result[@"commit"]) resBody[@"commit"] = result[@"commit"];
        resBody[@"validationStatus"] = firstResult[@"validationStatus"] ?: @"valid";

        response.statusCode = HttpStatusOK;
        [response setJsonBody:resBody];
    }];

#pragma mark - com.atproto.repo.deleteRecord
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_deleteRecord handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSString *collection = [request stringBodyForKey:@"collection"];
        NSString *rkey = [request stringBodyForKey:@"rkey"];
        NSString *repo = [request stringBodyForKey:@"repo"];
        NSString *swapCommit = [request stringBodyForKey:@"swapCommit"];
        NSString *swapRecord = [request stringBodyForKey:@"swapRecord"];

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot delete record for another user"}];
            return;
        }

        if (rejectUnavailableRepoDid(did, services, response)) {
            return;
        }

        if (!collection || !rkey) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection or rkey"}];
            return;
        }
        if (!authorizeRepositoryWrite(request, response, collection, @"delete")) return;

        NSDictionary *write = @{
            @"action": @"delete",
            @"collection": collection,
            @"rkey": rkey,
            @"swapRecord": swapRecord ?: [NSNull null]
        };

        NSError *error = nil;
        NSDictionary *result = [recordService applyWrites:@[write]
                                                   forDid:did
                                           validationMode:PDSValidationModeOff
                                               swapCommit:swapCommit
                                                    error:&error];
        if (!result) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"RecordDeletionFailed", @"message": error.localizedDescription ?: @"Failed to delete record"}];
            return;
        }

        NSMutableDictionary *resBody = [NSMutableDictionary dictionary];
        if (result[@"commit"]) resBody[@"commit"] = result[@"commit"];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:resBody];
    }];

#pragma mark - com.atproto.repo.putRecord / updateRecord (shared upsert handler)
    XrpcMethodHandler upsertRecordHandler = ^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSString *collection = [request stringBodyForKey:@"collection"];
        NSString *rkey = [request stringBodyForKey:@"rkey"];
        NSDictionary *record = [request stringBodyForKey:@"record"] ? nil : request.jsonBody[@"record"];
        NSString *repo = [request stringBodyForKey:@"repo"];
        NSString *swapCommit = [request stringBodyForKey:@"swapCommit"];
        NSString *swapRecord = [request stringBodyForKey:@"swapRecord"];
        PDSValidationMode mode = validationModeFromValidateParameter(request.jsonBody[@"validate"]);

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot update record for another user"}];
            return;
        }

        if (rejectUnavailableRepoDid(did, services, response)) {
            return;
        }

        if (!collection || !rkey || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection, rkey, or record"}];
            return;
        }
        if (!authorizeRepositoryWrite(request, response, collection, @"update")) return;

        // putRecord is an upsert per ATProto spec: create the record if it
        // doesn't exist, or update it if it does.  We try "update" first;
        // if the record is not found we fall back to "create".
        NSDictionary *write = @{
            @"action": @"update",
            @"collection": collection,
            @"rkey": rkey,
            @"value": record,
            @"swapRecord": swapRecord ?: [NSNull null]
        };

        NSError *error = nil;
        NSDictionary *result = [recordService applyWrites:@[write]
                                                   forDid:did
                                           validationMode:mode
                                               swapCommit:swapCommit
                                                    error:&error];
        if (!result && error) {
            NSString *errMsg = error.localizedDescription ?: @"";
            if ([errMsg containsString:@"Record not found"] ||
                [errMsg containsString:@"not found"]) {
                // Upsert fallback: record doesn't exist yet, create it.
                NSDictionary *createWrite = @{
                    @"action": @"create",
                    @"collection": collection,
                    @"rkey": rkey,
                    @"value": record,
                };
                if (!authorizeRepositoryWrite(request, response, collection, @"create")) return;
                NSError *createError = nil;
                result = [recordService applyWrites:@[createWrite]
                                             forDid:did
                                     validationMode:mode
                                         swapCommit:swapCommit
                                              error:&createError];
                if (!result) {
                    response.statusCode = HttpStatusBadRequest;
                    if (isReplyNotAllowedError(createError)) {
                        [response setJsonBody:@{@"error": @"ReplyNotAllowed", @"message": @"Reply not allowed by threadgate"}];
                    } else {
                        [response setJsonBody:@{@"error": @"RecordCreateFailed",
                                                @"message": createError.localizedDescription ?: @"Failed to create record"}];
                    }
                    return;
                }
            } else {
                response.statusCode = HttpStatusBadRequest;
                if (isReplyNotAllowedError(error)) {
                    [response setJsonBody:@{@"error": @"ReplyNotAllowed", @"message": @"Reply not allowed by threadgate"}];
                } else {
                    [response setJsonBody:@{@"error": @"RecordUpdateFailed",
                                            @"message": errMsg}];
                }
                return;
            }
        } else if (!result) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"RecordUpdateFailed",
                                    @"message": @"Failed to update record"}];
            return;
        }

        NSArray *resultsArray = result[@"results"];
        NSDictionary *firstResult = resultsArray.count > 0 ? resultsArray.firstObject : nil;
        
        NSMutableDictionary *resBody = [NSMutableDictionary dictionary];
        if (firstResult[@"uri"]) resBody[@"uri"] = firstResult[@"uri"];
        if (firstResult[@"cid"]) resBody[@"cid"] = firstResult[@"cid"];
        if (result[@"commit"]) resBody[@"commit"] = result[@"commit"];
        resBody[@"validationStatus"] = firstResult[@"validationStatus"] ?: @"valid";

        response.statusCode = HttpStatusOK;
        [response setJsonBody:resBody];
    };

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_putRecord handler:upsertRecordHandler];
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_updateRecord handler:upsertRecordHandler];

#pragma mark - com.atproto.repo.applyWrites
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_applyWrites handler:^(HttpRequest *request, HttpResponse *response) {
        if (!request.jsonBody) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSArray *writes = [request arrayBodyForKey:@"writes"];
        NSString *repo = [request stringBodyForKey:@"repo"];
        PDSValidationMode mode = validationModeFromValidateParameter(request.jsonBody[@"validate"]);
        NSString *swapCommit = [request stringBodyForKey:@"swapCommit"];

        GZ_LOG_INFO(@"applyWrites: did=%@ writeCount=%lu validationMode=%ld",
                    did,
                    (unsigned long)([writes isKindOfClass:[NSArray class]] ? [(NSArray *)writes count] : 0),
                    (long)mode);

        if (![repo isKindOfClass:[NSString class]] || repo.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": @"Missing repo"
            }];
            return;
        }

        if (![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot apply writes for another user"}];
            return;
        }

        if (rejectUnavailableRepoDid(did, services, response)) {
            return;
        }

        NSError *writeValidationError = nil;
        if (!validateApplyWritesPayload(writes, &writeValidationError)) {
            response.statusCode = (writeValidationError.code == PDSRepoPackValidationErrorPayloadTooLarge)
                ? HttpStatusPayloadTooLarge
                : HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": (response.statusCode == HttpStatusPayloadTooLarge) ? @"PayloadTooLarge" : @"InvalidRequest",
                @"message": writeValidationError.localizedDescription ?: @"Invalid writes array"
            }];
            return;
        }
        NSMutableArray<NSDictionary *> *normalizedWrites =
            [NSMutableArray arrayWithCapacity:writes.count];
        for (NSDictionary *write in writes) {
            NSString *action = normalizedApplyWriteAction(write);
            if (!authorizeRepositoryWrite(request, response, write[@"collection"], action)) return;
            NSMutableDictionary *normalizedWrite = [write mutableCopy];
            normalizedWrite[@"action"] = action;
            [normalizedWrites addObject:normalizedWrite];
        }

        NSError *error = nil;
        NSDictionary *result = [recordService applyWrites:normalizedWrites
                                                   forDid:did
                                          validationMode:mode
                                               swapCommit:swapCommit
                                                    error:&error];
        if (!result) {
            GZ_LOG_INFO(@"applyWrites: did=%@ writeCount=%lu result=failed", did, (unsigned long)[writes count]);
            response.statusCode = HttpStatusBadRequest;
            if (isReplyNotAllowedError(error)) {
                [response setJsonBody:@{@"error": @"ReplyNotAllowed", @"message": @"Reply not allowed by threadgate"}];
            } else {
                [response setJsonBody:@{@"error": @"WriteFailed", @"message": error.localizedDescription ?: @"Failed to apply writes"}];
            }
            return;
        }

        GZ_LOG_INFO(@"applyWrites: did=%@ writeCount=%lu result=ok", did, (unsigned long)[writes count]);
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
}

@end
