// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoCAWatchService.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "MediaCore/ATProtoCAMediaDenylist.h"
#import "MediaCore/ATProtoCAMirrorResolver.h"
#import "Core/ATProtoMASLDocument.h"
#import "Core/CID.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NSErrorDomain const ATProtoCAWatchServiceErrorDomain = @"com.atproto.ca.watch";

static NSError *CAWatchError(ATProtoCAWatchServiceErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoCAWatchServiceErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void CAWatchSetError(NSError **error, ATProtoCAWatchServiceErrorCode code, NSString *message) {
    if (error) {
        *error = CAWatchError(code, message);
    }
}

/** Mirrors BlobStorage range parsing without importing Services. */
static BOOL CAWatchParseByteRange(NSString *rangeHeader,
                                  unsigned long long totalLength,
                                  BOOL *hasRange,
                                  BOOL *satisfiable,
                                  unsigned long long *outStart,
                                  unsigned long long *outEnd,
                                  NSString **failureReason) {
    if (hasRange) *hasRange = NO;
    if (satisfiable) *satisfiable = YES;
    if (outStart) *outStart = 0;
    if (outEnd) *outEnd = totalLength > 0 ? (totalLength - 1) : 0;

    NSString *trimmed = [rangeHeader stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return YES;
    }
    if (hasRange) *hasRange = YES;
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
    NSString *startPart = [spec substringToIndex:dash.location];
    NSString *endPart = [spec substringFromIndex:dash.location + 1];

    unsigned long long start = 0;
    unsigned long long end = totalLength > 0 ? (totalLength - 1) : 0;

    if (startPart.length == 0) {
        // suffix: bytes=-N
        if (endPart.length == 0) {
            if (failureReason) *failureReason = @"Range header is malformed";
            return NO;
        }
        unsigned long long suffix = strtoull(endPart.UTF8String, NULL, 10);
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
        start = strtoull(startPart.UTF8String, NULL, 10);
        if (endPart.length > 0) {
            end = strtoull(endPart.UTF8String, NULL, 10);
        } else {
            end = totalLength > 0 ? (totalLength - 1) : 0;
        }
        if (totalLength == 0 || start >= totalLength || start > end) {
            if (satisfiable) *satisfiable = NO;
            return YES;
        }
        if (end >= totalLength) {
            end = totalLength - 1;
        }
    }

    if (outStart) *outStart = start;
    if (outEnd) *outEnd = end;
    return YES;
}

@interface ATProtoCAWatchService ()
@property (nonatomic, strong, readwrite) ATProtoCAObjectStore *objectStore;
@property (nonatomic, strong, readwrite, nullable) id<ATProtoCAMediaDenylist> denylist;
@end

@implementation ATProtoCAWatchService

- (instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore
                           denylist:(nullable id<ATProtoCAMediaDenylist>)denylist {
    self = [super init];
    if (self) {
        _objectStore = objectStore;
        _denylist = denylist;
    }
    return self;
}

+ (nullable NSString *)bundlePathFromWatchRemainder:(nullable NSString *)remainder {
    NSString *raw = remainder ?: @"";
    if (raw.length == 0 || [raw isEqualToString:@"playlist.m3u8"]) {
        return @"/";
    }

    NSString *decoded = [raw stringByRemovingPercentEncoding];
    if (!decoded) {
        return nil;
    }
    // Reject traversal and null bytes after decoding. Never join onto a filesystem.
    if ([decoded containsString:@".."] || [decoded containsString:@"\0"]) {
        return nil;
    }
    while ([decoded hasPrefix:@"/"]) {
        decoded = [decoded substringFromIndex:1];
    }
    if (decoded.length == 0) {
        return @"/";
    }
    return [@"/" stringByAppendingString:decoded];
}

+ (BOOL)parseWatchPath:(NSString *)path
                 outDID:(NSString **)outDID
      outManifestCIDStr:(NSString **)outManifestCIDStr
          outBundlePath:(NSString **)outBundlePath {
    if (![path isKindOfClass:[NSString class]] || ![path hasPrefix:@"/watch/"]) {
        return NO;
    }
    NSString *suffix = [path substringFromIndex:7];
    NSArray<NSString *> *parts = [suffix componentsSeparatedByString:@"/"];
    if (parts.count < 2) {
        return NO;
    }
    NSString *did = parts[0];
    NSString *manifestCID = parts[1];
    if (did.length == 0 || manifestCID.length == 0) {
        return NO;
    }
    NSString *remainder = @"";
    if (parts.count > 2) {
        remainder = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@"/"];
    }
    NSString *bundlePath = [self bundlePathFromWatchRemainder:remainder];
    if (!bundlePath) {
        return NO;
    }
    if (outDID) *outDID = did;
    if (outManifestCIDStr) *outManifestCIDStr = manifestCID;
    if (outBundlePath) *outBundlePath = bundlePath;
    return YES;
}

- (void)registerRoutesOnServer:(id)server {
    if (![server isKindOfClass:[ATProtoHttpServer class]]) {
        return;
    }
    ATProtoHttpServer *http = (ATProtoHttpServer *)server;
    __weak typeof(self) weakSelf = self;
    void (^handler)(ATProtoHttpRequest *, ATProtoHttpResponse *) = ^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        [weakSelf handleRequest:request response:response];
    };
    [http addRoute:@"OPTIONS" path:@"/watch/*" handler:handler];
    [http addRoute:@"GET" path:@"/watch/*" handler:handler];
    [http addRoute:@"HEAD" path:@"/watch/*" handler:handler];
}

