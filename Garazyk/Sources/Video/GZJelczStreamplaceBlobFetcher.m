// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczStreamplaceBlobFetcher.h"
#import "Core/CID.h"

NSErrorDomain const GZJelczStreamplaceBlobFetcherErrorDomain =
    @"GZJelczStreamplaceBlobFetcherErrorDomain";

/** Lexicon NSID — keep in sync with place.stream.playback.getVideoBlob. */
static NSString * const kGZJelczStreamplaceGetVideoBlobNSID =
    @"place.stream.playback.getVideoBlob";

static NSString *GZPercentEncodeQueryValue(NSString *value) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

static NSURL *GZNormalizeProviderBase(NSString *providerBaseURL) {
    if (providerBaseURL.length == 0) {
        return nil;
    }
    NSString *trimmed = [providerBaseURL stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    trimmed = [trimmed stringByTrimmingCharactersInSet:
               [NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSURL *base = [NSURL URLWithString:trimmed];
    if (!base || !base.host) {
        if ([trimmed hasPrefix:@"http://"] || [trimmed hasPrefix:@"https://"]) {
            base = [NSURL URLWithString:trimmed];
        } else {
            base = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", trimmed]];
        }
    }
    if (!base.host) {
        return nil;
    }
    NSString *scheme = base.scheme.length > 0 ? base.scheme : @"https";
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }
    if (base.port) {
        return [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@:%@",
                                     scheme, base.host, base.port]];
    }
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", scheme, base.host]];
}

@interface GZJelczStreamplaceBlobFetcher ()
@property (atomic, assign, readwrite) NSUInteger successCount;
@property (atomic, assign, readwrite) NSUInteger blobNotFoundCount;
@property (atomic, assign, readwrite) NSUInteger failureCount;
@property (atomic, strong, readwrite, nullable) NSDate *lastSuccessAt;
@end

@implementation GZJelczStreamplaceBlobFetcher

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                   attributionDID:(NSString *)attributionDID {
    NSParameterAssert(httpClient);
    NSParameterAssert(attributionDID.length > 0);
    self = [super init];
    if (self) {
        _httpClient = httpClient;
        _attributionDID = [attributionDID copy];
        _timeout = 30.0;
        _maxResponseBytes = 64ULL * 1024ULL * 1024ULL;
    }
    return self;
}

+ (NSURL *)getVideoBlobURLForCID:(ATProtoCID *)cid
                 attributionDID:(NSString *)attributionDID
                providerBaseURL:(NSString *)providerBaseURL {
    if (!cid || attributionDID.length == 0 || providerBaseURL.length == 0) {
        return nil;
    }
    NSURL *base = GZNormalizeProviderBase(providerBaseURL);
    if (!base) {
        return nil;
    }
    NSString *cidStr = cid.stringValue ?: @"";
    if ([cidStr.lowercaseString hasSuffix:@".m4s"]) {
        cidStr = [cidStr substringToIndex:cidStr.length - 4];
    }
    if (cidStr.length == 0) {
        return nil;
    }
    NSString *path = [NSString stringWithFormat:@"/xrpc/%@",
                      kGZJelczStreamplaceGetVideoBlobNSID];
    NSString *query = [NSString stringWithFormat:@"did=%@&cid=%@",
                       GZPercentEncodeQueryValue(attributionDID),
                       GZPercentEncodeQueryValue(cidStr)];
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@%@?%@",
                                 base.absoluteString, path, query]];
}

- (NSDictionary *)allowlistedStatsDictionary {
    NSString *lastSuccess = nil;
    if (self.lastSuccessAt) {
        NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
        lastSuccess = [fmt stringFromDate:self.lastSuccessAt];
    }
    return @{
        @"successCount": @(self.successCount),
        @"blobNotFoundCount": @(self.blobNotFoundCount),
        @"failureCount": @(self.failureCount),
        @"lastSuccessAt": lastSuccess ?: [NSNull null],
        @"attributionDIDConfigured": @(self.attributionDID.length > 0),
    };
}

