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
#import "Repository/CAR.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Auth/Secp256k1.h"
#import <CommonCrypto/CommonDigest.h>

static BOOL parseStrictIntegerString(NSString *value, NSInteger *result);

static PDSValidationMode validationModeFromValidateParameter(id validateParam) {
    if (!validateParam || validateParam == (id)[NSNull null]) {
        // Per lexicon: unset -> validate only for known Lexicons.
        return PDSValidationModeOptimistic;
    }
    if ([validateParam isKindOfClass:[NSNumber class]]) {
        return [validateParam boolValue] ? PDSValidationModeRequired : PDSValidationModeOff;
    }
    if ([validateParam isKindOfClass:[NSString class]]) {
        NSString *lower = [(NSString *)validateParam lowercaseString];
        if ([lower isEqualToString:@"true"]) return PDSValidationModeRequired;
        if ([lower isEqualToString:@"false"]) return PDSValidationModeOff;
    }
    // Default to optimistic to avoid surprising hard failures on unknown types.
    return PDSValidationModeOptimistic;
}

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

static void importRepoExtractRecords(NSData *mstRootCIDBytes, NSString *did, CARReader *reader, PDSActorStore *store, PDSRecordService *recordService, NSString *rev);

static void walkMST(CID *nodeCID, NSString *prevKey, NSString *did, CARReader *reader, NSMutableArray<PDSDatabaseRecord *> *recordList, NSString *rev) {
    if (!nodeCID) return;
    CARBlock *block = [reader blockWithCID:nodeCID];
    if (!block) return;
    
    NSDictionary *node = [ATProtoCBORSerialization JSONObjectWithData:block.data error:nil];
    if (![node isKindOfClass:[NSDictionary class]]) return;
    
    // ATProto MST node structure: { "e": [ ... ], "l": <cid_link> }
    
    // Recurse left
    id leftLink = node[@"l"];
    if ([leftLink isKindOfClass:[NSDictionary class]]) {
        NSData *leftCIDBytes = leftLink[@"/"];
        if ([leftCIDBytes isKindOfClass:[NSData class]]) {
            walkMST([CID cidFromBytes:leftCIDBytes], prevKey, did, reader, recordList, rev);
        }
    }
    
    // Iterate entries
    NSArray *entries = node[@"e"];
    if (![entries isKindOfClass:[NSArray class]]) return;
    
    NSString *currentPrevKey = prevKey;
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        
        // entry: { "k": <bytes_suffix>, "p": <prefix_len>, "t": <tree_cid_link>, "v": <value_cid_link> }
        NSUInteger p = [entry[@"p"] unsignedIntegerValue];
        NSData *kSuffix = entry[@"k"];
        if (![kSuffix isKindOfClass:[NSData class]]) continue;
        
        NSString *suffixStr = [[NSString alloc] initWithData:kSuffix encoding:NSUTF8StringEncoding];
        if (!suffixStr) continue;
        
        NSString *fullKey = [currentPrevKey substringToIndex:MIN(p, currentPrevKey.length)];
        fullKey = [fullKey stringByAppendingString:suffixStr];
        
        // Extract record
        id vLink = entry[@"v"];
        if ([vLink isKindOfClass:[NSDictionary class]]) {
            NSData *vCIDBytes = vLink[@"/"];
            if ([vCIDBytes isKindOfClass:[NSData class]]) {
                CID *vCID = [CID cidFromBytes:vCIDBytes];
                if (vCID) {
                    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
                    record.did = did;
                    record.cid = vCID.stringValue;
                    record.rev = rev;
                    record.createdAt = [NSDate date];
                    
                    // Split key into collection/rkey
                    NSRange slashRange = [fullKey rangeOfString:@"/"];
                    if (slashRange.location != NSNotFound) {
                        record.collection = [fullKey substringToIndex:slashRange.location];
                        record.rkey = [fullKey substringFromIndex:slashRange.location + 1];
                    } else {
                        record.collection = @"unknown";
                        record.rkey = fullKey;
                    }
                    record.uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, record.collection, record.rkey];
                    
                    // Decode value to JSON string
                    CARBlock *vBlock = [reader blockWithCID:vCID];
                    if (vBlock) {
                        id jsonObj = [ATProtoCBORSerialization JSONObjectWithData:vBlock.data error:nil];
                        if (jsonObj) {
                            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObj options:0 error:nil];
                            if (jsonData) {
                                record.value = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                            }
                        }
                    }
                    
                    [recordList addObject:record];
                }
            }
        }
        
        // Recurse subtree (right)
        id tLink = entry[@"t"];
        if ([tLink isKindOfClass:[NSDictionary class]]) {
            NSData *tCIDBytes = tLink[@"/"];
            if ([tCIDBytes isKindOfClass:[NSData class]]) {
                walkMST([CID cidFromBytes:tCIDBytes], fullKey, did, reader, recordList, rev);
            }
        }
        
        currentPrevKey = fullKey;
    }
}

