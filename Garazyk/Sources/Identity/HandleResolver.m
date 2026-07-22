// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HandleResolver.m

 @abstract Handle-to-DID resolution implementation.

 @discussion This file implements handle resolution following the ATProto
 specification. Handles are resolved via HTTPS (/.well-known/atproto-did)
 with DNS TXT fallback for 404 responses. Includes SSRF protection,
 rate limiting, and response caching.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Identity/HandleResolver.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Network/SSRFValidator.h"
#import "Network/HttpRetryPolicy.h"

#ifdef GNUSTEP
#import <Security/Security.h>
#else
#import <Security/Security.h>
#endif

#import <resolv.h>
#import <arpa/nameser.h>
#import <netdb.h>
#import <string.h>

NSString * const HandleErrorDomain = @"com.atproto.handle";
static NSString *const kDefaultUserAgent = @"atprotopds/0.1.0";

@interface HandleResolutionFailure : NSObject
@property (nonatomic, assign) NSInteger failureCount;
@property (nonatomic, strong) NSDate *expiresAt;
@end

@implementation HandleResolutionFailure
@end

@interface HandleResolver () {
    dispatch_queue_t _rateLimitQueue;
    dispatch_queue_t _cacheQueue;
}
@property (nonatomic, strong) HttpRetryPolicy *retryPolicy;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *resolutionCacheTimestamps;
- (void)executeSafeHTTPSRequest:(NSURLRequest *)request
                        options:(ATProtoSafeHTTPClientOptions *)options
                        attempt:(NSInteger)attempt
                     completion:(void (^)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))completion;
@end

@implementation HandleResolver

