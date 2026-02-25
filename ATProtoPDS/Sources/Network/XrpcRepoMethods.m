#import "Network/XrpcRepoMethods.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcMethodRegistry.h"
#import "App/Services/PDSAccountService.h"
#import "App/Services/PDSRecordService.h"
#import "App/Services/PDSBlobService.h"
#import "App/Services/PDSRepositoryService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Identity/HandleResolver.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/DID.h"
#import "Core/TID.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "App/PDSConfiguration.h"

static BOOL parseStrictIntegerString(NSString *value, NSInteger *result);

static NSString *trimmedNonEmptyString(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

static BOOL parseStrictIntegerString(NSString *value, NSInteger *result) {
    NSString *trimmed = trimmedNonEmptyString(value);
    if (trimmed.length == 0) {
        return NO;
    }

    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    scanner.charactersToBeSkipped = nil;
    
    NSInteger parsed = 0;
    if (![scanner scanInteger:&parsed] || !scanner.isAtEnd) {
        return NO;
    }

    if (result) {
        *result = parsed;
    }
    return YES;
}

static NSString *normalizedAtHandleFromAlsoKnownAs(NSArray<NSString *> *alsoKnownAs) {
    if (!alsoKnownAs || alsoKnownAs.count == 0) {
        return nil;
    }
    
    for (NSString *aka in alsoKnownAs) {
        if (![aka isKindOfClass:[NSString class]]) {
            continue;
        }
        if ([aka hasPrefix:@"at://"]) {
            NSString *handle = [aka substringFromIndex:5];
            return [handle lowercaseString];
        }
    }
    return nil;
}

@implementation XrpcRepoMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
                accountService:(id<PDSAccountService>)accountService
                 recordService:(PDSRecordService *)recordService
                   blobService:(PDSBlobService *)blobService
             repositoryService:(PDSRepositoryService *)repositoryService
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases {
    
    // com.atproto.repo.listRecords
    [dispatcher registerComAtprotoRepoListRecords:^(HttpRequest *request, HttpResponse *response) {
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

    // com.atproto.repo.getRecord
    [dispatcher registerComAtprotoRepoGetRecord:^(HttpRequest *request, HttpResponse *response) {
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
        NSError *error = nil;
        NSDictionary *record = [recordService getRecord:uri forDid:did error:&error];

        if (error || !record) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RecordNotFound", @"message": @"Record not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:record];
    }];

    // com.atproto.repo.createRecord
    [dispatcher registerComAtprotoRepoCreateRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *collection = body[@"collection"];
        NSDictionary *record = body[@"record"];
        NSString *rkey = body[@"rkey"];
        NSString *repo = body[@"repo"];
        BOOL validate = [body[@"validate"] boolValue];

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot create record for another user"}];
            return;
        }

        if (!collection || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection or record"}];
            return;
        }

        if (!rkey) {
            rkey = [[TID tid] stringValue];
        }

        PDSValidationMode mode = validate ? PDSValidationModeRequired : PDSValidationModeOff;
        NSError *error = nil;
        BOOL success = [recordService putRecord:collection rkey:rkey value:record forDid:did validationMode:mode error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"RecordCreationFailed", @"message": error.localizedDescription ?: @"Failed to create record"}];
            return;
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        NSDictionary *createdRecord = [recordService getRecord:uri forDid:did error:nil];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:createdRecord ?: @{@"uri": uri}];
    }];

    // com.atproto.repo.deleteRecord
    [dispatcher registerComAtprotoRepoDeleteRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *collection = body[@"collection"];
        NSString *rkey = body[@"rkey"];
        NSString *repo = body[@"repo"];

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot delete record for another user"}];
            return;
        }

        if (!collection || !rkey) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection or rkey"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [recordService deleteRecord:collection rkey:rkey forDid:did error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"RecordDeletionFailed", @"message": error.localizedDescription ?: @"Failed to delete record"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"uri": [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey]}];
    }];

    // com.atproto.repo.uploadBlob
    [dispatcher registerComAtprotoRepoUploadBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSData *blobData = request.body;
        if (!blobData || blobData.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing blob data"}];
            return;
        }

        if (blobData.length > 1 * 1024 * 1024) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BlobTooLarge", @"message": @"Blob too large"}];
            return;
        }

        NSString *contentType = [request headerForKey:@"Content-Type"];
        if (contentType && [contentType isEqualToString:@"application/x-msdownload"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidMimeType", @"message": @"Forbidden MIME type"}];
            return;
        }
        NSError *error = nil;
        NSDictionary *result = [blobService uploadBlob:blobData
                                                forDid:did
                                              mimeType:contentType ?: @"application/octet-stream"
                                                 error:&error];
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BlobUploadFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // com.atproto.repo.deleteBlob
    [dispatcher registerComAtprotoRepoDeleteBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *cid = body[@"blob"];
        if (!cid) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing blob CID"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [blobService deleteBlobWithCID:cid did:did error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BlobDeletionFailed", @"message": error.localizedDescription ?: @"Failed to delete blob"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // com.atproto.repo.listMissingBlobs
    [dispatcher registerComAtprotoRepoListMissingBlobs:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSString *limitParam = [request queryParamForKey:@"limit"];
        NSInteger limit = 500;
        if (limitParam.length > 0) {
            if (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 1000) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 1000"}];
                return;
            }
        }

        NSMutableDictionary *result = [@{@"blobs": @[]} mutableCopy];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        if (cursor.length > 0) {
            result[@"cursor"] = cursor;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // com.atproto.repo.importRepo
    [dispatcher registerComAtprotoRepoImportRepo:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSString *contentType = [request headerForKey:@"Content-Type"] ?: @"";
        if (![contentType hasPrefix:@"application/vnd.ipld.car"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Expected application/vnd.ipld.car content type"}];
            return;
        }

        NSString *contentLengthHeader = [request headerForKey:@"Content-Length"];
        NSInteger contentLength = 0;
        if (contentLengthHeader.length == 0 || !parseStrictIntegerString(contentLengthHeader, &contentLength) || contentLength <= 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid Content-Length header"}];
            return;
        }

        NSData *body = request.body;
        if (body.length == 0 || body.length != (NSUInteger)contentLength) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Body length does not match Content-Length"}];
            return;
        }

        response.statusCode = 501;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"repo.importRepo is not yet supported"}];
    }];

    // com.atproto.repo.describeRepo
    [dispatcher registerComAtprotoRepoDescribeRepo:^(HttpRequest *request, HttpResponse *response) {
        // Per lexicon: does not require auth.
        NSString *identifier = [request queryParamForKey:@"repo"] ?: @"";
        if (identifier.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo"}];
            return;
        }

        NSString *did = nil;
        PDSDatabaseAccount *localAccount = nil;
        if ([identifier hasPrefix:@"did:"]) {
            did = identifier;
            localAccount = [serviceDatabases getAccountByDid:did error:nil];
        } else {
            NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:identifier];
            localAccount = [serviceDatabases getAccountByHandle:normalizedHandle error:nil];
            did = localAccount.did;
        }

        if (!localAccount) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
            return;
        }

        NSDictionary *stats = [recordService getRepoStatsForDid:did error:nil];

        // Resolve full DID document (required by lexicon).
        DIDDocument *doc = [[DIDResolver sharedResolver] resolveDIDSync:did error:nil];
        NSDictionary *didDocJson = doc.jsonDictionary ?: @{};

        NSString *handleFromDidDoc = normalizedAtHandleFromAlsoKnownAs(doc.alsoKnownAs);
        NSString *accountHandle = localAccount.handle.length > 0 ? [localAccount.handle lowercaseString] : @"handle.invalid";
        BOOL handleIsCorrect = (handleFromDidDoc.length > 0 && [handleFromDidDoc isEqualToString:accountHandle]);

        NSMutableArray *collections = [NSMutableArray array];
        if ([stats[@"collections"] isKindOfClass:[NSArray class]]) {
            for (NSDictionary *col in stats[@"collections"]) {
                if ([col isKindOfClass:[NSDictionary class]] && [col[@"collection"] isKindOfClass:[NSString class]]) {
                    [collections addObject:col[@"collection"]];
                }
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"handle": accountHandle,
            @"did": did,
            @"didDoc": didDocJson,
            @"collections": collections,
            @"handleIsCorrect": @(handleIsCorrect)
        }];
    }];

    // com.atproto.repo.putRecord
    [dispatcher registerComAtprotoRepoPutRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *collection = body[@"collection"];
        NSString *rkey = body[@"rkey"];
        NSDictionary *record = body[@"record"];
        NSString *repo = body[@"repo"];
        BOOL validate = [body[@"validate"] boolValue];

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot update record for another user"}];
            return;
        }

        if (!collection || !rkey || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection, rkey, or record"}];
            return;
        }

        PDSValidationMode mode = validate ? PDSValidationModeRequired : PDSValidationModeOff;
        NSError *error = nil;
        BOOL success = [recordService putRecord:collection rkey:rkey value:record forDid:did validationMode:mode error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"RecordUpdateFailed", @"message": error.localizedDescription ?: @"Failed to update record"}];
            return;
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"uri": uri}];
    }];

    // com.atproto.repo.applyWrites
    [dispatcher registerComAtprotoRepoApplyWrites:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        if (!body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSArray *writes = body[@"writes"];
        NSString *repo = body[@"repo"];
        BOOL validate = [body[@"validate"] boolValue];
        NSString *swapCommit = body[@"swapCommit"];

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot apply writes for another user"}];
            return;
        }

        if (!writes || ![writes isKindOfClass:[NSArray class]]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid writes array"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [recordService applyWrites:writes
                                                   forDid:did
                                                 validate:validate
                                               swapCommit:swapCommit
                                                    error:&error];
        if (!result) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"WriteFailed", @"message": error.localizedDescription ?: @"Failed to apply writes"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
}

@end
