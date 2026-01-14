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
#import <Security/Security.h>
#import <resolv.h>
#import <arpa/nameser.h>
#import <netdb.h>
#import <netinet/in.h>
#import <string.h>
#import <sys/socket.h>
#import <arpa/inet.h>

NSString * const HandleErrorDomain = @"com.atproto.handle";

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
        _session = nil;  // NSURLConnection uses class methods, no session object needed
#endif
        _resolutionCache = [[NSCache alloc] init];
        _cacheExpirationInterval = 300.0; // 5 minutes
        _rateLimitPerMinute = 100; // Allow 100 resolutions per minute
        _requestTimestamps = [NSMutableArray array];
    }
    return self;
}

- (void)resolveHandle:(NSString *)handle
                      completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion {

    /*! Check rate limit before attempting resolution. */
    if (![self checkRateLimit]) {
        NSError *rateLimitError = [NSError errorWithDomain:HandleErrorDomain
                                                   code:HandleErrorNetworkError
                                               userInfo:@{NSLocalizedDescriptionKey: @"Rate limit exceeded"}];
        completion(nil, rateLimitError);
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
            completion(did, nil);
        } else if (error && [error.domain isEqualToString:HandleErrorDomain] &&
                   error.code == HandleErrorNotFound) {
            /*! Fallback to DNS TXT record lookup on 404 response. */
            [self resolveHandleViaDNS:handle completion:completion];
        } else {
            /*! Wrap network errors in HandleErrorDomain for consistent error handling. */
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
    
#if defined(__APPLE__)
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
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
            
            int txt_len = txt_data[0];
            NSString *txt_str = [[NSString alloc] initWithBytes:txt_data + 1 length:txt_len encoding:NSUTF8StringEncoding];
            
            if ([txt_str hasPrefix:@"did="]) {
                NSString *did = [txt_str substringFromIndex:4];
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
            /*! IPv6 address validation. */
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

/*!
 @method isPrivateIPv4Address:

 @abstract Checks if an IPv4 address is in a private or reserved range.

 @discussion Blocks RFC 1918 private addresses (10.x, 172.16.x, 192.168.x),
 loopback (127.x), link-local (169.254.x), multicast (224.x), and TEST-NET
 ranges used for documentation (192.0.2.x, 198.51.100.x, 203.0.113.x).

 @param ip The IPv4 address in network byte order (ntohl applied).
 @return YES if address is private/reserved, NO if public.
 */
- (BOOL)isPrivateIPv4Address:(uint32_t)ip {
    /*! RFC 1918 private ranges: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16. */
    if ((ip & 0xFF000000) == 0x0A000000) return YES;      // 10.0.0.0/8
    if ((ip & 0xFFF00000) == 0xAC100000) return YES;      // 172.16.0.0/12
    if ((ip & 0xFFFF0000) == 0xC0A80000) return YES;      // 192.168.0.0/16

    /*! Loopback: 127.0.0.0/8. */
    if ((ip & 0xFF000000) == 0x7F000000) return YES;      // 127.0.0.0/8

    /*! Link-local: 169.254.0.0/16. */
    if ((ip & 0xFFFF0000) == 0xA9FE0000) return YES;      // 169.254.0.0/16

    /*! TEST-NET documentation ranges (RFC 5737). */
    if ((ip & 0xFF000000) == 0x00000000) return YES;      // 0.0.0.0/8
    if ((ip & 0xFFC00000) == 0x64400000) return YES;      // 100.64.0.0/10 (RFC 6598)
    if ((ip & 0xFFFFFF00) == 0xC0000000) return YES;      // 192.0.0.0/24 (IETF protocol)
    if ((ip & 0xFFFFFF00) == 0xC0000200) return YES;      // 192.0.2.0/24 (TEST-NET-1)
    if ((ip & 0xFFFFFF00) == 0xC6336400) return YES;      // 198.51.100.0/24 (TEST-NET-2)
    if ((ip & 0xFFFFFF00) == 0xCB007100) return YES;      // 203.0.113.0/24 (TEST-NET-3)

    /*! Multicast (224.0.0.0/4) and reserved for future use (240.0.0.0/4). */
    if ((ip & 0xF0000000) == 0xE0000000) return YES;      // 224.0.0.0/4
    if ((ip & 0xF0000000) == 0xF0000000) return YES;      // 240.0.0.0/4

    return NO;
}

/*!
 @method isPrivateIPv6Address:

 @abstract Checks if an IPv6 address is in a private or reserved range.

 @discussion Blocks loopback (::1), unique local addresses (fc00::/7),
 link-local (fe80::/10), and IPv4-mapped IPv6 addresses containing
 private IPv4 addresses.

 @param ip6 The IPv6 address structure.
 @return YES if address is private/reserved, NO if public.
 */
- (BOOL)isPrivateIPv6Address:(struct in6_addr)ip6 {
    const uint8_t *bytes = ip6.s6_addr;

    /*! Loopback: ::1/128. */
    if (memcmp(&ip6, &in6addr_loopback, sizeof(struct in6_addr)) == 0) return YES;

    /*! Unique local addresses (ULA): fc00::/7. */
    if ((bytes[0] & 0xFE) == 0xFC) return YES;

    /*! Link-local: fe80::/10. */
    if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) return YES;

    /*! IPv4-mapped IPv6 addresses: ::ffff:0:0/96. */
    /*! Validate embedded IPv4 to prevent IPv4 private address bypass. */
    if (memcmp(bytes, (uint8_t[]){0,0,0,0,0,0,0,0,0,0,0xFF,0xFF}, 12) == 0) {
        /*! Extract embedded IPv4 from last 4 bytes. */
        uint32_t ipv4;
        memcpy(&ipv4, bytes + 12, sizeof(ipv4));
        ipv4 = ntohl(ipv4);
        /*! Recursively validate embedded IPv4 address. */
        return [self isPrivateIPv4Address:ipv4];
    }

    return NO;
}

@end
