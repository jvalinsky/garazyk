// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoCARASLWellKnown.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@implementation ATProtoCARASLWellKnown

- (instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore {
    NSParameterAssert(objectStore);
    self = [super init];
    if (self) {
        _objectStore = objectStore;
    }
    return self;
}

+ (ATProtoCID *)cidFromRASLParameter:(NSString *)cidParam {
    if (cidParam.length == 0) {
        return nil;
    }
    NSString *decoded = [cidParam stringByRemovingPercentEncoding] ?: cidParam;
    ATProtoCID *cid = [ATProtoCID daslCIDFromString:decoded profile:ATProtoDASLCIDProfileBig];
    if (!cid) {
        cid = [ATProtoCID daslCIDFromString:decoded profile:ATProtoDASLCIDProfileBase];
    }
    return cid;
}

- (void)registerRoutesOnServer:(id)server {
    if (![server isKindOfClass:[ATProtoHttpServer class]]) {
        return;
    }
    ATProtoHttpServer *http = (ATProtoHttpServer *)server;
    __weak typeof(self) weakSelf = self;
    [http addRoute:@"GET" path:@"/.well-known/rasl/:cid"
           handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
               [weakSelf handleRequest:request response:response includeBody:YES];
           }];
    [http addRoute:@"HEAD" path:@"/.well-known/rasl/:cid"
           handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
               [weakSelf handleRequest:request response:response includeBody:NO];
           }];
}

- (BOOL)handleRequest:(ATProtoHttpRequest *)request
             response:(ATProtoHttpResponse *)response
          includeBody:(BOOL)includeBody {
    response.contentType = @"application/octet-stream";

    NSString *cidParam = request.pathParameters[@"cid"];
    if (cidParam.length == 0) {
        // Fallback: parse path suffix.
        NSString *path = request.path ?: @"";
        NSString *prefix = @"/.well-known/rasl/";
        if ([path hasPrefix:prefix]) {
            cidParam = [path substringFromIndex:prefix.length];
        }
    }
    ATProtoCID *cid = [ATProtoCARASLWellKnown cidFromRASLParameter:cidParam];
    if (!cid) {
        response.statusCode = 400;
        return NO;
    }

    NSError *storeError = nil;
    NSData *data = [self.objectStore dataForCID:cid error:&storeError];
    if (!data) {
        response.statusCode = 404;
        return NO;
    }

    const uint8_t *mh = (const uint8_t *)cid.multihash.bytes;
    ATProtoCAObjectDigestProfile profile = ATProtoCAObjectDigestProfileSHA256;
    if (cid.multihash.length >= 2 && mh[0] == ATProtoDASLMultihashBLAKE3) {
        profile = ATProtoCAObjectDigestProfileBLAKE3;
    } else if (cid.multihash.length < 2 || mh[0] != ATProtoDASLMultihashSHA256) {
        response.statusCode = 400;
        return NO;
    }

    ATProtoCID *computed = [ATProtoCAObjectStore cidForData:data profile:profile error:nil];
    if (![computed isEqual:cid]) {
        response.statusCode = 500;
        return NO;
    }

    response.statusCode = 200;
    if (includeBody) {
        [response setBodyData:data];
    }
    return YES;
}

@end
