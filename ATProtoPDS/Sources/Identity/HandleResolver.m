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
#import "Network/SSRFValidator.h"

#ifdef GNUSTEP
#import <Security/Security.h>
#else
#import <Security/Security.h>
#endif

#import <resolv.h>
#import <arpa/nameser.h>
#import <netdb.h>
#import <netinet/in.h>
#import <string.h>
#import <sys/socket.h>
#import <arpa/inet.h>

NSString * const HandleErrorDomain = @"com.atproto.handle";
static NSString *const kDefaultUserAgent = @"atprotopds/0.1.0";

@interface HandleResolutionFailure : NSObject
@property (nonatomic, assign) NSInteger failureCount;
@property (nonatomic, strong) NSDate *expiresAt;
@end

@implementation HandleResolutionFailure
@end

@implementation HandleResolver

- (instancetype)init {
    self = [super init];
    if (self) {
#if defined(__APPLE__)
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        config.timeoutIntervalForResource = 30.0;
        _session = [NSURLSession sessionWithConfiguration:config];
#else
        _session = nil;
#endif
        _resolutionCache = [[NSCache alloc] init];
        _failureCache = [[NSCache alloc] init];
        _cacheExpirationInterval = 300.0;
        _rateLimitPerMinute = 100;
        _requestTimestamps = [NSMutableArray array];
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

    /*! Prevent SSRF attacks by validating public IP resolution. */
    if (!self.skipSSRFCheck) {
        NSError *ssrfError = nil;
        if (![self validateHandleResolvesToPublicIP:handle error:&ssrfError]) {
            completion(nil, ssrfError);
            return;
        }
    }

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
    NSString *cachedDID = [self.resolutionCache objectForKey:handle];
    if (cachedDID) {
        completion(cachedDID, nil);
        return;
    }

    /*! Attempt HTTPS resolution first, fallback to DNS TXT for 404 errors. */
    [self resolveHandleViaHTTPS:handle completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        if (did) {
            /*! Cache successful resolution for future requests. */
            [self.resolutionCache setObject:did forKey:handle];
            [self.failureCache removeObjectForKey:handle]; // Clear failure count on success
            completion(did, nil);
        } else if (error && [error.domain isEqualToString:HandleErrorDomain] &&
                   error.code == HandleErrorNotFound) {
            /*! Fallback to DNS TXT record lookup on 404 response. */
            [self resolveHandleViaDNS:handle completion:^(NSString * _Nullable dnsDid, NSError * _Nullable dnsError) {
                if (dnsDid) {
                    [self.resolutionCache setObject:dnsDid forKey:handle];
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
    
    NSString *urlString = [NSString stringWithFormat:@"https://%@/.well-known/atproto-did", handle];
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url) {
        NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                          code:HandleErrorInvalidFormat
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from handle"}];
        completion(nil, error);
        return;
    }
    
#if defined(__APPLE__)
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:kDefaultUserAgent forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                              completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        if (error) {
            completion(nil, error);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                      code:HandleErrorNotFound
                                                  userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld when resolving handle", (long)httpResponse.statusCode]}];
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
    [task resume];
    
#else
    /*! Linux (GNUstep): Use NSURLConnection with synchronous request on background queue. */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        NSURLResponse *response = nil;
        NSError *error = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(nil, error);
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode != 200) {
                NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                          code:HandleErrorNotFound
                                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld when resolving handle", (long)httpResponse.statusCode]}];
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
        });
    });
#endif
}

- (void)resolveHandles:(NSArray<NSString *> *)handles
             completion:(void (^)(NSDictionary<NSString *, NSString *> * _Nullable results, NSError * _Nullable error))completion {

    NSMutableDictionary<NSString *, NSString *> *results = [NSMutableDictionary dictionary];
    __block NSUInteger remaining = handles.count;
    __block NSError *firstError = nil;

    if (remaining == 0) {
        completion(@{}, nil);
        return;
    }

    for (NSString *handle in handles) {
        [self resolveHandle:handle completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            @synchronized(results) {
                if (did) {
                    results[handle] = did;
                } else if (!firstError) {
                    firstError = error;
                }
            }

            remaining--;
            if (remaining == 0) {
                completion(results.count > 0 ? results : nil, firstError);
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
    @synchronized(self.requestTimestamps) {
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
            return NO;
        }

        // Add current timestamp
        [self.requestTimestamps addObject:now];
        return YES;
    }
}

#pragma mark - SSRF Protection

/*!
 @method validateHandleResolvesToPublicIP:error:

 @abstract Validates that a handle resolves to a public IP address.

 @discussion Performs DNS resolution and checks all resolved IP addresses
 against private/reserved ranges to prevent SSRF attacks. This includes
 RFC 1918 private addresses, loopback, link-local, and IPv6 private ranges.

 @param handle The handle to validate (nonnull).
 @param error On return, contains an error if validation failed.
 @return YES if handle resolves to public IP, NO otherwise.
 */
- (BOOL)validateHandleResolvesToPublicIP:(NSString *)handle error:(NSError **)error {
    /*! Resolve hostname to prevent DNS rebinding attacks. */
    CFHostRef hostRef = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)handle);
    if (!hostRef) {
        if (error) {
            *error = [NSError errorWithDomain:HandleErrorDomain
                                         code:HandleErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create host resolver"}];
        }
        return NO;
    }

    CFStreamError streamError;
    Boolean success = CFHostStartInfoResolution(hostRef, kCFHostAddresses, &streamError);

    if (!success) {
        CFRelease(hostRef);
        if (error) {
            *error = [NSError errorWithDomain:HandleErrorDomain
                                         code:HandleErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to resolve hostname"}];
        }
        return NO;
    }

    CFArrayRef addresses = CFHostGetAddressing(hostRef, NULL);
    if (!addresses || CFArrayGetCount(addresses) == 0) {
        CFRelease(hostRef);
        if (error) {
            *error = [NSError errorWithDomain:HandleErrorDomain
                                         code:HandleErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"No IP addresses found for hostname"}];
        }
        return NO;
    }

    /*! Validate each resolved IP address against private/reserved ranges. */
    for (CFIndex i = 0; i < CFArrayGetCount(addresses); i++) {
        struct sockaddr *addr = (struct sockaddr *)CFDataGetBytePtr(CFArrayGetValueAtIndex(addresses, i));

        if (addr->sa_family == AF_INET) {
            /*! IPv4 address validation. */
            struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
            uint32_t ip = ntohl(addr_in->sin_addr.s_addr);

            if ([SSRFValidator isPrivateIPv4Address:ip]) {
                CFRelease(hostRef);
                if (error) {
                    *error = [NSError errorWithDomain:HandleErrorDomain
                                                 code:HandleErrorSSRFAttempt
                                             userInfo:@{NSLocalizedDescriptionKey: @"Handle resolves to private IP address (SSRF protection)"}];
                }
                return NO;
            }
        } else if (addr->sa_family == AF_INET6) {
            /*! IPv6 address validation. */
            struct sockaddr_in6 *addr_in6 = (struct sockaddr_in6 *)addr;
            struct in6_addr ip6 = addr_in6->sin6_addr;

            if ([SSRFValidator isPrivateIPv6Address:ip6]) {
                CFRelease(hostRef);
                if (error) {
                    *error = [NSError errorWithDomain:HandleErrorDomain
                                                 code:HandleErrorSSRFAttempt
                                             userInfo:@{NSLocalizedDescriptionKey: @"Handle resolves to private IPv6 address (SSRF protection)"}];
                }
                return NO;
            }
        }
    }

    CFRelease(hostRef);
    return YES;
}

@end