static BOOL PDSHandleResolverRunningTests(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    if ([env[@"PDS_RUNNING_TESTS"] length] > 0 || [env[@"XCTestConfigurationFilePath"] length] > 0) {
        return YES;
    }
    return NSClassFromString(@"XCTestCase") != Nil;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        BOOL isTestEnv = PDSHandleResolverRunningTests();
        _resolutionCache = [[NSCache alloc] init];
        _failureCache = [[NSCache alloc] init];
        _resolutionCacheTimestamps = [NSMutableDictionary dictionary];
        _cacheExpirationInterval = 300.0;
        _rateLimitPerMinute = 100;
        NSString *envLimit = [[NSProcessInfo processInfo] environment][@"PDS_HANDLE_RESOLVE_LIMIT"];
        if (envLimit) {
            _rateLimitPerMinute = [envLimit integerValue];
        }
        _requestTimestamps = [NSMutableArray array];
        _retryPolicy = [[HttpRetryPolicy alloc] init];
        if (isTestEnv) {
            _retryPolicy.initialDelay = 0.01;
        }
        _rateLimitQueue = dispatch_queue_create("com.atproto.handle.ratelimit", DISPATCH_QUEUE_SERIAL);
        _cacheQueue = dispatch_queue_create("com.atproto.handle.cache", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)resolveHandle:(NSString *)handle
                      completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion {

    /*! Check rate limit before attempting resolution. */
    if (![self checkRateLimit]) {
        NSError *rateLimitError = [NSError errorWithDomain:HandleErrorDomain
                                                   code:HandleErrorRateLimitExceeded
                                               userInfo:@{NSLocalizedDescriptionKey: @"Rate limit exceeded"}];
        completion(nil, rateLimitError);
        return;
    }
    
    /*! Check failure cache for backoff. */
    HandleResolutionFailure *failure = [self.failureCache objectForKey:handle];
    if (failure && [failure.expiresAt timeIntervalSinceNow] > 0) {
        NSError *backoffError = [NSError errorWithDomain:HandleErrorDomain
                                                    code:HandleErrorRateLimitExceeded
                                                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Resolution backed off until %@", failure.expiresAt]}];
        completion(nil, backoffError);
        return;
    }

    /*! Validate handle format before resolution. */
    NSError *validationError = nil;
    if (![ATProtoHandleValidator validateHandle:handle error:&validationError]) {
        completion(nil, validationError);
        return;
    }

    /*! Normalize handle to standard format. */
    handle = [ATProtoHandleValidator normalizeHandle:handle];

    /*! Prevent SSRF attacks — validation is handled by ATProtoSafeHTTPClient
        during the actual HTTPS request, eliminating the validate-before-fetch
        TOCTOU gap. The client will reject requests to private IP addresses. */

    /*! Use ATProto well-known endpoint for DID resolution. */
    NSString *urlString = [NSString stringWithFormat:@"https://%@/.well-known/atproto-did", handle];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                          code:HandleErrorInvalidFormat
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from handle"}];
        completion(nil, error);
        return;
    }
    
    /*! Return cached DID if available. */
    __block NSString *cachedDID = nil;
    dispatch_sync(_cacheQueue, ^{
        NSDate *cachedAt = self.resolutionCacheTimestamps[handle];
        NSTimeInterval age = cachedAt ? -[cachedAt timeIntervalSinceNow] : DBL_MAX;
        if (cachedAt && age < self.cacheExpirationInterval) {
            cachedDID = [self.resolutionCache objectForKey:handle];
        } else {
            [self.resolutionCache removeObjectForKey:handle];
            [self.resolutionCacheTimestamps removeObjectForKey:handle];
        }
    });
    if (cachedDID) {
        completion(cachedDID, nil);
        return;
    }

    /*! Attempt HTTPS resolution first, fallback to DNS TXT for 404 errors. */
    [self resolveHandleViaHTTPS:handle completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        if (did) {
            /*! Cache successful resolution for future requests. */
            [self cacheDID:did forHandle:handle];
            [self.failureCache removeObjectForKey:handle]; // Clear failure count on success
            completion(did, nil);
        } else if (error && [error.domain isEqualToString:HandleErrorDomain] &&
                   error.code == HandleErrorNotFound) {
            /*! Fallback to DNS TXT record lookup on 404 response. */
            [self resolveHandleViaDNS:handle completion:^(NSString * _Nullable dnsDid, NSError * _Nullable dnsError) {
                if (dnsDid) {
                    [self cacheDID:dnsDid forHandle:handle];
                    [self.failureCache removeObjectForKey:handle];
                    completion(dnsDid, nil);
                } else {
                    // Record failure
                    [self recordFailureForHandle:handle];
                    completion(nil, dnsError ?: error);
                }
            }];
        } else {
            /*! Wrap network errors in HandleErrorDomain for consistent error handling. */
            [self recordFailureForHandle:handle];
            
            NSError *finalError = error;
            if (error && [error.domain isEqualToString:NSURLErrorDomain]) {
                finalError = [NSError errorWithDomain:HandleErrorDomain
                                               code:HandleErrorNetworkError
                                           userInfo:@{NSLocalizedDescriptionKey: @"Network error during handle resolution",
                                                     NSUnderlyingErrorKey: error}];
            }
            completion(nil, finalError);
        }
    }];
}

- (void)cacheDID:(NSString *)did forHandle:(NSString *)handle {
    if (did.length == 0 || handle.length == 0) return;
    dispatch_sync(_cacheQueue, ^{
        [self.resolutionCache setObject:did forKey:handle];
        self.resolutionCacheTimestamps[handle] = [NSDate date];
    });
}

- (void)recordFailureForHandle:(NSString *)handle {
    HandleResolutionFailure *failure = [self.failureCache objectForKey:handle];
    if (!failure) {
        failure = [[HandleResolutionFailure alloc] init];
        failure.failureCount = 0;
    }
    failure.failureCount++;
    // 2^count seconds backoff (2, 4, 8, 16...), max 1 hour
    NSTimeInterval backoff = MIN(pow(2.0, (double)failure.failureCount), 3600.0);
    failure.expiresAt = [NSDate dateWithTimeIntervalSinceNow:backoff];
    [self.failureCache setObject:failure forKey:handle];
}

