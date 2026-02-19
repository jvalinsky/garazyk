#ifdef GNUSTEP
#import "Compat/GNUstepCompat.h"
#endif

#import "Federation/FederationClient.h"
#import "Core/DID.h"
#import "Debug/PDSLogger.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconSchema.h"
#import "Lexicon/ATProtoLexiconDef.h"

#include <netinet/in.h>
#include <arpa/inet.h>
#import <CoreFoundation/CoreFoundation.h>

NSErrorDomain const FederationErrorDomain = @"com.atproto.federation";

static BOOL pds_isPrivateIPv4Address(uint32_t ip) {
    if ((ip & 0xFF000000) == 0x0A000000) return YES;      // 10.0.0.0/8
    if ((ip & 0xFFF00000) == 0xAC100000) return YES;      // 172.16.0.0/12
    if ((ip & 0xFFFF0000) == 0xC0A80000) return YES;      // 192.168.0.0/16
    if ((ip & 0xFF000000) == 0x7F000000) return YES;      // 127.0.0.0/8
    if ((ip & 0xFFFF0000) == 0xA9FE0000) return YES;      // 169.254.0.0/16
    if ((ip & 0xFF000000) == 0x00000000) return YES;      // 0.0.0.0/8
    if ((ip & 0xFFC00000) == 0x64400000) return YES;      // 100.64.0.0/10
    if ((ip & 0xFFFFFF00) == 0xC0000000) return YES;      // 192.0.0.0/24
    if ((ip & 0xFFFFFF00) == 0xC0000200) return YES;      // 192.0.2.0/24
    if ((ip & 0xFFFFFF00) == 0xC6336400) return YES;      // 198.51.100.0/24
    if ((ip & 0xFFFFFF00) == 0xCB007100) return YES;      // 203.0.113.0/24
    if ((ip & 0xF0000000) == 0xE0000000) return YES;      // 224.0.0.0/4
    if ((ip & 0xF0000000) == 0xF0000000) return YES;      // 240.0.0.0/4
    return NO;
}

static BOOL pds_isPrivateIPv6Address(struct in6_addr ip6) {
    const uint8_t *bytes = ip6.s6_addr;
    if (memcmp(&ip6, &in6addr_loopback, sizeof(struct in6_addr)) == 0) return YES;
    if ((bytes[0] & 0xFE) == 0xFC) return YES;            // fc00::/7
    if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) return YES; // fe80::/10
    if (memcmp(bytes, (uint8_t[]){0,0,0,0,0,0,0,0,0,0,0xFF,0xFF}, 12) == 0) {
        uint32_t ipv4;
        memcpy(&ipv4, bytes + 12, sizeof(ipv4));
        ipv4 = ntohl(ipv4);
        return pds_isPrivateIPv4Address(ipv4);
    }
    return NO;
}

static NSString *const kDefaultUserAgent = @"atprotopds/0.1.0";

@implementation FederationClient {
}

static NSString *PDSSanitizedURLString(NSURL *url) {
    if (!url) return @"";
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) return url.absoluteString ?: @"";
    components.query = nil;
    components.fragment = nil;
    return components.string ?: (url.absoluteString ?: @"");
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 60.0;
        _session = [NSURLSession sessionWithConfiguration:config];

        _didResolver = [[DIDResolver alloc] init];
    }
    return self;
}

