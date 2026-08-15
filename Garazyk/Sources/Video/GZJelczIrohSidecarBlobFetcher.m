// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczIrohSidecarBlobFetcher.h"
#import "Video/GZJelczIrohSidecarURL.h"
#import "Core/CID.h"

NSErrorDomain const GZJelczIrohSidecarBlobFetcherErrorDomain =
    @"GZJelczIrohSidecarBlobFetcherErrorDomain";

static NSString * const kGZJelczIrohProviderScheme = @"iroh://";

@implementation GZJelczIrohSidecarBlobFetcher

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                    sidecarBaseURL:(NSString *)sidecarBaseURL {
    return [self initWithHTTPClient:httpClient sidecarBaseURL:sidecarBaseURL trustLan:NO];
}

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                    sidecarBaseURL:(NSString *)sidecarBaseURL
                          trustLan:(BOOL)trustLan {
    NSParameterAssert(httpClient);
    NSString *normalized =
        [GZJelczIrohSidecarURL normalizedHTTPBase:sidecarBaseURL trustLan:trustLan];
    if (normalized.length == 0) {
        return nil;
    }
    self = [super init];
    if (self) {
        _httpClient = httpClient;
        _sidecarBaseURL = [normalized copy];
        _timeout = 60.0;
        _maxResponseBytes = 64ULL * 1024ULL * 1024ULL;
    }
    return self;
}

+ (NSString *)endpointIdFromIrohProviderHint:(NSString *)providerHint {
    if (providerHint.length == 0) {
        return nil;
    }
    if (![providerHint hasPrefix:kGZJelczIrohProviderScheme]) {
        return nil;
    }
    NSString *endpointId = [providerHint substringFromIndex:kGZJelczIrohProviderScheme.length];
    endpointId = [endpointId stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return endpointId.length > 0 ? endpointId : nil;
}

- (nullable NSString *)endpointTicketForEndpointId:(NSString *)endpointId {
    if (endpointId.length == 0) {
        return nil;
    }
    NSString *ticket = self.endpointTicketsByEndpointId[endpointId];
    if (ticket.length > 0) {
        return ticket;
    }
    if ([endpointId isEqualToString:self.defaultProviderEndpointId] &&
        self.defaultProviderEndpointTicket.length > 0) {
        return self.defaultProviderEndpointTicket;
    }
    return nil;
}

- (nullable NSData *)fetchObjectBytesForCID:(ATProtoCID *)cid
                                  providers:(NSArray<NSString *> *)providers
                                      error:(NSError **)error {
    if (!cid || providers.count == 0 || self.capabilityToken.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:GZJelczIrohSidecarBlobFetcherErrorDomain
                                         code:GZJelczIrohSidecarBlobFetcherErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"CID, providers, and sidecar capability required"}];
        }
        return nil;
    }

    NSMutableArray<NSString *> *endpointIds = [NSMutableArray array];
    for (NSString *provider in providers) {
        NSString *endpointId = [GZJelczIrohSidecarBlobFetcher endpointIdFromIrohProviderHint:provider];
        if (endpointId.length > 0) {
            [endpointIds addObject:endpointId];
        }
    }
    if (endpointIds.count == 0 && self.defaultProviderEndpointId.length > 0) {
        [endpointIds addObject:self.defaultProviderEndpointId];
    }
    if (endpointIds.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:GZJelczIrohSidecarBlobFetcherErrorDomain
                                         code:GZJelczIrohSidecarBlobFetcherErrorNoIrohProvider
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"No iroh:// provider endpointId in providers"}];
        }
        return nil;
    }

    NSURL *url = [NSURL URLWithString:[self.sidecarBaseURL stringByAppendingString:@"/v1/fetch"]];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:GZJelczIrohSidecarBlobFetcherErrorDomain
                                         code:GZJelczIrohSidecarBlobFetcherErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid sidecar base URL"}];
        }
        return nil;
    }

    NSError *lastError = nil;
    for (NSString *endpointId in endpointIds) {
        NSMutableDictionary *provider = [@{ @"endpointId": endpointId } mutableCopy];
        NSString *ticket = [self endpointTicketForEndpointId:endpointId];
        if (ticket.length > 0) {
            provider[@"endpointTicket"] = ticket;
        }
        NSDictionary *payload = @{
            @"cid": cid.stringValue,
            @"provider": provider,
        };
        NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&lastError];
        if (!body) {
            continue;
        }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        request.timeoutInterval = self.timeout;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        if (self.capabilityToken.length > 0) {
            [request setValue:[@"Bearer " stringByAppendingString:self.capabilityToken]
   forHTTPHeaderField:@"Authorization"];
        }
        request.HTTPBody = body;

        NSHTTPURLResponse *response = nil;
        NSError *reqError = nil;
        NSData *candidate = [self.httpClient sendSynchronousRequest:request
                                                            options:nil
                                                           response:&response
                                                              error:&reqError];
        if (reqError) {
            lastError = reqError;
            continue;
        }
        if (response.statusCode != 200) {
            lastError = [NSError errorWithDomain:GZJelczIrohSidecarBlobFetcherErrorDomain
                                            code:GZJelczIrohSidecarBlobFetcherErrorSidecarFailed
                                        userInfo:@{
                NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Sidecar fetch returned HTTP %ld for endpoint %@",
                     (long)response.statusCode, endpointId]
            }];
            continue;
        }
        // A zero-length object is a valid BLAKE3-addressed blob.  Distinguish
        // an absent response from an empty NSData so the resolver can verify
        // the empty-object CID before committing it to the CA store.
        if (!candidate) {
            lastError = [NSError errorWithDomain:GZJelczIrohSidecarBlobFetcherErrorDomain
                                            code:GZJelczIrohSidecarBlobFetcherErrorSidecarFailed
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       @"Sidecar returned no response body"}];
            continue;
        }
        if (candidate.length > self.maxResponseBytes) {
            lastError = [NSError errorWithDomain:GZJelczIrohSidecarBlobFetcherErrorDomain
                                            code:GZJelczIrohSidecarBlobFetcherErrorSidecarFailed
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       @"Sidecar response exceeds maxResponseBytes"}];
            continue;
        }
        return candidate;
    }

    if (error) {
        *error = lastError ?: [NSError errorWithDomain:GZJelczIrohSidecarBlobFetcherErrorDomain
                                                  code:GZJelczIrohSidecarBlobFetcherErrorSidecarFailed
                                              userInfo:@{NSLocalizedDescriptionKey:
                                                             @"All iroh sidecar providers failed"}];
    }
    return nil;
}

@end
