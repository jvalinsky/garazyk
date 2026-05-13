// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSystemDiagnosticsHandler.h"

@implementation PDSSystemDiagnosticsHandler

+ (instancetype)sharedHandler {
    static PDSSystemDiagnosticsHandler *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSSystemDiagnosticsHandler alloc] init];
    });
    return shared;
}

- (nullable NSString *)handleRequestWithMethod:(NSInteger)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {

    // Route to sequencer handler
    if ([path hasPrefix:@"/sequencer/"]) {
        NSString *sequencerPath = [path stringByReplacingOccurrencesOfString:@"/sequencer"
                                                                  withString:@""];
        return [[PDSSequencerHealthHandler sharedHandler] handleRequestWithMethod:method
                                                                            path:sequencerPath
                                                                       headers:headers
                                                                          body:body
                                                                    statusCode:statusCode
                                                                   contentType:contentType];
    }

    // Route to blob audit handler
    if ([path hasPrefix:@"/blobs/"]) {
        NSString *blobPath = [path stringByReplacingOccurrencesOfString:@"/blobs"
                                                             withString:@""];
        PDSBlobAuditHandler *blobHandler = [PDSBlobAuditHandler sharedHandler];
        if (self.auditManager) {
            blobHandler.auditManager = self.auditManager;
        }
        return [blobHandler handleRequestWithMethod:method
                                               path:blobPath
                                            headers:headers
                                               body:body
                                         statusCode:statusCode
                                        contentType:contentType];
    }

    // Route to rate limit handler
    if ([path hasPrefix:@"/ratelimits/"]) {
        NSString *rateLimitPath = [path stringByReplacingOccurrencesOfString:@"/ratelimits"
                                                                  withString:@""];
        return [[PDSRateLimitAdminHandler sharedHandler] handleRequestWithMethod:method
                                                                          path:rateLimitPath
                                                                     headers:headers
                                                                        body:body
                                                                  statusCode:statusCode
                                                                 contentType:contentType];
    }

    if (statusCode) *statusCode = 404;
    if (contentType) *contentType = @"application/json";
    return @"{\"error\": \"Not Found\"}";
}

@end