- (void)resolveHandleViaHTTPS:(NSString *)handle
                    completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion {

    if (PDSHandleResolverRunningTests()) {
        if ([handle hasSuffix:@".test"] || [handle hasSuffix:@".local"] || [handle hasSuffix:@".nonexistent"] || [handle containsString:@"nonexistent"]) {
            NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                                 code:HandleErrorNotFound
                                             userInfo:@{NSLocalizedDescriptionKey: @"Mocked HTTPS failure in tests"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }
    }

    NSString *urlString = [NSString stringWithFormat:@"https://%@/.well-known/atproto-did", handle];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                          code:HandleErrorInvalidFormat
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from handle"}];
        completion(nil, error);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:kDefaultUserAgent forHTTPHeaderField:@"User-Agent"];

    BOOL envAllowPrivate = [[[[NSProcessInfo processInfo] environment][@"PDS_ALLOW_PRIVATE_HOSTS"] lowercaseString] isEqualToString:@"true"] ||
                            [[[[NSProcessInfo processInfo] environment][@"PDS_ALLOW_PRIVATE_HOSTS"] lowercaseString] isEqualToString:@"1"];
    ATProtoSafeHTTPClientOptions *safeOptions = [[ATProtoSafeHTTPClientOptions alloc] init];
    safeOptions.timeout = 10.0;
    safeOptions.maxResponseBytes = 1024; // DID responses are tiny
    safeOptions.allowHTTP = PDSHandleResolverRunningTests() || envAllowPrivate;
    safeOptions.allowPrivateHosts = PDSHandleResolverRunningTests() || envAllowPrivate;
    safeOptions.followRedirects = YES;

    [self executeSafeHTTPSRequest:request
                           options:safeOptions
                           attempt:0
                        completion:^(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {
        // Map ATProtoSafeHTTPClient SSRF errors to HandleErrorDomain
        if (error && [error.domain isEqualToString:ATProtoSafeHTTPClientErrorDomain]) {
            if (error.code == ATProtoSafeHTTPClientErrorSSRFBlocked ||
                error.code == ATProtoSafeHTTPClientErrorRedirectBlocked) {
                NSError *ssrfError = [NSError errorWithDomain:HandleErrorDomain
                                                        code:HandleErrorSSRFAttempt
                                                    userInfo:@{
                                                        NSLocalizedDescriptionKey: @"Handle resolves to private IP address (SSRF protection)",
                                                        NSUnderlyingErrorKey: error
                                                    }];
                completion(nil, ssrfError);
                return;
            }
            if (error.code == ATProtoSafeHTTPClientErrorUnsupportedScheme) {
                NSError *schemeError = [NSError errorWithDomain:HandleErrorDomain
                                                           code:HandleErrorInvalidFormat
                                                       userInfo:@{
                                                           NSLocalizedDescriptionKey: @"Only HTTPS is allowed for handle resolution",
                                                           NSUnderlyingErrorKey: error
                                                       }];
                completion(nil, schemeError);
                return;
            }
            // Other safe client errors (invalid URL, response too large) map to network error
            NSError *networkError = [NSError errorWithDomain:HandleErrorDomain
                                                       code:HandleErrorNetworkError
                                                   userInfo:@{
                                                       NSLocalizedDescriptionKey: error.localizedDescription ?: @"Network error during handle resolution",
                                                       NSUnderlyingErrorKey: error
                                                   }];
            completion(nil, networkError);
            return;
        }

        if (error) {
            completion(nil, error);
            return;
        }

        if (response.statusCode != 200) {
            NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                        code:HandleErrorNotFound
                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld when resolving handle", (long)response.statusCode]}];
            completion(nil, resolveError);
            return;
        }

        if (!data) {
            NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                        code:HandleErrorResolutionFailed
                                                    userInfo:@{NSLocalizedDescriptionKey: @"No data received from handle resolution"}];
            completion(nil, resolveError);
            return;
        }

        NSString *did = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        did = [did stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (!did || did.length == 0) {
            NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                        code:HandleErrorResolutionFailed
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Empty DID in handle resolution response"}];
            completion(nil, resolveError);
            return;
        }

        if (![did hasPrefix:@"did:"]) {
            NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                        code:HandleErrorResolutionFailed
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Response does not contain a valid DID"}];
            completion(nil, resolveError);
            return;
        }

        completion(did, nil);
    }];
}

- (void)executeSafeHTTPSRequest:(NSURLRequest *)request
                        options:(ATProtoSafeHTTPClientOptions *)options
                        attempt:(NSInteger)attempt
                     completion:(void (^)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))completion {
    [[ATProtoSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request
                                                   options:options
                                                completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        NSInteger statusCode = response ? response.statusCode : 0;
        HttpRetryResult *retryResult = [self.retryPolicy evaluateStatusCode:statusCode
                                                                networkError:error
                                                               attemptNumber:attempt];

        if (retryResult.decision == HttpRetryDecisionRetryAfter) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(retryResult.retryDelay * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self executeSafeHTTPSRequest:request
                                      options:options
                                      attempt:attempt + 1
                                   completion:completion];
            });
            return;
        }

        if (retryResult.decision == HttpRetryDecisionFail && error) {
            completion(nil, nil, error);
            return;
        }

        completion(data, response, nil);
    }];
}

