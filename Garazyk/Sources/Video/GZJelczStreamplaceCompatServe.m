// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczStreamplaceCompatServe.h"
#import "Video/GZJelczStreamplaceOriginHints.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NSErrorDomain const GZJelczStreamplaceCompatServeErrorDomain =
    @"GZJelczStreamplaceCompatServeErrorDomain";

static NSError *CompatServeError(GZJelczStreamplaceCompatServeErrorCode code, NSString *message) {
    return [NSError errorWithDomain:GZJelczStreamplaceCompatServeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

static NSString *GZStripM4SSuffix(NSString *cidParam) {
    if ([cidParam.lowercaseString hasSuffix:@".m4s"]) {
        return [cidParam substringToIndex:cidParam.length - 4];
    }
    return cidParam;
}

static BOOL GZParseByteRange(NSString *rangeHeader,
                             unsigned long long totalLength,
                             BOOL *hasRange,
                             BOOL *satisfiable,
                             unsigned long long *startOut,
                             unsigned long long *endOut,
                             NSString **failureReason) {
    if (hasRange) *hasRange = NO;
    if (satisfiable) *satisfiable = YES;
    if (startOut) *startOut = 0;
    if (endOut) *endOut = totalLength > 0 ? totalLength - 1 : 0;
    if (failureReason) *failureReason = nil;
    if (rangeHeader.length == 0) {
        return YES;
    }
    if (hasRange) *hasRange = YES;
    NSString *trimmed = [rangeHeader stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![trimmed.lowercaseString hasPrefix:@"bytes="]) {
        if (failureReason) *failureReason = @"Range header must use bytes units";
        return NO;
    }
    NSString *spec = [trimmed substringFromIndex:6];
    NSRange dash = [spec rangeOfString:@"-"];
    if (dash.location == NSNotFound) {
        if (failureReason) *failureReason = @"Range header is malformed";
        return NO;
    }
    NSString *startStr = [spec substringToIndex:dash.location];
    NSString *endStr = [spec substringFromIndex:dash.location + 1];
    unsigned long long start = 0;
    unsigned long long end = totalLength > 0 ? totalLength - 1 : 0;
    if (startStr.length == 0) {
        // suffix bytes
        unsigned long long suffix = (unsigned long long)endStr.longLongValue;
        if (suffix == 0 || totalLength == 0) {
            if (satisfiable) *satisfiable = NO;
            return YES;
        }
        if (suffix >= totalLength) {
            start = 0;
        } else {
            start = totalLength - suffix;
        }
        end = totalLength - 1;
    } else {
        start = (unsigned long long)startStr.longLongValue;
        if (endStr.length > 0) {
            end = (unsigned long long)endStr.longLongValue;
        }
        if (start >= totalLength || end < start) {
            if (satisfiable) *satisfiable = NO;
            return YES;
        }
        if (end >= totalLength) {
            end = totalLength - 1;
        }
    }
    if (startOut) *startOut = start;
    if (endOut) *endOut = end;
    return YES;
}

@implementation GZJelczStreamplaceCompatServe

- (instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore {
    NSParameterAssert(objectStore);
    self = [super init];
    if (self) {
        _objectStore = objectStore;
    }
    return self;
}

- (ATProtoCID *)cidFromParameter:(NSString *)cidParam {
    NSString *cleaned = GZStripM4SSuffix(cidParam ?: @"");
    if (cleaned.length == 0) {
        return nil;
    }
    ATProtoCID *cid = [ATProtoCID daslCIDFromString:cleaned profile:ATProtoDASLCIDProfileBig];
    if (!cid) {
        cid = [ATProtoCID daslCIDFromString:cleaned profile:ATProtoDASLCIDProfileBase];
    }
    return cid;
}

- (NSDictionary *)originAttestationForCIDString:(NSString *)cidString error:(NSError **)error {
    ATProtoCID *cid = [self cidFromParameter:cidString];
    if (!cid) {
        if (error) *error = CompatServeError(GZJelczStreamplaceCompatServeErrorInvalidArgument, @"Invalid CID");
        return nil;
    }
    NSDictionary *stat = [self.objectStore statCID:cid error:error];
    if (!stat) {
        if (error && !*error) {
            *error = CompatServeError(GZJelczStreamplaceCompatServeErrorNotFound, @"BlobNotFound");
        }
        return nil;
    }
    NSUInteger size = [stat[@"size"] unsignedIntegerValue];
    return [GZJelczStreamplaceOriginHints originRecordForBlobCID:cid.stringValue
                                                            size:size
                                                        mimeType:@"video/mp4"];
}

- (BOOL)handleRequest:(ATProtoHttpRequest *)request
             response:(ATProtoHttpResponse *)response
                error:(NSError **)error {
    NSString *did = [request queryParamForKey:@"did"];
    NSString *cidParam = [request queryParamForKey:@"cid"];
    (void)did; // lexicon accounting; not ACL
    if (cidParam.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"cid required"}];
        if (error) *error = CompatServeError(GZJelczStreamplaceCompatServeErrorInvalidArgument, @"cid required");
        return NO;
    }
    if (did.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"did required"}];
        if (error) *error = CompatServeError(GZJelczStreamplaceCompatServeErrorInvalidArgument, @"did required");
        return NO;
    }

    ATProtoCID *cid = [self cidFromParameter:cidParam];
    if (!cid) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Invalid cid"}];
        if (error) *error = CompatServeError(GZJelczStreamplaceCompatServeErrorInvalidArgument, @"Invalid cid");
        return NO;
    }

    NSError *storeError = nil;
    NSData *full = [self.objectStore dataForCID:cid error:&storeError];
    if (!full) {
        response.statusCode = 404;
        [response setJsonBody:@{
            @"error": @"BlobNotFound",
            @"message": @"This node doesn't have the requested CID"
        }];
        if (error) *error = CompatServeError(GZJelczStreamplaceCompatServeErrorNotFound, @"BlobNotFound");
        return NO;
    }

    // Verify digest before egress.
    const uint8_t *mh = (const uint8_t *)cid.multihash.bytes;
    ATProtoCAObjectDigestProfile profile = ATProtoCAObjectDigestProfileSHA256;
    if (cid.multihash.length >= 2 && mh[0] == ATProtoDASLMultihashBLAKE3) {
        profile = ATProtoCAObjectDigestProfileBLAKE3;
    }
    ATProtoCID *computed = [ATProtoCAObjectStore cidForData:full profile:profile error:nil];
    if (![computed isEqual:cid]) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"InternalError", @"message": @"CID verification failed"}];
        if (error) *error = CompatServeError(GZJelczStreamplaceCompatServeErrorInvalidArgument, @"CID verify failed");
        return NO;
    }

    unsigned long long total = full.length;
    BOOL hasRange = NO;
    BOOL satisfiable = YES;
    unsigned long long start = 0;
    unsigned long long end = total > 0 ? total - 1 : 0;
    NSString *rangeFailure = nil;
    NSString *rangeHeader = [request headerForKey:@"Range"];
    if (!GZParseByteRange(rangeHeader, total, &hasRange, &satisfiable, &start, &end, &rangeFailure)) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRange", @"message": rangeFailure ?: @"Invalid Range"}];
        if (error) *error = CompatServeError(GZJelczStreamplaceCompatServeErrorRange, rangeFailure ?: @"Invalid Range");
        return NO;
    }
    if (hasRange && !satisfiable) {
        response.statusCode = 416;
        response.statusMessage = @"Range Not Satisfiable";
        [response setHeader:[NSString stringWithFormat:@"bytes */%llu", total] forKey:@"Content-Range"];
        if (error) *error = CompatServeError(GZJelczStreamplaceCompatServeErrorRange, @"Range not satisfiable");
        return NO;
    }

    response.contentType = @"video/mp4";
    [response setHeader:@"bytes" forKey:@"Accept-Ranges"];
    NSData *body = full;
    if (hasRange) {
        NSUInteger loc = (NSUInteger)start;
        NSUInteger len = (NSUInteger)(end - start + 1);
        body = [full subdataWithRange:NSMakeRange(loc, len)];
        response.statusCode = 206;
        [response setHeader:[NSString stringWithFormat:@"bytes %llu-%llu/%llu", start, end, total]
                     forKey:@"Content-Range"];
    } else {
        response.statusCode = 200;
    }
    [response setBodyData:body];
    return YES;
}

@end