static void importRepoExtractRecords(NSData *mstRootCIDBytes, NSString *did, CARReader *reader, PDSActorStore *store, PDSRecordService *recordService, NSString *rev) {
    NSMutableArray<PDSDatabaseRecord *> *recordList = [NSMutableArray array];
    CID *rootCID = [CID cidFromBytes:mstRootCIDBytes];
    if (!rootCID) return;
    
    walkMST(rootCID, @"", did, reader, recordList, rev);
    
    if (recordList.count > 0) {
        [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **error) {
            [transactor putRecords:recordList forDid:did error:error];
        } error:nil];
    }
}

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
        PDSValidationMode mode = validationModeFromValidateParameter(body[@"validate"]);

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

        // Parse the incoming CAR file
        NSError *carError = nil;
        CARReader *reader = [CARReader readFromData:body error:&carError];
        if (!reader) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest",
                                    @"message": [NSString stringWithFormat:@"Failed to parse CAR: %@",
                                                 carError.localizedDescription ?: @"unknown error"]}];
            return;
        }

        if (!reader.rootCID) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"CAR has no root CID"}];
            return;
        }

        if (reader.blocks.count == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"CAR contains no blocks"}];
            return;
        }

        // Find the root (commit) block
        CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
        if (!commitBlock) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Root block not found in CAR"}];
            return;
        }

        // Decode the commit to verify structure
        NSDictionary *commitData = [ATProtoCBORSerialization JSONObjectWithData:commitBlock.data error:nil];
        if (!commitData) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Failed to decode commit block"}];
            return;
        }

        // Verify DID matches authenticated user
        NSString *commitDid = commitData[@"did"];
        if (commitDid && ![commitDid isEqualToString:did]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest",
                                    @"message": @"CAR commit DID does not match authenticated user"}];
            return;
        }

        // Verify signature
        NSData *sig = commitData[@"sig"];
        if (![sig isKindOfClass:[NSData class]]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Commit is missing signature"}];
            return;
        }

        // Resolve DID to get public key
        NSError *resolveError = nil;
        NSDictionary *atprotoData = [[DIDResolver sharedResolver] resolveAtprotoDataForDID:did error:&resolveError];
        NSData *pubKey = atprotoData[@"signingKeyBytes"];
        if (!pubKey) {
             response.statusCode = HttpStatusBadRequest;
             [response setJsonBody:@{@"error": @"InvalidRequest",
                                     @"message": [NSString stringWithFormat:@"Failed to resolve signing key for %@: %@",
                                                  did, resolveError.localizedDescription ?: @"not found"]}];
             return;
        }

        // Prepare signing input (commit block without sig field)
        NSMutableDictionary *signingData = [commitData mutableCopy];
        [signingData removeObjectForKey:@"sig"];
        NSData *signingInput = [ATProtoCBORSerialization dataWithJSONObject:signingData error:nil];
        if (!signingInput) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": @"Failed to re-encode commit for verification"}];
            return;
        }

        // Compute SHA256 of signing input
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(signingInput.bytes, (CC_LONG)signingInput.length, hash);
        NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];

        // Verify signature
        NSError *verifyError = nil;
        BOOL sigValid = [[Secp256k1 shared] verifySignature:sig forHash:hashData withPublicKey:pubKey error:&verifyError];
        if (!sigValid) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest",
                                    @"message": [NSString stringWithFormat:@"Commit signature verification failed: %@",
                                                 verifyError.localizedDescription ?: @"invalid signature"]}];
            return;
        }

        // Extract revision from commit
        NSString *rev = commitData[@"rev"];
        if (!rev || ![rev isKindOfClass:[NSString class]] || rev.length == 0) {
            rev = [TID tid].stringValue;
        }

        // Get the actor store
        NSError *storeError = nil;
        PDSActorStore *store = [repositoryService.databasePool storeForDid:did error:&storeError];
        if (!store) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError",
                                    @"message": @"Failed to access actor store"}];
            return;
        }

        // Convert CAR blocks to database blocks and store them
        NSMutableArray<PDSDatabaseBlock *> *dbBlocks = [NSMutableArray arrayWithCapacity:reader.blocks.count];
        for (CARBlock *carBlock in reader.blocks) {
            // Validate CID integrity: compute CID from data and compare
            PDSDatabaseBlock *dbBlock = [[PDSDatabaseBlock alloc] init];
            dbBlock.cid = carBlock.cid.bytes;
            dbBlock.repoDid = did;
            dbBlock.blockData = carBlock.data;
            dbBlock.contentType = @"application/vnd.ipld.dag-cbor";
            dbBlock.size = (NSInteger)carBlock.data.length;
            dbBlock.createdAt = [NSDate date];
            dbBlock.rev = rev;
            [dbBlocks addObject:dbBlock];
        }

        // Store all blocks and update repo root in a single transaction
        __block BOOL importSuccess = NO;
        [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            // Store all blocks
            if (![transactor putBlocks:dbBlocks forDid:did error:blockError]) {
                return;
            }

            // Update the repo root to point at the commit CID
            if (![transactor updateRepoRoot:did
                                    rootCid:reader.rootCID.bytes
                                        rev:rev
                                      error:blockError]) {
                return;
            }

            importSuccess = YES;
        } error:&storeError];

        if (!importSuccess) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError",
                                    @"message": [NSString stringWithFormat:@"Failed to import: %@",
                                                 storeError.localizedDescription ?: @"unknown"]}];
            return;
        }

        // Walk the MST blocks to extract records and store them as record entries
        // The commit's "data" field contains a CID link to the MST root
        id dataField = commitData[@"data"];
        NSData *mstRootCIDBytes = nil;
        if ([dataField isKindOfClass:[NSDictionary class]]) {
            // CBOR CID link: { "/": <bytes> }
            NSData *linkBytes = dataField[@"/"];
            if ([linkBytes isKindOfClass:[NSData class]]) {
                mstRootCIDBytes = linkBytes;
            } else {
                NSString *linkStr = dataField[@"/"];
                if ([linkStr isKindOfClass:[NSString class]]) {
                    CID *linkCID = [CID cidFromString:linkStr];
                    mstRootCIDBytes = linkCID.bytes;
                }
            }
        }

        // Extract records by iterating the MST
        if (mstRootCIDBytes) {
            importRepoExtractRecords(mstRootCIDBytes, did, reader, store, recordService, rev);
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
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
        PDSValidationMode mode = validationModeFromValidateParameter(body[@"validate"]);

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
        PDSValidationMode mode = validationModeFromValidateParameter(body[@"validate"]);
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
                                          validationMode:mode
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
