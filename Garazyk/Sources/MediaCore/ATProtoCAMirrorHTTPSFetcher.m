// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoCAMirrorHTTPSFetcher.h"
#import "Core/ATProtoRASLURL.h"
#import "Core/CID.h"

NSErrorDomain const ATProtoCAMirrorHTTPSFetcherErrorDomain =
    @"ATProtoCAMirrorHTTPSFetcherErrorDomain";

@implementation ATProtoCAMirrorHTTPSFetcher

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient {
    NSParameterAssert(httpClient);
    self = [super init];
    if (self) {
        _httpClient = httpClient;
        _timeout = 30.0;
        _maxResponseBytes = 64ULL * 1024ULL * 1024ULL;
    }
    return self;
}

+ (NSURL *)raslURLForCID:(ATProtoCID *)cid providerBaseURL:(NSString *)providerBaseURL {
    if (!cid || providerBaseURL.length == 0) {
        return nil;
    }
    NSURL *base = [NSURL URLWithString:providerBaseURL];
    if (!base || !base.host) {
        // Allow bare host strings.
        NSString *host = [providerBaseURL stringByTrimmingCharactersInSet:
                          [NSCharacterSet characterSetWithCharactersInString:@"/"]];
        if ([host hasPrefix:@"http://"] || [host hasPrefix:@"https://"]) {
            base = [NSURL URLWithString:host];
        } else {
            base = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", host]];
        }
    }
    if (!base.host) {
        return nil;
    }
    NSString *scheme = base.scheme.length > 0 ? base.scheme : @"https";
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }
    NSString *path = ATProtoRASLWellKnownPathForCID(cid);
    NSString *urlString = [NSString stringWithFormat:@"%@://%@%@", scheme, base.host, path];
    if (base.port) {
        urlString = [NSString stringWithFormat:@"%@://%@:%@%@", scheme, base.host, base.port, path];
    }
    return [NSURL URLWithString:urlString];
}

- (NSData *)fetchObjectBytesForCID:(ATProtoCID *)cid
                         providers:(NSArray<NSString *> *)providers
                             error:(NSError **)error {
    if (!cid || providers.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoCAMirrorHTTPSFetcherErrorDomain
                                         code:ATProtoCAMirrorHTTPSFetcherErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"CID and providers required"}];
        }
        return nil;
    }

    NSError *lastError = nil;
    for (NSString *provider in providers) {
        NSURL *url = [ATProtoCAMirrorHTTPSFetcher raslURLForCID:cid providerBaseURL:provider];
        if (!url) {
            continue;
        }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"GET";
        request.timeoutInterval = self.timeout;
        NSHTTPURLResponse *response = nil;
        NSError *reqError = nil;
        NSData *body = [self.httpClient sendSynchronousRequest:request
                                                       options:nil
                                                      response:&response
                                                         error:&reqError];
        if (reqError) {
            lastError = reqError;
            continue;
        }
        if (response.statusCode != 200 || body.length == 0) {
            lastError = [NSError errorWithDomain:ATProtoCAMirrorHTTPSFetcherErrorDomain
                                            code:ATProtoCAMirrorHTTPSFetcherErrorAllProvidersFailed
                                        userInfo:@{
                NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Provider %@ returned HTTP %ld",
                     provider, (long)response.statusCode]
            }];
            continue;
        }
        if (body.length > self.maxResponseBytes) {
            lastError = [NSError errorWithDomain:ATProtoCAMirrorHTTPSFetcherErrorDomain
                                            code:ATProtoCAMirrorHTTPSFetcherErrorAllProvidersFailed
                                        userInfo:@{NSLocalizedDescriptionKey: @"Response exceeds maxResponseBytes"}];
            continue;
        }
        return body;
    }

    if (error) {
        *error = lastError ?: [NSError errorWithDomain:ATProtoCAMirrorHTTPSFetcherErrorDomain
                                                  code:ATProtoCAMirrorHTTPSFetcherErrorAllProvidersFailed
                                              userInfo:@{NSLocalizedDescriptionKey: @"All providers failed"}];
    }
    return nil;
}

@end
