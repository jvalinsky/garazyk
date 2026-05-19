// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcRepoPack.h"
#import "Admin/PDSAdminController.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/RateLimiter.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSRecordService.h"
#import "Services/PDS/PDSBlobService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/GZLogger.h"
#import "Database/PDSDatabase.h"
#import "Identity/HandleResolver.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/DID.h"
#import "Core/TID.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Repository/CAR.h"
#import "Repository/STAR.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Repository/CBOR.h"
#import "Repository/RepoCommit.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Auth/Secp256k1.h"
#import <CommonCrypto/CommonDigest.h>

static const NSUInteger kPDSUploadBlobDefaultMaxBytes = 1024 * 1024;
static const NSUInteger kPDSUploadBlobVideoMaxBytes = 50 * 1024 * 1024;

static BOOL parseStrictIntegerString(NSString *value, NSInteger *result);
static CID *cidFromTaggedCBORValue(CBORValue *value);

static BOOL isReplyNotAllowedError(NSError *error) {
    return [error.localizedDescription containsString:@"ReplyNotAllowed"];
}

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

static NSUInteger maxUploadBlobBytesForContentType(NSString *contentType) {
    NSString *lowerContentType = [[contentType ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *mimeType = [lowerContentType componentsSeparatedByString:@";"].firstObject ?: @"";
    if ([mimeType isEqualToString:@"video/mp4"]) {
        return kPDSUploadBlobVideoMaxBytes;
    }
    return kPDSUploadBlobDefaultMaxBytes;
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

@implementation XrpcRepoPack

+ (NSString *)routePackIdentifier {
  return @"com.atproto.repo";
}

static NSArray<PDSDatabaseRecord *> *importRepoExtractRecords(NSData *mstRootCIDBytes, NSString *did, CARReader *reader, NSString *rev);

static CID *cidFromTaggedCBORValue(CBORValue *value) {
    if (!value) {
        return nil;
    }

    if (value.type == CBORTypeSimpleOrFloat &&
        value.simpleValue &&
        value.simpleValue.unsignedIntegerValue == 22) {
        return nil;
    }

    if (value.type != CBORTypeTag || !value.tagValue || value.tagValue.type != CBORTypeByteString) {
        return nil;
    }

    NSData *bytes = value.tagValue.byteString;
    if (!bytes || bytes.length <= 1) {
        return nil;
    }

    NSData *cidBytes = [bytes subdataWithRange:NSMakeRange(1, bytes.length - 1)];
    return [CID cidFromBytes:cidBytes];
}

static void walkMST(CID *nodeCID, NSString *prevKey, NSString *did, CARReader *reader, NSMutableArray<PDSDatabaseRecord *> *recordList, NSString *rev) {
    if (!nodeCID) return;
    CARBlock *block = [reader blockWithCID:nodeCID];
    if (!block) return;

    CBORValue *nodeValue = [CBORValue decode:block.data];
    if (!nodeValue || nodeValue.type != CBORTypeMap) return;

    // Recurse left subtree first to preserve in-order traversal.
    CBORValue *leftTag = nodeValue.map[[CBORValue textString:@"l"]];
    CID *leftCID = cidFromTaggedCBORValue(leftTag);
    if (leftCID) {
        walkMST(leftCID, prevKey, did, reader, recordList, rev);
    }

    CBORValue *entriesValue = nodeValue.map[[CBORValue textString:@"e"]];
    NSArray<CBORValue *> *entriesArray = (entriesValue && entriesValue.type == CBORTypeArray)
                                             ? entriesValue.array
                                             : @[];

    NSString *currentPrevKey = prevKey ?: @"";
    for (CBORValue *entryMap in entriesArray) {
        if (entryMap.type != CBORTypeMap) continue;

        NSData *suffixData = entryMap.map[[CBORValue textString:@"k"]].byteString ?: [NSData data];
        CBORValue *prefixValue = entryMap.map[[CBORValue textString:@"p"]];
        NSUInteger prefixLen = prefixValue.unsignedInteger.unsignedIntegerValue;
        NSUInteger safePrefixLen = MIN(prefixLen, currentPrevKey.length);
        NSString *prefix = [currentPrevKey substringToIndex:safePrefixLen];
        NSString *suffix = [[NSString alloc] initWithData:suffixData encoding:NSUTF8StringEncoding] ?: @"";
        NSString *fullKey = [prefix stringByAppendingString:suffix];

        CBORValue *valueTag = entryMap.map[[CBORValue textString:@"v"]];
        CID *valueCID = cidFromTaggedCBORValue(valueTag);
        if (valueCID) {
            PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
            record.did = did;
            record.cid = valueCID.stringValue;
            record.rev = rev;
            record.createdAt = [NSDate date];

            NSRange slashRange = [fullKey rangeOfString:@"/"];
            if (slashRange.location != NSNotFound) {
                record.collection = [fullKey substringToIndex:slashRange.location];
                record.rkey = [fullKey substringFromIndex:slashRange.location + 1];
            } else {
                record.collection = @"unknown";
                record.rkey = fullKey;
            }
            record.uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, record.collection, record.rkey];

            CARBlock *valueBlock = [reader blockWithCID:valueCID];
            if (valueBlock) {
                id jsonObj = [ATProtoCBORSerialization JSONObjectWithData:valueBlock.data error:nil];
                if (jsonObj) {
                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObj options:0 error:nil];
                    if (jsonData) {
                        record.value = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                    }
                }
            }
            [recordList addObject:record];
        }

        CBORValue *treeTag = entryMap.map[[CBORValue textString:@"t"]];
        CID *treeCID = cidFromTaggedCBORValue(treeTag);
        if (treeCID) {
            walkMST(treeCID, fullKey, did, reader, recordList, rev);
        }

        currentPrevKey = fullKey;
    }
}

static NSArray<PDSDatabaseRecord *> *importRepoExtractRecords(NSData *mstRootCIDBytes, NSString *did, CARReader *reader, NSString *rev) {
    NSMutableArray<PDSDatabaseRecord *> *recordList = [NSMutableArray array];
    CID *rootCID = [CID cidFromBytes:mstRootCIDBytes];
    if (!rootCID) return @[];
    
    walkMST(rootCID, @"", did, reader, recordList, rev);

    return [recordList copy];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
    
    JWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    PDSRecordService *recordService = services.recordService;
    PDSBlobService *blobService = services.blobService;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    RateLimiter *rateLimiter = services.rateLimiter;
    
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

        NSError *takedownError = nil;
        if ([adminController isAccountTakedownActive:did error:&takedownError]) {
            response.statusCode = HttpStatusGone;
            [response setJsonBody:@{
                @"error": @"AccountTakedown",
                @"message": @"Repository has been taken down by the host",
            }];
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

        NSError *takedownError = nil;
        if ([adminController isAccountTakedownActive:did error:&takedownError]) {
            response.statusCode = HttpStatusGone;
            [response setJsonBody:@{
                @"error": @"AccountTakedown",
                @"message": @"Repository has been taken down by the host",
            }];
            return;
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        GZ_LOG_INFO(@"getRecord: resolving uri=%@ for did=%@", uri, did);
        NSError *error = nil;
        NSDictionary *record = [recordService getRecord:uri forDid:did error:&error];

        if (error || !record) {
            GZ_LOG_INFO(@"getRecord: not found uri=%@ (error=%@)", uri, error.localizedDescription);
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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
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
        NSString *swapCommit = body[@"swapCommit"];
        NSString *swapRecord = body[@"swapRecord"];
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

    // com.atproto.repo.deleteRecord
    [dispatcher registerComAtprotoRepoDeleteRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
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
        NSString *swapCommit = body[@"swapCommit"];
        NSString *swapRecord = body[@"swapRecord"];

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

    // com.atproto.repo.uploadBlob
    [dispatcher registerComAtprotoRepoUploadBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
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

        NSString *contentType = [request headerForKey:@"Content-Type"];
        NSUInteger maxUploadBytes = maxUploadBlobBytesForContentType(contentType);
        if (blobData.length > maxUploadBytes) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BlobTooLarge", @"message": @"Blob too large"}];
            return;
        }

        if (contentType && [contentType isEqualToString:@"application/x-msdownload"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidMimeType", @"message": @"Forbidden MIME type"}];
            return;
        }

        RateLimitResult *blobRateLimit = [rateLimiter checkBlobUploadRateLimitForDid:did];
        if (!blobRateLimit.allowed) {
            response.statusCode = HttpStatusTooManyRequests;
            [response setHeader:[NSString stringWithFormat:@"%ld", (long)blobRateLimit.limit] forKey:@"X-RateLimit-Limit"];
            [response setHeader:[NSString stringWithFormat:@"%ld", (long)blobRateLimit.remaining] forKey:@"X-RateLimit-Remaining"];
            [response setHeader:[NSString stringWithFormat:@"%.0f", blobRateLimit.resetSeconds] forKey:@"X-RateLimit-Reset"];
            [response setHeader:[NSString stringWithFormat:@"%.0f", blobRateLimit.retryAfter] forKey:@"Retry-After"];
            [response setJsonBody:@{@"error": @"RateLimitExceeded", @"message": @"Blob upload rate limit exceeded"}];
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

    // com.atproto.repo.listMissingBlobs
    [dispatcher registerComAtprotoRepoListMissingBlobs:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
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

    // com.atproto.repo.getBlob - Auth-gated wrapper that delegates to sync.getBlob
    [dispatcher registerComAtprotoRepoGetBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSString *cid = [request queryParamForKey:@"cid"];
        if (cid.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing cid"}];
            return;
        }

        NSString *didParam = [request queryParamForKey:@"did"];
        NSString *blobDid = didParam.length > 0 ? didParam : did;
        if (![blobDid isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot fetch blob for another user"}];
            return;
        }

        // Check if CDN redirect is enabled (Phase 5)
        ATProtoServiceConfiguration *configuration = [ATProtoServiceConfiguration sharedConfiguration];
        NSString *cdnURL = [configuration stringForKey:@"cdnURL"];
        if (cdnURL && cdnURL.length > 0) {
            // Return 302 Found redirect to CDN URL
            NSString *cdnBlobURL = [NSString stringWithFormat:@"%@/%@", cdnURL, cid];
            response.statusCode = 302; // Found (temporary redirect)
            [response setHeader:cdnBlobURL forKey:@"Location"];
            [response setJsonBody:@{
                @"message" : @"Blob available at CDN",
                @"location" : cdnBlobURL
            }];
            return;
        }

        // Delegate to shared blob retrieval logic with Range support from sync.getBlob
        NSError *blobError = nil;
        NSDictionary *result = [blobService getBlobStreamWithCID:cid did:blobDid error:&blobError];
        if (!result && !blobError) {
            result = [blobService getBlobWithCID:cid did:blobDid error:&blobError];
        }
        if (!result) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"BlobRetrievalFailed",
                                    @"message": blobError.localizedDescription ?: @"Blob not found"}];
            return;
        }

        NSString *mimeType = [result[@"mimeType"] isKindOfClass:[NSString class]] && [result[@"mimeType"] length] > 0
                                 ? result[@"mimeType"]
                                 : @"application/octet-stream";
        response.contentType = mimeType;

        NSString *filePath = [result[@"filePath"] isKindOfClass:[NSString class]] ? result[@"filePath"] : nil;
        NSData *blobData = [result[@"blob"] isKindOfClass:[NSData class]] ? result[@"blob"] : nil;
        NSNumber *sizeNum = [result[@"size"] isKindOfClass:[NSNumber class]] ? result[@"size"] : nil;
        unsigned long long totalLength = sizeNum ? [sizeNum unsignedLongLongValue] : 0;

        // Use shared blob response handler with Range support (Phase 1.2)
        NSError *responseError = nil;
        if (![blobService.blobStorage respondWithBlobData:blobData
                                                filePath:filePath
                                             totalLength:totalLength
                                              forRequest:request
                                                response:response
                                                   error:&responseError]) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"BlobReadFailed", @"message": @"Failed to send blob"}];
            }
        }
    }];

    // com.atproto.repo.importRepo
    [dispatcher registerComAtprotoRepoImportRepo:^(HttpRequest *request, HttpResponse *response) {
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

        NSMutableArray<PDSDatabaseBlock *> *blocks = [NSMutableArray arrayWithCapacity:reader.blocks.count];
        for (CARBlock *block in reader.blocks) {
            if (!block.cid || block.data.length == 0) {
                continue;
            }
            PDSDatabaseBlock *dbBlock = [[PDSDatabaseBlock alloc] init];
            dbBlock.cid = block.cid.bytes;
            dbBlock.blockData = block.data;
            dbBlock.size = (NSInteger)block.data.length;
            dbBlock.rev = commit.rev ?: @"";
            [blocks addObject:dbBlock];
        }

        NSArray<PDSDatabaseRecord *> *records = importRepoExtractRecords(commit.dataCID.bytes, did, reader, commit.rev ?: @"");

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

        PDSDatabasePool *databasePool = recordService.databasePool;
        if (!databasePool) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": @"Record database pool is unavailable"}];
            return;
        }

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
        NSDictionary *didDocJson = nil;

        if (doc) {
            didDocJson = doc.jsonDictionary ?: @{};
        } else {
            // Fallback: construct a minimal DID document for local accounts
            // when PLC resolution is unavailable (e.g. PDS_PLC_URL=skip)
            NSString *accountHandle = localAccount.handle.length > 0 ? [localAccount.handle lowercaseString] : @"handle.invalid";
            didDocJson = @{
                @"id": did,
                @"alsoKnownAs": accountHandle.length > 0 ? @[[NSString stringWithFormat:@"at://%@", accountHandle]] : @[]
            };
        }

        NSString *handleFromDidDoc = normalizedAtHandleFromAlsoKnownAs(doc.alsoKnownAs);
        NSString *accountHandle = localAccount.handle.length > 0 ? [localAccount.handle lowercaseString] : @"handle.invalid";
        BOOL handleIsCorrect = (handleFromDidDoc.length > 0 && [handleFromDidDoc isEqualToString:accountHandle]) || (doc == nil && localAccount.handle.length > 0);

        NSMutableArray *collections = [NSMutableArray array];
        NSMutableArray *collectionStats = [NSMutableArray array];
        if ([stats[@"collections"] isKindOfClass:[NSArray class]]) {
            for (NSDictionary *col in stats[@"collections"]) {
                if ([col isKindOfClass:[NSDictionary class]] && [col[@"collection"] isKindOfClass:[NSString class]]) {
                    [collections addObject:col[@"collection"]];
                    [collectionStats addObject:@{
                        @"name": col[@"collection"],
                        @"count": col[@"count"] ?: @(0)
                    }];
                }
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"handle": accountHandle,
            @"did": did,
            @"didDoc": didDocJson,
            @"collections": collections,
            @"collectionStats": collectionStats,
            @"handleIsCorrect": @(handleIsCorrect)
        }];
    }];

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

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *collection = body[@"collection"];
        NSString *rkey = body[@"rkey"];
        NSDictionary *record = body[@"record"];
        NSString *repo = body[@"repo"];
        NSString *swapCommit = body[@"swapCommit"];
        NSString *swapRecord = body[@"swapRecord"];
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

    // com.atproto.repo.putRecord
    [dispatcher registerComAtprotoRepoPutRecord:upsertRecordHandler];

    // com.atproto.repo.updateRecord
    [dispatcher registerComAtprotoRepoUpdateRecord:upsertRecordHandler];

    // com.atproto.repo.applyWrites
    [dispatcher registerComAtprotoRepoApplyWrites:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        GZ_LOG_INFO(@"applyWrites: method called, body=%@", body);
        if (!body) {
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

        NSArray *writes = body[@"writes"];
        NSString *repo = body[@"repo"];
        PDSValidationMode mode = validationModeFromValidateParameter(body[@"validate"]);
        NSString *swapCommit = body[@"swapCommit"];

        GZ_LOG_INFO(@"applyWrites: body=%@, writes=%@", body, writes);

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
            if (isReplyNotAllowedError(error)) {
                [response setJsonBody:@{@"error": @"ReplyNotAllowed", @"message": @"Reply not allowed by threadgate"}];
            } else {
                [response setJsonBody:@{@"error": @"WriteFailed", @"message": error.localizedDescription ?: @"Failed to apply writes"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // com.atproto.repo.deleteBlob
    [dispatcher registerComAtprotoRepoDeleteBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *cid = body[@"blob"];
        if (cid.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing blob CID"}];
            return;
        }

        NSError *error = nil;
        if (![blobService deleteBlobWithCID:cid did:did error:&error]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{
                @"error": @"DeleteFailed",
                @"message": error.localizedDescription ?: @"Failed to delete blob"
            }];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];
    }];
}

@end
