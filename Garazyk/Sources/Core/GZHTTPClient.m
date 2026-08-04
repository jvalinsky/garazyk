// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/GZHTTPClient.h"

NSErrorDomain const GZHTTPClientErrorDomain = @"com.atproto.safe-http";

@implementation GZHTTPClientOptions

+ (instancetype)defaultOptions {
    GZHTTPClientOptions *options = [[self alloc] init];
    options.timeout = 10.0;
    options.maxResponseBytes = 1024 * 1024;
    options.allowHTTP = NO;
    options.allowPrivateHosts = NO;
    options.followRedirects = YES;
    return options;
}

- (id)copyWithZone:(NSZone *)zone {
    GZHTTPClientOptions *copy = [[[self class] allocWithZone:zone] init];
    copy.timeout = self.timeout;
    copy.maxResponseBytes = self.maxResponseBytes;
    copy.allowHTTP = self.allowHTTP;
    copy.allowPrivateHosts = self.allowPrivateHosts;
    copy.followRedirects = self.followRedirects;
    return copy;
}

@end

@interface GZUnavailableHTTPClient : NSObject <GZHTTPClient>
@end

@implementation GZUnavailableHTTPClient

- (NSError *)unavailableError {
    return [NSError errorWithDomain:GZHTTPClientErrorDomain
                                code:GZHTTPClientErrorUnavailable
                            userInfo:@{NSLocalizedDescriptionKey: @"No HTTP transport has been registered"}];
}

- (void)performDataTaskWithRequest:(NSURLRequest *)request
                            options:(GZHTTPClientOptions *)options
                         completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    if (completion) {
        completion(nil, nil, [self unavailableError]);
    }
}

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                            options:(GZHTTPClientOptions *)options
                           response:(NSHTTPURLResponse **)response
                              error:(NSError **)error {
    if (response) {
        *response = nil;
    }
    if (error) {
        *error = [self unavailableError];
    }
    return nil;
}

- (void)performDataTaskWithRequest:(NSURLRequest *)request
                            timeout:(NSTimeInterval)timeout
                         completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    [self performDataTaskWithRequest:request options:nil completion:completion];
}

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                            timeout:(NSTimeInterval)timeout
                           response:(NSHTTPURLResponse **)response
                              error:(NSError **)error {
    return [self sendSynchronousRequest:request options:nil response:response error:error];
}

@end

static id<GZHTTPClient> gSharedGZHTTPClient = nil;
static id<GZHTTPClient> GZDefaultHTTPClient(void) {
    static id<GZHTTPClient> unavailableClient = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        unavailableClient = [[GZUnavailableHTTPClient alloc] init];
    });
    return gSharedGZHTTPClient ?: unavailableClient;
}

@implementation GZHTTPClientRegistry

+ (id<GZHTTPClient>)sharedClient {
    return GZDefaultHTTPClient();
}

+ (void)setSharedClient:(id<GZHTTPClient>)client {
    gSharedGZHTTPClient = client;
}

@end
