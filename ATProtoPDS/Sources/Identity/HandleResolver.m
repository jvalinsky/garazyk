#import "Identity/HandleResolver.h"
#import "Identity/ATProtoHandleValidator.h"
#import <netinet/in.h>
#import <sys/socket.h>
#import <arpa/inet.h>

NSString * const HandleErrorDomain = @"com.atproto.handle";

@implementation HandleResolver

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        config.timeoutIntervalForResource = 30.0;
        _session = [NSURLSession sessionWithConfiguration:config];
        _resolutionCache = [[NSCache alloc] init];
        _cacheExpirationInterval = 300.0; // 5 minutes
        _rateLimitPerMinute = 100; // Allow 100 resolutions per minute
        _requestTimestamps = [NSMutableArray array];
    }
    return self;
}

- (void)resolveHandle:(NSString *)handle
                     completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion {

    // Rate limiting check
    if (![self checkRateLimit]) {
        NSError *rateLimitError = [NSError errorWithDomain:HandleErrorDomain
                                                   code:HandleErrorNetworkError
                                               userInfo:@{NSLocalizedDescriptionKey: @"Rate limit exceeded"}];
        completion(nil, rateLimitError);
        return;
    }

    // Validate handle format first
    NSError *validationError = nil;
    if (![ATProtoHandleValidator validateHandle:handle error:&validationError]) {
        completion(nil, validationError);
        return;
    }

    // Normalize handle
    handle = [ATProtoHandleValidator normalizeHandle:handle];

    // SSRF Protection: Check if handle resolves to private/internal IPs
    if (!self.skipSSRFCheck) {
        NSError *ssrfError = nil;
        if (![self validateHandleResolvesToPublicIP:handle error:&ssrfError]) {
            completion(nil, ssrfError);
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
    
    // Check cache first
    NSString *cachedDID = [self.resolutionCache objectForKey:handle];
    if (cachedDID) {
        completion(cachedDID, nil);
        return;
    }

    // Try HTTPS resolution first, then DNS TXT fallback for specific errors
    [self resolveHandleViaHTTPS:handle completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        if (did) {
            // Cache successful resolution
            [self.resolutionCache setObject:did forKey:handle];
            completion(did, nil);
        } else if (error && [error.domain isEqualToString:HandleErrorDomain] &&
                   error.code == HandleErrorNotFound) {
            // Try DNS TXT fallback only for 404 Not Found errors
            [self resolveHandleViaDNS:handle completion:completion];
        } else {
            // Ensure network errors are properly wrapped
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
    
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                              completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        if (error) {
            // Pass error up to main method for DNS fallback
            completion(nil, error);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            // Pass error up to main method for DNS fallback
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
        
        // Basic validation that it's a DID
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

    // DNS TXT resolution: look for _atproto.{handle} TXT record
    // Note: This is a placeholder implementation. Full DNS TXT support would require
    // a dedicated DNS library or raw DNS query implementation.

    NSString *dnsName = [NSString stringWithFormat:@"_atproto.%@", handle];

    // For now, we simulate DNS resolution failure since we don't have TXT record support
    // In a full implementation, this would query DNS TXT records and parse the DID

    NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                      code:HandleErrorNotFound
                                  userInfo:@{NSLocalizedDescriptionKey: @"DNS TXT record resolution not implemented",
                                            @"dns_name": dnsName,
                                            @"note": @"DNS TXT fallback requires additional DNS library implementation"}];
    completion(nil, error);
}

- (BOOL)checkRateLimit {
    @synchronized(self.requestTimestamps) {
        NSDate *now = [NSDate date];
        NSTimeInterval oneMinuteAgo = [now timeIntervalSince1970] - 60.0;

        // Remove timestamps older than 1 minute
        [self.requestTimestamps filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDate *timestamp, NSDictionary *bindings) {
            return [timestamp timeIntervalSince1970] > oneMinuteAgo;
        }]];

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

- (BOOL)validateHandleResolvesToPublicIP:(NSString *)handle error:(NSError **)error {
    // Resolve the handle to IP addresses to prevent DNS rebinding attacks
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

    // Check each resolved IP address
    for (CFIndex i = 0; i < CFArrayGetCount(addresses); i++) {
        struct sockaddr *addr = (struct sockaddr *)CFDataGetBytePtr(CFArrayGetValueAtIndex(addresses, i));

        if (addr->sa_family == AF_INET) {
            // IPv4
            struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
            uint32_t ip = ntohl(addr_in->sin_addr.s_addr);

            if ([self isPrivateIPv4Address:ip]) {
                CFRelease(hostRef);
                if (error) {
                    *error = [NSError errorWithDomain:HandleErrorDomain
                                                 code:HandleErrorSSRFAttempt
                                             userInfo:@{NSLocalizedDescriptionKey: @"Handle resolves to private IP address (SSRF protection)"}];
                }
                return NO;
            }
        } else if (addr->sa_family == AF_INET6) {
            // IPv6
            struct sockaddr_in6 *addr_in6 = (struct sockaddr_in6 *)addr;
            struct in6_addr ip6 = addr_in6->sin6_addr;

            if ([self isPrivateIPv6Address:ip6]) {
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

- (BOOL)isPrivateIPv4Address:(uint32_t)ip {
    // RFC 1918 private ranges
    // 10.0.0.0/8
    if ((ip & 0xFF000000) == 0x0A000000) return YES;
    // 172.16.0.0/12
    if ((ip & 0xFFF00000) == 0xAC100000) return YES;
    // 192.168.0.0/16
    if ((ip & 0xFFFF0000) == 0xC0A80000) return YES;
    // 127.0.0.0/8 (loopback)
    if ((ip & 0xFF000000) == 0x7F000000) return YES;
    // 169.254.0.0/16 (link-local)
    if ((ip & 0xFFFF0000) == 0xA9FE0000) return YES;

    return NO;
}

- (BOOL)isPrivateIPv6Address:(struct in6_addr)ip6 {
    // IPv6 private ranges
    // ::1/128 (loopback)
    if (memcmp(&ip6, &in6addr_loopback, sizeof(struct in6_addr)) == 0) return YES;

    // fc00::/7 (unique local addresses)
    if ((ip6.s6_addr[0] & 0xFE) == 0xFC) return YES;

    // fe80::/10 (link-local)
    if ((ip6.s6_addr[0] == 0xFE) && ((ip6.s6_addr[1] & 0xC0) == 0x80)) return YES;

    return NO;
}

@end