- (void)forwardXrpcRequest:(NSString *)method
                parameters:(nullable NSDictionary *)parameters
                       did:(NSString *)did
                completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion {

    if (!completion) return;

    // Resolve the DID to find the PDS endpoint
    NSDictionary *atprotoData = [(DIDResolver *)self.didResolver resolveAtprotoDataForDID:did error:nil];
    if (!atprotoData || !atprotoData[@"pds"]) {
        NSError *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorDIDResolutionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to resolve PDS endpoint for DID"}];
        completion(nil, error);
        return;
    }

    NSString *pdsEndpoint = atprotoData[@"pds"];
    if (![pdsEndpoint hasPrefix:@"http"]) {
        pdsEndpoint = [NSString stringWithFormat:@"https://%@", pdsEndpoint];
    }

    // SSRF protection: validate PDS endpoint resolves to public IP
    NSURL *pdsURL = [NSURL URLWithString:pdsEndpoint];
    NSString *pdsHost = pdsURL.host;
    NSError *ssrfError = nil;
    if (![self validateHostResolvesToPublicIP:pdsHost error:&ssrfError]) {
        completion(nil, ssrfError);
        return;
    }

    // Construct the XRPC URL
    NSString *xrpcPath = [NSString stringWithFormat:@"/xrpc/%@", method];
    NSString *urlString = [NSString stringWithFormat:@"%@%@", pdsEndpoint, xrpcPath];

    // Add query parameters for GET requests
    if (parameters && [self isGetMethod:method]) {
        NSMutableArray<NSString *> *queryParts = [NSMutableArray array];
        for (NSString *key in parameters) {
            NSString *value = parameters[key];
            if ([value isKindOfClass:[NSString class]]) {
                NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                NSString *encodedValue = [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                [queryParts addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
            }
        }
        if (queryParts.count > 0) {
            urlString = [NSString stringWithFormat:@"%@?%@", urlString, [queryParts componentsJoinedByString:@"&"]];
        }
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed for remote request"}];
        completion(nil, error);
        return;
    }

    PDS_LOG_SERVICE_INFO(@"Forwarding XRPC request (method=%@, did=%@) to %@", method ?: @"", did ?: @"", PDSSanitizedURLString(url));

    // Prepare the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = [self isGetMethod:method] ? @"GET" : @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:kDefaultUserAgent forHTTPHeaderField:@"User-Agent"];

    // Add JSON body for POST requests
    if (parameters && ![self isGetMethod:method]) {
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:&jsonError];
        if (jsonError) {
            NSError *error = [NSError errorWithDomain:FederationErrorDomain
                                             code:FederationErrorNetworkError
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize request parameters",
                                                   NSUnderlyingErrorKey: jsonError}];
            completion(nil, error);
            return;
        }
        request.HTTPBody = jsonData;
    }

    // Execute the request
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {

        if (error) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorNetworkError
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Network error during remote request",
                                                              NSUnderlyingErrorKey: error}];
            completion(nil, federationError);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorRemoteServerError
                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Remote server returned HTTP %ld", (long)httpResponse.statusCode]}];
            completion(nil, federationError);
            return;
        }

        if (!data) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorInvalidResponse
                                                    userInfo:@{NSLocalizedDescriptionKey: @"No data received from remote server"}];
            completion(nil, federationError);
            return;
        }

        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorInvalidResponse
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON response from remote server",
                                                              NSUnderlyingErrorKey: jsonError}];
            completion(nil, federationError);
            return;
        }

        completion(jsonResponse, nil);
    }];

    [task resume];
}

- (void)forwardHttpRequest:(NSURL *)url
                    method:(NSString *)method
                   headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                      body:(nullable NSData *)body
                completion:(void (^)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))completion {

    if (!completion) return;

    PDS_LOG_SERVICE_INFO(@"Forwarding HTTP request (method=%@) to %@", method ?: @"", PDSSanitizedURLString(url));

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;

    // Add headers
    for (NSString *key in headers) {
        [request setValue:headers[key] forHTTPHeaderField:key];
    }

    request.HTTPBody = body;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        completion(data, (NSHTTPURLResponse *)response, error);
    }];

    [task resume];
}

- (void)forwardXrpcBinaryRequest:(NSString *)method
                      parameters:(nullable NSDictionary *)parameters
                             did:(NSString *)did
                      completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion {

    if (!completion) return;

    // Resolve the DID to find the PDS endpoint
    NSDictionary *atprotoData = [(DIDResolver *)self.didResolver resolveAtprotoDataForDID:did error:nil];
    if (!atprotoData || !atprotoData[@"pds"]) {
        NSError *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorDIDResolutionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to resolve PDS endpoint for DID"}];
        completion(nil, error);
        return;
    }

    NSString *pdsEndpoint = atprotoData[@"pds"];
    if (![pdsEndpoint hasPrefix:@"http"]) {
        pdsEndpoint = [NSString stringWithFormat:@"https://%@", pdsEndpoint];
    }

    // SSRF protection: validate PDS endpoint resolves to public IP
    NSURL *binaryPdsURL = [NSURL URLWithString:pdsEndpoint];
    NSError *ssrfError = nil;
    if (![self validateHostResolvesToPublicIP:binaryPdsURL.host error:&ssrfError]) {
        completion(nil, ssrfError);
        return;
    }

    // Construct the XRPC URL
    NSString *xrpcPath = [NSString stringWithFormat:@"/xrpc/%@", method];
    NSString *urlString = [NSString stringWithFormat:@"%@%@", pdsEndpoint, xrpcPath];

    // Add query parameters
    if (parameters) {
        NSMutableArray<NSString *> *queryParts = [NSMutableArray array];
        for (NSString *key in parameters) {
            NSString *value = parameters[key];
            if ([value isKindOfClass:[NSString class]]) {
                NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                NSString *encodedValue = [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                [queryParts addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
            }
        }
        if (queryParts.count > 0) {
            urlString = [NSString stringWithFormat:@"%@?%@", urlString, [queryParts componentsJoinedByString:@"&"]];
        }
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed for remote request"}];
        completion(nil, error);
        return;
    }

    PDS_LOG_SERVICE_INFO(@"Forwarding binary XRPC request (method=%@, did=%@) to %@", method ?: @"", did ?: @"", PDSSanitizedURLString(url));

    // Prepare the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Accept"];
    [request setValue:kDefaultUserAgent forHTTPHeaderField:@"User-Agent"];

    // Execute the request
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {

        if (error) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorNetworkError
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Network error during remote request",
                                                              NSUnderlyingErrorKey: error}];
            completion(nil, federationError);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorRemoteServerError
                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Remote server returned HTTP %ld", (long)httpResponse.statusCode]}];
            completion(nil, federationError);
            return;
        }

        if (!data) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorInvalidResponse
                                                    userInfo:@{NSLocalizedDescriptionKey: @"No data received from remote server"}];
            completion(nil, federationError);
            return;
        }

        completion(data, nil);
    }];

    [task resume];
}