- (void)handleRequest:(ATProtoHttpRequest *)request
             response:(ATProtoHttpResponse *)response {
    NSString *origin = [request headerForKey:@"Origin"];
    if (origin.length > 0) {
        [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"true" forKey:@"Access-Control-Allow-Credentials"];
        [response setHeader:@"Origin" forKey:@"Vary"];
    } else {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    }
    [response setHeader:@"GET, HEAD, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:@"Authorization, Content-Type, Accept, Range, *" forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:@"Content-Length, Content-Range, Accept-Ranges" forKey:@"Access-Control-Expose-Headers"];

    if (request.method == HttpMethodOPTIONS) {
        response.statusCode = 204;
        [response setBodyData:[NSData data]];
        return;
    }

    NSString *did = nil;
    NSString *manifestCIDStr = nil;
    NSString *bundlePath = nil;
    if (![ATProtoCAWatchService parseWatchPath:request.path ?: @""
                                         outDID:&did
                              outManifestCIDStr:&manifestCIDStr
                                  outBundlePath:&bundlePath]) {
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"NotFound", @"message": @"Invalid watch path"}];
        return;
    }

    ATProtoCID *manifestCID = [ATProtoCID cidFromString:manifestCIDStr];
    if (!manifestCID) {
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"NotFound", @"message": @"Invalid manifest CID"}];
        return;
    }

    // Optional record-scope denylist using at://{did}/… is not required for Phase 5;
    // CID denylist covers manifest and resource objects.
    (void)did;

    NSError *serveError = nil;
    BOOL ok = [self serveManifestCID:manifestCID
                          bundlePath:bundlePath
                         rangeHeader:[request headerForKey:@"Range"]
                            response:response
                               error:&serveError];
    if (ok) {
        return;
    }
    if (serveError.code == ATProtoCAWatchServiceErrorDenied) {
        response.statusCode = 403;
        [response setJsonBody:@{
            @"error": @"ContentDenied",
            @"message": serveError.localizedDescription ?: @"Content denied by policy"
        }];
        return;
    }
    if (serveError.code == ATProtoCAWatchServiceErrorRange) {
        // serveManifestCID already configured 416/400 on the response.
        return;
    }
    response.statusCode = 404;
    [response setJsonBody:@{
        @"error": @"NotFound",
        @"message": serveError.localizedDescription ?: @"Resource not found"
    }];
}