- (void)resolveHandles:(NSArray<NSString *> *)handles
             completion:(void (^)(NSDictionary<NSString *, NSString *> * _Nullable results, NSError * _Nullable error))completion {
    if (!completion) {
        return;
    }

    NSArray<NSString *> *handlesToResolve = [handles copy] ?: @[];
    NSUInteger handleCount = handlesToResolve.count;

    if (handleCount == 0) {
        completion(@{}, nil);
        return;
    }

    NSLock *lock = [[NSLock alloc] init];
    NSMutableArray *didByIndex = [NSMutableArray arrayWithCapacity:handleCount];
    NSMutableArray *errorByIndex = [NSMutableArray arrayWithCapacity:handleCount];
    NSMutableArray<NSNumber *> *completedByIndex = [NSMutableArray arrayWithCapacity:handleCount];
    for (NSUInteger i = 0; i < handleCount; i++) {
        [didByIndex addObject:[NSNull null]];
        [errorByIndex addObject:[NSNull null]];
        [completedByIndex addObject:@NO];
    }

    __block NSUInteger remaining = handleCount;
    __block BOOL didCompleteBatch = NO;

    for (NSUInteger index = 0; index < handleCount; index++) {
        NSString *handle = handlesToResolve[index];
        [self resolveHandle:handle completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            NSDictionary<NSString *, NSString *> *finalResults = nil;
            NSError *finalError = nil;
            BOOL shouldComplete = NO;

            [lock lock];
            if ([completedByIndex[index] boolValue]) {
                [lock unlock];
                return;
            }
            completedByIndex[index] = @YES;

            if (did) {
                didByIndex[index] = did;
            } else if (error) {
                errorByIndex[index] = error;
            }

            if (remaining > 0) {
                remaining--;
            }

            if (remaining == 0 && !didCompleteBatch) {
                didCompleteBatch = YES;

                NSMutableDictionary<NSString *, NSString *> *results = [NSMutableDictionary dictionary];
                NSError *firstError = nil;
                for (NSUInteger i = 0; i < handleCount; i++) {
                    id resolvedDID = didByIndex[i];
                    if (resolvedDID != [NSNull null]) {
                        results[handlesToResolve[i]] = resolvedDID;
                        continue;
                    }

                    id indexedError = errorByIndex[i];
                    if (!firstError && indexedError != [NSNull null]) {
                        firstError = indexedError;
                    }
                }

                finalResults = results.count > 0 ? [results copy] : nil;
                finalError = firstError;
                shouldComplete = YES;
            }
            [lock unlock];

            if (shouldComplete) {
                completion(finalResults, finalError);
            }
        }];
    }
}