- (NSData *)fetchObjectBytesForCID:(ATProtoCID *)cid
                         providers:(NSArray<NSString *> *)providers
                             error:(NSError **)error {
    return [self fetchObjectBytesForCID:cid providers:providers rangeHeader:nil error:error];
}

- (NSData *)fetchObjectBytesForCID:(ATProtoCID *)cid
                         providers:(NSArray<NSString *> *)providers
                       rangeHeader:(NSString *)rangeHeader
                             error:(NSError **)error {
    if (!cid || providers.count == 0 || self.attributionDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:GZJelczStreamplaceBlobFetcherErrorDomain
                                         code:GZJelczStreamplaceBlobFetcherErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"CID, providers, and attributionDID required"}];
        }
        return nil;
    }

    NSError *lastError = nil;
    BOOL sawBlobNotFound = NO;
    for (NSString *provider in providers) {
        NSURL *url = [GZJelczStreamplaceBlobFetcher getVideoBlobURLForCID:cid
                                                          attributionDID:self.attributionDID
                                                         providerBaseURL:provider];
        if (!url) {
            continue;
        }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"GET";
        request.timeoutInterval = self.timeout;
        if (rangeHeader.length > 0) {
            [request setValue:rangeHeader forHTTPHeaderField:@"Range"];
        }

        NSHTTPURLResponse *response = nil;
        NSError *reqError = nil;
        NSData *body = [self.httpClient sendSynchronousRequest:request
                                                       options:nil
                                                      response:&response
                                                         error:&reqError];
        if (reqError) {
            lastError = reqError;
            self.failureCount += 1;
            continue;
        }
        if (response.statusCode == 404) {
            sawBlobNotFound = YES;
            self.blobNotFoundCount += 1;
            lastError = [NSError errorWithDomain:GZJelczStreamplaceBlobFetcherErrorDomain
                                            code:GZJelczStreamplaceBlobFetcherErrorBlobNotFound
                                        userInfo:@{
                NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"BlobNotFound from %@", provider]
            }];
            continue;
        }
        NSInteger expected = rangeHeader.length > 0 ? 206 : 200;
        if (response.statusCode != 200 && response.statusCode != 206) {
            self.failureCount += 1;
            lastError = [NSError errorWithDomain:GZJelczStreamplaceBlobFetcherErrorDomain
                                            code:GZJelczStreamplaceBlobFetcherErrorAllProvidersFailed
                                        userInfo:@{
                NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Provider %@ returned HTTP %ld (expected %ld)",
                     provider, (long)response.statusCode, (long)expected]
            }];
            continue;
        }
        if (body.length == 0) {
            self.failureCount += 1;
            lastError = [NSError errorWithDomain:GZJelczStreamplaceBlobFetcherErrorDomain
                                            code:GZJelczStreamplaceBlobFetcherErrorAllProvidersFailed
                                        userInfo:@{NSLocalizedDescriptionKey: @"Empty body"}];
            continue;
        }
        if (body.length > self.maxResponseBytes) {
            self.failureCount += 1;
            lastError = [NSError errorWithDomain:GZJelczStreamplaceBlobFetcherErrorDomain
                                            code:GZJelczStreamplaceBlobFetcherErrorAllProvidersFailed
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       @"Response exceeds maxResponseBytes"}];
            continue;
        }
        self.successCount += 1;
        self.lastSuccessAt = [NSDate date];
        return body;
    }

    if (error) {
        if (sawBlobNotFound && !lastError) {
            *error = [NSError errorWithDomain:GZJelczStreamplaceBlobFetcherErrorDomain
                                         code:GZJelczStreamplaceBlobFetcherErrorBlobNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"BlobNotFound"}];
        } else {
            *error = lastError ?: [NSError errorWithDomain:GZJelczStreamplaceBlobFetcherErrorDomain
                                                      code:GZJelczStreamplaceBlobFetcherErrorAllProvidersFailed
                                                  userInfo:@{NSLocalizedDescriptionKey:
                                                                 @"All Streamplace providers failed"}];
        }
    }
    return nil;
}

@end