- (BOOL)serveManifestCID:(ATProtoCID *)manifestCID
              bundlePath:(NSString *)bundlePath
             rangeHeader:(nullable NSString *)rangeHeader
                response:(ATProtoHttpResponse *)response
                   error:(NSError **)error {
    if (![manifestCID isKindOfClass:[ATProtoCID class]] || bundlePath.length == 0 || !response) {
        CAWatchSetError(error, ATProtoCAWatchServiceErrorInvalidArgument, @"Invalid serve arguments");
        return NO;
    }

    if ([self.denylist isDeniedCID:manifestCID]) {
        CAWatchSetError(error, ATProtoCAWatchServiceErrorDenied, @"Manifest CID is denied");
        return NO;
    }

    NSError *storeError = nil;
    NSData *manifestData = nil;
    if (self.mirrorResolver) {
        manifestData = [self.mirrorResolver dataForCID:manifestCID
                                             providers:self.mirrorProviders
                                                 error:&storeError];
    } else {
        manifestData = [self.objectStore dataForCID:manifestCID error:&storeError];
    }
    if (!manifestData) {
        CAWatchSetError(error, ATProtoCAWatchServiceErrorNotFound, @"Manifest object not found");
        return NO;
    }

    ATProtoMASLDocument *document = [ATProtoMASLDocument documentWithDRISLData:manifestData error:&storeError];
    if (!document || !document.isBundle) {
        CAWatchSetError(error, ATProtoCAWatchServiceErrorNotFound, @"Manifest is not a MASL bundle");
        return NO;
    }

    ATProtoCID *resourceCID = [document resourceCIDForPath:bundlePath error:&storeError];
    if (!resourceCID) {
        CAWatchSetError(error, ATProtoCAWatchServiceErrorNotFound,
                        [NSString stringWithFormat:@"No resource at %@", bundlePath]);
        return NO;
    }

    if ([self.denylist isDeniedCID:resourceCID]) {
        CAWatchSetError(error, ATProtoCAWatchServiceErrorDenied, @"Resource CID is denied");
        return NO;
    }

    NSDictionary *stat = [self.objectStore statCID:resourceCID error:&storeError];
    if (!stat && self.mirrorResolver) {
        // Ensure object is local (or fetched) before range reads.
        NSData *full = [self.mirrorResolver dataForCID:resourceCID
                                             providers:self.mirrorProviders
                                                 error:&storeError];
        if (full) {
            stat = [self.objectStore statCID:resourceCID error:&storeError];
        }
    }
    if (!stat) {
        CAWatchSetError(error, ATProtoCAWatchServiceErrorNotFound, @"Resource object not found");
        return NO;
    }
    unsigned long long totalLength = [stat[@"size"] unsignedLongLongValue];

    NSDictionary<NSString *, NSString *> *maslHeaders =
        [document httpHeadersForPath:bundlePath error:nil] ?: @{};
    NSString *contentType = maslHeaders[@"content-type"] ?: @"application/octet-stream";
    response.contentType = contentType;
    for (NSString *key in maslHeaders) {
        if ([key isEqualToString:@"content-type"]) {
            continue;
        }
        [response setHeader:maslHeaders[key] forKey:key];
    }
    [response setHeader:@"bytes" forKey:@"Accept-Ranges"];
    [response setHeader:@"public, max-age=3600" forKey:@"Cache-Control"];

    BOOL hasRange = NO;
    BOOL satisfiable = YES;
    unsigned long long start = 0;
    unsigned long long end = totalLength > 0 ? (totalLength - 1) : 0;
    NSString *rangeFailure = nil;
    if (!CAWatchParseByteRange(rangeHeader, totalLength, &hasRange, &satisfiable, &start, &end, &rangeFailure)) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRange", @"message": rangeFailure ?: @"Invalid Range"}];
        CAWatchSetError(error, ATProtoCAWatchServiceErrorRange, rangeFailure ?: @"Invalid Range");
        return NO;
    }
    if (hasRange && !satisfiable) {
        response.statusCode = 416;
        response.statusMessage = @"Range Not Satisfiable";
        [response setHeader:[NSString stringWithFormat:@"bytes */%llu", totalLength] forKey:@"Content-Range"];
        [response setBodyData:[NSData data]];
        CAWatchSetError(error, ATProtoCAWatchServiceErrorRange, @"Range not satisfiable");
        return NO;
    }

    NSUInteger offset = (NSUInteger)start;
    NSUInteger length = (NSUInteger)(end >= start ? (end - start + 1) : 0);
    NSData *bytes = nil;
    if (self.mirrorResolver) {
        bytes = [self.mirrorResolver dataForCID:resourceCID
                                         offset:offset
                                         length:length
                                      providers:self.mirrorProviders
                                          error:&storeError];
    } else {
        bytes = [self.objectStore dataForCID:resourceCID offset:offset length:length error:&storeError];
    }
    if (!bytes) {
        CAWatchSetError(error, ATProtoCAWatchServiceErrorNotFound, @"Failed to read resource bytes");
        return NO;
    }

    if (hasRange) {
        response.statusCode = 206;
        response.statusMessage = @"Partial Content";
        [response setHeader:[NSString stringWithFormat:@"bytes %llu-%llu/%llu", start, end, totalLength]
                     forKey:@"Content-Range"];
    } else {
        response.statusCode = 200;
    }
    [response setBodyData:bytes];
    if (error) *error = nil;
    return YES;
}

@end
