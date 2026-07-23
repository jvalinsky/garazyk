// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcRepoPack+Blobs.h"
#import "Network/XrpcRepoPack_Internal.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/RateLimiter.h"
#import "Services/PDS/PDSBlobService.h"
#import "Services/PDS/PDSSpaceStore.h"
#import "Database/Service/ServiceDatabases.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Core/ATProtoValidator.h"
#import "Security/Space/PDSSpaceScope.h"
#import "Security/Space/PDSSpaceURI.h"
#import "Auth/JWT.h"
#import "Network/Generated/GZXrpcNSID.h"

static const NSUInteger kPDSUploadBlobDefaultMaxBytes = 1024 * 1024;
static const NSUInteger kPDSUploadBlobVideoMaxBytes = 50 * 1024 * 1024;

static NSUInteger maxUploadBlobBytesForContentType(NSString *contentType) {
    NSString *mimeType = normalizedMimeType(contentType);
    if ([mimeType isEqualToString:@"video/mp4"]) {
        return kPDSUploadBlobVideoMaxBytes;
    }
    return kPDSUploadBlobDefaultMaxBytes;
}

static BOOL repoBlobMimeTypeShouldAttach(NSString *mimeType) {
    NSString *lower = normalizedMimeType(mimeType);
    if ([lower isEqualToString:@"application/octet-stream"]) return YES;
    if ([lower hasPrefix:@"application/pdf"]) return NO;
    if ([lower hasPrefix:@"application/msword"] ||
        [lower hasPrefix:@"application/vnd."] ||
        [lower hasPrefix:@"application/rtf"] ||
        [lower hasPrefix:@"application/zip"]) {
        return YES;
    }
    return NO;
}

void applyRepoBlobDownloadHeaders(NSString *mimeType, HttpResponse *response) {
    [response setHeader:@"nosniff" forKey:@"X-Content-Type-Options"];
    if (repoBlobMimeTypeShouldAttach(mimeType)) {
        [response setHeader:@"attachment" forKey:@"Content-Disposition"];
    }
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

/* A space blob is uploaded through the standard binary endpoint with explicit
 * experimental binding headers.  The space lexicon has no upload procedure,
 * so require the target collection and action here and prove the caller holds
 * the same OAuth capability that will be required to reference the blob. */
static BOOL authorizeSpaceBlobUpload(HttpRequest *request, HttpResponse *response,
                                     NSString *did, PDSSpaceURI *space,
                                     NSString *collection, NSString *action) {
    NSString *authorization = [request headerForKey:@"Authorization"];
    NSString *token = [authorization hasPrefix:@"Bearer "] ? [authorization substringFromIndex:7] :
                       [authorization hasPrefix:@"DPoP "] ? [authorization substringFromIndex:5] : nil;
    JWT *jwt = [JWT jwtWithToken:token error:nil];
    BOOL sawSpaceScope = NO;
    for (NSString *candidate in [jwt.payload.scope componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
        if (![candidate hasPrefix:@"space:"]) continue;
        sawSpaceScope = YES;
        PDSSpaceScope *scope = [[PDSSpaceScope scopeWithString:candidate error:nil]
            scopeByResolvingSelfAuthorityForDID:did];
        if ([scope matchesSpace:space action:action collection:collection]) return YES;
    }
    response.statusCode = HttpStatusForbidden;
    [response setJsonBody:@{ @"error" : @"InsufficientScope",
                             @"message" : sawSpaceScope
                                 ? @"OAuth scope does not permit this space blob upload"
                                 : @"A matching OAuth space: scope is required" }];
    return NO;
}

@implementation XrpcRepoPack (Blobs)

+ (void)registerBlobRoutesWithDispatcher:(XrpcDispatcher *)dispatcher
                                services:(id<XrpcRoutePackServices>)services {
    id<PDSAdminController> adminController = services.adminController;
    PDSBlobService *blobService = services.blobService;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    RateLimiter *rateLimiter = services.rateLimiter;

#pragma mark - com.atproto.repo.uploadBlob
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_uploadBlob handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        if (rejectUnavailableRepoDid(did, serviceDatabases, adminController, response)) {
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

        if ((contentType && [normalizedMimeType(contentType) isEqualToString:@"application/x-msdownload"]) ||
            isActiveUploadMimeType(contentType)) {
            response.statusCode = HttpStatusUnsupportedMediaType;
            [response setJsonBody:@{@"error": @"UnsupportedMediaType", @"message": @"Forbidden MIME type"}];
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

        NSString *spaceHeader = [request headerForKey:@"X-Atproto-Space"];
        NSString *collectionHeader = [request headerForKey:@"X-Atproto-Space-Collection"];
        NSString *actionHeader = [request headerForKey:@"X-Atproto-Space-Action"];
        if (spaceHeader.length > 0 || collectionHeader.length > 0 || actionHeader.length > 0) {
            PDSSpaceURI *space = [PDSSpaceURI URIWithString:spaceHeader error:nil];
            if (!space || space.recordURI ||
                ![ATProtoValidator validateNSID:collectionHeader error:nil] ||
                !([actionHeader isEqualToString:PDSSpaceActionCreate] ||
                  [actionHeader isEqualToString:PDSSpaceActionUpdate])) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{ @"error" : @"InvalidRequest",
                                         @"message" : @"Space uploads require valid X-Atproto-Space, X-Atproto-Space-Collection, and X-Atproto-Space-Action headers" }];
                return;
            }
            PDSSpaceStore *spaceStore = services.spaceStore;
            if (!spaceStore) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{ @"error" : @"SpaceFeatureDisabled",
                                         @"message" : @"Permissioned spaces are disabled on this PDS" }];
                return;
            }
            if (!authorizeSpaceBlobUpload(request, response, did, space, collectionHeader, actionHeader)) {
                return;
            }
            NSError *spaceBlobError = nil;
            NSDictionary *spaceBlob = [spaceStore storeBlobData:blobData
                                                        mimeType:normalizedMimeType(contentType) ?: @"application/octet-stream"
                                                         toSpace:space.spaceURI
                                                          author:did
                                                           error:&spaceBlobError];
            if (!spaceBlob) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{ @"error" : @"BlobUploadFailed",
                                         @"message" : spaceBlobError.localizedDescription ?: @"Unable to store private space blob" }];
                return;
            }
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{ @"blob" : @{
                @"$type" : @"blob",
                @"ref" : @{ @"$link" : spaceBlob[@"cid"] },
                @"mimeType" : spaceBlob[@"mimeType"],
                @"size" : spaceBlob[@"size"],
            } }];
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

#pragma mark - com.atproto.repo.listMissingBlobs
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_listMissingBlobs handler:^(HttpRequest *request, HttpResponse *response) {
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

#pragma mark - com.atproto.repo.getBlob
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_getBlob handler:^(HttpRequest *request, HttpResponse *response) {
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

        if (rejectUnavailableRepoDid(blobDid, serviceDatabases, adminController, response)) {
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
        applyRepoBlobDownloadHeaders(mimeType, response);

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

#pragma mark - com.atproto.repo.deleteBlob
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_repo_deleteBlob handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (rejectUnavailableRepoDid(did, serviceDatabases, adminController, response)) {
            return;
        }
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