#pragma mark - Helper Methods

- (BOOL)validateHostResolvesToPublicIP:(NSString *)hostname error:(NSError **)error {
    if (!hostname || hostname.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty hostname"}];
        }
        return NO;
    }

    CFHostRef hostRef = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)hostname);
    if (!hostRef) {
        if (error) {
            *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create host reference"}];
        }
        return NO;
    }

    CFStreamError streamError;
    if (!CFHostStartInfoResolution(hostRef, kCFHostAddresses, &streamError)) {
        CFRelease(hostRef);
        if (error) {
            *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"DNS resolution failed"}];
        }
        return NO;
    }

    CFArrayRef addresses = CFHostGetAddressing(hostRef, NULL);
    if (!addresses || CFArrayGetCount(addresses) == 0) {
        CFRelease(hostRef);
        if (error) {
            *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"No IP addresses found for hostname"}];
        }
        return NO;
    }

    for (CFIndex i = 0; i < CFArrayGetCount(addresses); i++) {
        struct sockaddr *addr = (struct sockaddr *)CFDataGetBytePtr(CFArrayGetValueAtIndex(addresses, i));

        if (addr->sa_family == AF_INET) {
            struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
            uint32_t ip = ntohl(addr_in->sin_addr.s_addr);
            if (pds_isPrivateIPv4Address(ip)) {
                CFRelease(hostRef);
                if (error) {
                    *error = [NSError errorWithDomain:FederationErrorDomain
                                                 code:FederationErrorNetworkError
                                             userInfo:@{NSLocalizedDescriptionKey: @"PDS endpoint resolves to private IP address (SSRF protection)"}];
                }
                return NO;
            }
        } else if (addr->sa_family == AF_INET6) {
            struct sockaddr_in6 *addr_in6 = (struct sockaddr_in6 *)addr;
            struct in6_addr ip6 = addr_in6->sin6_addr;
            if (pds_isPrivateIPv6Address(ip6)) {
                CFRelease(hostRef);
                if (error) {
                    *error = [NSError errorWithDomain:FederationErrorDomain
                                                 code:FederationErrorNetworkError
                                             userInfo:@{NSLocalizedDescriptionKey: @"PDS endpoint resolves to private IPv6 address (SSRF protection)"}];
                }
                return NO;
            }
        }
    }

    CFRelease(hostRef);
    return YES;
}

- (BOOL)isGetMethod:(NSString *)method {
    // Check the lexicon registry first
    ATProtoLexiconSchema *schema = [[ATProtoLexiconRegistry sharedRegistry] schemaForNSID:method];
    if (schema) {
        ATProtoLexiconDef *mainDef = [schema mainDefinition];
        if (mainDef) {
            return mainDef.type == ATProtoLexiconDefTypeQuery;
        }
    }

    // Fallback for unregistered lexicons
    static NSSet<NSString *> *getFallbacks = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        getFallbacks = [NSSet setWithArray:@[
            @"com.atproto.repo.getRecord",
            @"com.atproto.repo.listRecords",
            @"com.atproto.repo.describeRepo",
            @"com.atproto.sync.getRepo",
            @"com.atproto.sync.getHead",
            @"com.atproto.sync.getBlob",
            @"com.atproto.sync.listBlobs"
        ]];
    });

    return [getFallbacks containsObject:method];
}

@end