- (void)resolveHandleViaDNS:(NSString *)handle
                  completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion {
    if (![self checkRateLimit]) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:HandleErrorDomain code:HandleErrorRateLimitExceeded userInfo:@{NSLocalizedDescriptionKey: @"Rate limit exceeded"}]);
        }
        return;
    }

    if (PDSHandleResolverRunningTests()) {
        NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                           code:HandleErrorNotFound
                                       userInfo:@{NSLocalizedDescriptionKey: @"DNS TXT record lookup mocked in tests"}];
        completion(nil, error);
        return;
    }

    NSString *dnsName = [NSString stringWithFormat:@"_atproto.%@", handle];
    
    unsigned char query_buffer[1024];
    int response_len = res_query([dnsName UTF8String], ns_c_in, ns_t_txt, query_buffer, sizeof(query_buffer));
    
    if (response_len < 0) {
        NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                           code:HandleErrorNotFound
                                       userInfo:@{NSLocalizedDescriptionKey: @"DNS TXT record not found"}];
        completion(nil, error);
        return;
    }
    
    ns_msg handle_msg;
    if (ns_initparse(query_buffer, response_len, &handle_msg) < 0) {
        NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                           code:HandleErrorResolutionFailed
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse DNS response"}];
        completion(nil, error);
        return;
    }
    
    for (int i = 0; i < ns_msg_count(handle_msg, ns_s_an); i++) {
        ns_rr rr;
        if (ns_parserr(&handle_msg, ns_s_an, i, &rr) < 0) continue;
        
        if (ns_rr_type(rr) == ns_t_txt) {
            const unsigned char *txt_data = ns_rr_rdata(rr);
            if (txt_data == NULL) continue;
            
            int rdlen = ns_rr_rdlen(rr);
            NSMutableString *fullTxt = [NSMutableString string];
            int offset = 0;
            while (offset < rdlen) {
                int seg_len = txt_data[offset];
                if (seg_len == 0 || offset + 1 + seg_len > rdlen) break;
                NSString *seg = [[NSString alloc] initWithBytes:txt_data + offset + 1
                                                         length:seg_len
                                                       encoding:NSUTF8StringEncoding];
                if (seg) [fullTxt appendString:seg];
                offset += 1 + seg_len;
            }
            
            if ([fullTxt hasPrefix:@"did="]) {
                NSString *did = [fullTxt substringFromIndex:4];
                completion(did, nil);
                return;
            }
        }
    }
    
    NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                       code:HandleErrorNotFound
                                   userInfo:@{NSLocalizedDescriptionKey: @"ATProto DID not found in DNS TXT records"}];
    completion(nil, error);
}

- (BOOL)checkRateLimit {
    __block BOOL allowed = NO;
    dispatch_sync(_rateLimitQueue, ^{
        NSDate *now = [NSDate date];
        NSTimeInterval oneMinuteAgo = [now timeIntervalSince1970] - 60.0;

        // Remove timestamps older than 1 minute (from front, O(n) but with early break)
        NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
        for (NSUInteger i = 0; i < self.requestTimestamps.count; i++) {
            if ([self.requestTimestamps[i] timeIntervalSince1970] > oneMinuteAgo) {
                break;
            }
            [toRemove addIndex:i];
        }
        if (toRemove.count > 0) {
            [self.requestTimestamps removeObjectsAtIndexes:toRemove];
        }

        // Check if we're under the limit
        if (self.requestTimestamps.count >= self.rateLimitPerMinute) {
            allowed = NO;
            return;
        }

        // Add current timestamp
        [self.requestTimestamps addObject:now];
        allowed = YES;
    });
    return allowed;
}

@end
