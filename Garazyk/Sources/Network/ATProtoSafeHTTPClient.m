// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/ATProtoSafeHTTPClient.h"
#import "Network/SSRFValidator.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <Network/Network.h>
#endif

#if defined(GNUSTEP)
#import <curl/curl.h>
#import <unistd.h>

// Context structs for libcurl callbacks — must be defined before @implementation
typedef struct {
    NSMutableData *bodyData;
    NSUInteger maxBytes;
    BOOL exceededLimit;
} PDSCurlWriteContext;

typedef struct {
    NSMutableDictionary *headers;
    long statusCode;
    BOOL gotStatusLine;
} PDSCurlHeaderContext;

// Socket tracking callbacks for CURLOPT_OPENSOCKETFUNCTION / CLOSESOCKETFUNCTION
static curl_socket_t pds_curl_open_socket(void *clientp,
                                          curlsocktype purpose,
                                          struct curl_sockaddr *address) {
    curl_socket_t sockfd = socket(address->family, address->socktype, address->protocol);
    if (sockfd >= 0) {
        NSMutableSet<NSNumber *> *openSockets = (__bridge NSMutableSet<NSNumber *> *)clientp;
        [openSockets addObject:@(sockfd)];
    }
    return sockfd;
}

static int pds_curl_close_socket(void *clientp, curl_socket_t sockfd) {
    NSMutableSet<NSNumber *> *openSockets = (__bridge NSMutableSet<NSNumber *> *)clientp;
    [openSockets removeObject:@(sockfd)];
    close(sockfd);
    return 0;
}

// libcurl write callback — receives response body data
static size_t pds_curl_write_cb(void *contents, size_t size, size_t nmemb, void *userp) {
    PDSCurlWriteContext *ctx = (PDSCurlWriteContext *)userp;
    size_t totalSize = size * nmemb;
    if (ctx->exceededLimit) {
        return 0;
    }
    if (ctx->maxBytes > 0 && ctx->bodyData.length + totalSize > ctx->maxBytes) {
        ctx->exceededLimit = YES;
        return 0;
    }
    [ctx->bodyData appendBytes:contents length:totalSize];
    return totalSize;
}

// libcurl header callback — receives response headers
static size_t pds_curl_header_cb(void *contents, size_t size, size_t nmemb, void *userp) {
    PDSCurlHeaderContext *ctx = (PDSCurlHeaderContext *)userp;
    size_t totalSize = size * nmemb;
    char *headerStr = (char *)contents;

    if (!ctx->gotStatusLine && totalSize > 5 && strncmp(headerStr, "HTTP/", 5) == 0) {
        ctx->gotStatusLine = YES;
        char *space = strchr(headerStr, ' ');
        if (space) {
            ctx->statusCode = atoi(space + 1);
        }
        return totalSize;
    }

    if (totalSize > 0 && headerStr[0] != '\r' && headerStr[0] != '\n') {
        char *colon = memchr(headerStr, ':', totalSize);
        if (colon) {
            size_t nameLen = colon - headerStr;
            size_t valueStart = nameLen + 1;
            while (valueStart < totalSize && (headerStr[valueStart] == ' ' || headerStr[valueStart] == '\t')) {
                valueStart++;
            }
            size_t valueLen = totalSize - valueStart;
            while (valueLen > 0 && (headerStr[valueStart + valueLen - 1] == '\r' || headerStr[valueStart + valueLen - 1] == '\n')) {
                valueLen--;
            }
            NSString *name = [[NSString alloc] initWithBytes:headerStr length:nameLen encoding:NSUTF8StringEncoding];
            NSString *value = [[NSString alloc] initWithBytes:(headerStr + valueStart) length:valueLen encoding:NSUTF8StringEncoding];
            if (name && value) {
                ctx->headers[name] = value;
            }
        }
    }

    return totalSize;
}

#endif // defined(GNUSTEP)

NSErrorDomain const ATProtoSafeHTTPClientErrorDomain = @"com.atproto.safe-http";

static BOOL PDSIsLoopbackHost(NSString *host) {
    NSString *normalized = host.lowercaseString;
    return [normalized isEqualToString:@"127.0.0.1"] ||
           [normalized isEqualToString:@"localhost"] ||
           [normalized isEqualToString:@"::1"];
}

@implementation ATProtoSafeHTTPClientOptions

+ (instancetype)defaultOptions {
    ATProtoSafeHTTPClientOptions *options = [[ATProtoSafeHTTPClientOptions alloc] init];
    options.timeout = 10.0;
    options.maxResponseBytes = 1024 * 1024;
    options.allowHTTP = NO;
    options.allowPrivateHosts = NO;
    options.followRedirects = YES;
    return options;
}

- (id)copyWithZone:(NSZone *)zone {
    ATProtoSafeHTTPClientOptions *copy = [[[self class] allocWithZone:zone] init];
    copy.timeout = self.timeout;
    copy.maxResponseBytes = self.maxResponseBytes;
    copy.allowHTTP = self.allowHTTP;
    copy.allowPrivateHosts = self.allowPrivateHosts;
    copy.followRedirects = self.followRedirects;
    return copy;
}

@end

#if defined(GNUSTEP)

// On GNUstep, NSURLSession (libcurl backend) does not properly close
// sockets when the remote side sends FIN on idle pooled connections,
// leaving them in CLOSE-WAIT indefinitely. We bypass NSURLSession
// entirely and use libcurl directly with a multi handle, which gives
// us full control over the socket lifecycle.

@interface ATProtoSafeHTTPClient ()
@property (nonatomic, strong) NSLock *stateLock;
@end

@implementation ATProtoSafeHTTPClient

+ (instancetype)sharedClient {
    static ATProtoSafeHTTPClient *client = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [[ATProtoSafeHTTPClient alloc] init];
    });
    return client;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _stateLock = [[NSLock alloc] init];
    }
    return self;
}

+ (NSError *)errorWithCode:(ATProtoSafeHTTPClientErrorCode)code
               description:(NSString *)description
           underlyingError:(NSError *)underlyingError {
    NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey : description ?: @"Safe HTTP request rejected"} mutableCopy];
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:ATProtoSafeHTTPClientErrorDomain code:code userInfo:userInfo];
}

+ (BOOL)validateURL:(NSURL *)url options:(ATProtoSafeHTTPClientOptions *)options error:(NSError **)error {
    ATProtoSafeHTTPClientOptions *effective = options ?: [ATProtoSafeHTTPClientOptions defaultOptions];
    if (!url || url.host.length == 0 || url.scheme.length == 0) {
        if (error) {
            *error = [self errorWithCode:ATProtoSafeHTTPClientErrorInvalidURL
                             description:@"URL must include a scheme and host"
                         underlyingError:nil];
        }
        return NO;
    }

    NSString *host = url.host.lowercaseString;
    BOOL isLoopback = PDSIsLoopbackHost(host);

    if (!isLoopback) {
        NSString *scheme = url.scheme.lowercaseString;
        BOOL allowHTTP = effective.allowHTTP;
        if (!allowHTTP) {
            NSString *envAllow = [[NSProcessInfo processInfo] environment][@"PDS_ALLOW_HTTP"];
            if ([envAllow isEqualToString:@"1"] || [envAllow isEqualToString:@"true"]) {
                allowHTTP = YES;
            }
        }

        BOOL schemeAllowed = [scheme isEqualToString:@"https"] ||
                             (allowHTTP && [scheme isEqualToString:@"http"]);
        if (!schemeAllowed) {
            if (error) {
                *error = [self errorWithCode:ATProtoSafeHTTPClientErrorUnsupportedScheme
                                 description:@"Only HTTPS is allowed for this outbound request"
                             underlyingError:nil];
            }
            return NO;
        }

        BOOL allowPrivate = effective.allowPrivateHosts;
        if (!allowPrivate) {
            NSString *envAllow = [[NSProcessInfo processInfo] environment][@"PDS_ALLOW_PRIVATE_SSRF"];
            if ([envAllow isEqualToString:@"1"] || [envAllow isEqualToString:@"true"]) {
                allowPrivate = YES;
            }
        }

        if (!allowPrivate) {
            NSError *ssrfError = nil;
            if (![SSRFValidator validateHostResolvesToPublicIP:url.host error:&ssrfError]) {
                if (error) {
                    *error = [self errorWithCode:ATProtoSafeHTTPClientErrorSSRFBlocked
                                     description:@"Outbound request target failed SSRF validation"
                                 underlyingError:ssrfError];
                }
                return NO;
            }
        }
    }

    return YES;
}

#pragma mark - Direct libcurl request

- (void)performSafeDataTaskWithRequest:(NSURLRequest *)request
                    options:(ATProtoSafeHTTPClientOptions *)options
                 completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    [self performSafeDataTaskWithRequest:request options:options redirectCount:0 completion:completion];
}

- (void)performSafeDataTaskWithRequest:(NSURLRequest *)request
                    options:(ATProtoSafeHTTPClientOptions *)options
                 redirectCount:(NSUInteger)redirectCount
                 completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    if (!completion) {
        return;
    }
    ATProtoSafeHTTPClientOptions *effective = [options copy] ?: [ATProtoSafeHTTPClientOptions defaultOptions];
    NSError *validationError = nil;
    if (![[self class] validateURL:request.URL options:effective error:&validationError]) {
        completion(nil, nil, validationError);
        return;
    }

    NSURL *url = [request.URL absoluteURL];
    NSString *urlString = [url absoluteString];
    NSArray<NSString *> *pinnedAddresses = nil;
    if (!PDSIsLoopbackHost(url.host) && !effective.allowPrivateHosts) {
        NSError *resolutionError = nil;
        if (![SSRFValidator resolvePinnedAddressesForHost:url.host
                                                  timeout:effective.timeout
                                                resolver:nil
                                                addresses:&pinnedAddresses
                                                    error:&resolutionError]) {
            completion(nil, nil, [[self class] errorWithCode:ATProtoSafeHTTPClientErrorSSRFBlocked
                                                  description:@"Outbound request target failed SSRF validation"
                                              underlyingError:resolutionError]);
            return;
        }
    }
    NSTimeInterval timeout = effective.timeout;
    NSUInteger maxBytes = effective.maxResponseBytes;
    NSData *postBody = request.HTTPBody;
    NSString *method = request.HTTPMethod ?: @"GET";
    NSDictionary *requestHeaders = request.allHTTPHeaderFields;
    BOOL followRedirects = effective.followRedirects;
    ATProtoSafeHTTPClientOptions *opts = effective;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        CURL *curl = curl_easy_init();
        CURLM *multi = curl_multi_init();
        if (!curl || !multi) {
            if (curl) curl_easy_cleanup(curl);
            if (multi) curl_multi_cleanup(multi);
            NSError *err = [NSError errorWithDomain:ATProtoSafeHTTPClientErrorDomain
                                               code:0
                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to initialize curl handle"}];
            completion(nil, nil, err);
            return;
        }

        curl_easy_setopt(curl, CURLOPT_URL, [urlString UTF8String]);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, (long)timeout);
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, (long)MIN(timeout, 10.0));
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
        curl_easy_setopt(curl, CURLOPT_NOPROXY, "*");

        struct curl_slist *resolveEntries = NULL;
        if (pinnedAddresses.count > 0) {
            NSInteger port = url.port.integerValue;
            if (port == 0) {
                port = [[url.scheme lowercaseString] isEqualToString:@"https"] ? 443 : 80;
            }
            for (NSString *address in pinnedAddresses) {
                NSString *numericAddress = [address containsString:@":"]
                    ? [NSString stringWithFormat:@"[%@]", address]
                    : address;
                NSString *entry = [NSString stringWithFormat:@"%@:%ld:%@",
                                   url.host, (long)port, numericAddress];
                resolveEntries = curl_slist_append(resolveEntries, entry.UTF8String);
            }
            curl_easy_setopt(curl, CURLOPT_RESOLVE, resolveEntries);
        }

        struct curl_slist *headers = NULL;
        headers = curl_slist_append(headers, "Connection: close");
        curl_easy_setopt(curl, CURLOPT_FORBID_REUSE, 1L);

        // Track socket FDs so we can force-close any that cleanup leaks
        NSMutableSet<NSNumber *> *openSockets = [NSMutableSet set];
        curl_easy_setopt(curl, CURLOPT_OPENSOCKETFUNCTION, pds_curl_open_socket);
        curl_easy_setopt(curl, CURLOPT_OPENSOCKETDATA, (__bridge void *)openSockets);
        curl_easy_setopt(curl, CURLOPT_CLOSESOCKETFUNCTION, pds_curl_close_socket);
        curl_easy_setopt(curl, CURLOPT_CLOSESOCKETDATA, (__bridge void *)openSockets);

        if ([method isEqualToString:@"POST"]) {
            curl_easy_setopt(curl, CURLOPT_POST, 1L);
            if (postBody) {
                curl_easy_setopt(curl, CURLOPT_POSTFIELDS, [postBody bytes]);
                curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)[postBody length]);
            }
        } else if (![method isEqualToString:@"GET"]) {
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, [method UTF8String]);
        }

        for (NSString *key in requestHeaders) {
            if ([key caseInsensitiveCompare:@"Connection"] == NSOrderedSame) {
                continue;
            }
            NSString *headerLine = [NSString stringWithFormat:@"%@: %@", key, requestHeaders[key]];
            headers = curl_slist_append(headers, [headerLine UTF8String]);
        }
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

        // Redirects are executed one hop at a time below. Letting curl follow
        // them internally would bypass validation and pinning for the target.
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);

        PDSCurlWriteContext writeCtx = {
            .bodyData = [NSMutableData data],
            .maxBytes = maxBytes,
            .exceededLimit = NO
        };
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, pds_curl_write_cb);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &writeCtx);

        PDSCurlHeaderContext headerCtx = {
            .headers = [NSMutableDictionary dictionary],
            .statusCode = 0,
            .gotStatusLine = NO
        };
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, pds_curl_header_cb);
        curl_easy_setopt(curl, CURLOPT_HEADERDATA, &headerCtx);

        curl_multi_add_handle(multi, curl);

        int stillRunning = 0;
        CURLMcode mres;
        do {
            mres = curl_multi_perform(multi, &stillRunning);
            if (mres != CURLM_OK) break;
            int numfds = 0;
            curl_multi_wait(multi, NULL, 0, (int)(timeout * 1000), &numfds);
        } while (stillRunning);

        CURLcode res = CURLE_OK;
        int msgsLeft = 0;
        CURLMsg *msg = curl_multi_info_read(multi, &msgsLeft);
        if (msg && msg->msg == CURLMSG_DONE) {
            res = msg->data.result;
        }

        long httpCode = 0;
        if (res == CURLE_OK) {
            curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
        } else if (headerCtx.statusCode > 0) {
            httpCode = headerCtx.statusCode;
        }

        char *finalUrl = NULL;
        curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &finalUrl);
        NSError *redirectBlockError = nil;
        if (finalUrl && followRedirects) {
            NSString *finalUrlStr = [NSString stringWithUTF8String:finalUrl];
            NSURL *finalNSURL = [NSURL URLWithString:finalUrlStr];
            if (finalNSURL && ![finalNSURL.host isEqualToString:url.host]) {
                NSError *redirectError = nil;
                if (![[self class] validateURL:finalNSURL options:opts error:&redirectError]) {
                    redirectBlockError = [[self class] errorWithCode:ATProtoSafeHTTPClientErrorRedirectBlocked
                                                       description:@"Redirect target failed SSRF validation"
                                                   underlyingError:redirectError];
                }
            }
        }

        // Snapshot tracked sockets before cleanup
        NSSet<NSNumber *> *leakedSockets = [openSockets copy];

        // Remove easy handle, then clean up both. curl_multi_cleanup
        // closes ALL connections in the multi handle's cache.
        curl_multi_remove_handle(multi, curl);
        curl_slist_free_all(headers);
        curl_slist_free_all(resolveEntries);
        curl_easy_cleanup(curl);
        curl_multi_cleanup(multi);

        // Force-close any sockets that the cleanup path didn't close.
        for (NSNumber *fdNum in leakedSockets) {
            close([fdNum intValue]);
        }

        if (redirectBlockError) {
            completion(nil, nil, redirectBlockError);
            return;
        }

        NSString *location = headerCtx.headers[@"Location"] ?: headerCtx.headers[@"location"];
        if (followRedirects && httpCode >= 300 && httpCode < 400 && location.length > 0) {
            if (redirectCount >= 5) {
                completion(nil, nil, [[self class] errorWithCode:ATProtoSafeHTTPClientErrorRedirectBlocked
                                                      description:@"Too many outbound redirects"
                                                  underlyingError:nil]);
                return;
            }
            NSURL *target = [[NSURL URLWithString:location relativeToURL:url] absoluteURL];
            NSError *redirectError = nil;
            if (!target || ![[self class] validateURL:target options:opts error:&redirectError]) {
                completion(nil, nil, [[self class] errorWithCode:ATProtoSafeHTTPClientErrorRedirectBlocked
                                                      description:@"Redirect target failed SSRF validation"
                                                  underlyingError:redirectError]);
                return;
            }
            NSMutableURLRequest *redirectRequest = [request mutableCopy];
            redirectRequest.URL = target;
            [self performSafeDataTaskWithRequest:redirectRequest
                                          options:opts
                                     redirectCount:redirectCount + 1
                                       completion:completion];
            return;
        }

        if (res != CURLE_OK) {
            if (writeCtx.exceededLimit) {
                NSError *sizeError = [[self class] errorWithCode:ATProtoSafeHTTPClientErrorResponseTooLarge
                                                      description:@"Outbound response exceeded size limit"
                                                  underlyingError:nil];
                NSHTTPURLResponse *httpResp = [[NSHTTPURLResponse alloc] initWithURL:url
                                                                          statusCode:httpCode
                                                                         HTTPVersion:@"HTTP/1.1"
                                                                        headerFields:headerCtx.headers];
                completion(nil, httpResp, sizeError);
                return;
            }
            NSError *curlError = [NSError errorWithDomain:NSURLErrorDomain
                                                     code:NSURLErrorCannotConnectToHost
                                                 userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithUTF8String:curl_easy_strerror(res)]}];
            completion(nil, nil, curlError);
            return;
        }

        NSHTTPURLResponse *httpResponse = [[NSHTTPURLResponse alloc] initWithURL:url
                                                                      statusCode:httpCode
                                                                     HTTPVersion:@"HTTP/1.1"
                                                                    headerFields:headerCtx.headers];
        completion(writeCtx.bodyData, httpResponse, nil);
    });
}

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(ATProtoSafeHTTPClientOptions *)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSData *resultData = nil;
    __block NSHTTPURLResponse *resultResponse = nil;
    __block NSError *resultError = nil;

    [self performSafeDataTaskWithRequest:request options:options completion:^(NSData *data, NSHTTPURLResponse *httpResponse, NSError *requestError) {
        resultData = data;
        resultResponse = httpResponse;
        resultError = requestError;
        dispatch_semaphore_signal(sema);
    }];

    NSTimeInterval timeout = (options ?: [ATProtoSafeHTTPClientOptions defaultOptions]).timeout + 1.0;
    if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
        resultError = [NSError errorWithDomain:NSURLErrorDomain
                                          code:NSURLErrorTimedOut
                                      userInfo:@{NSLocalizedDescriptionKey : @"Safe HTTP request timed out"}];
    }

    if (response) {
        *response = resultResponse;
    }
    if (error && resultError) {
        *error = resultError;
    }
    return resultError ? nil : resultData;
}

@end

#else // Apple platforms — NSURLSession for loopback and pinned NWConnection otherwise

@interface PDSPinnedHTTPTransport : NSObject
+ (void)performRequest:(NSURLRequest *)request
       pinnedAddresses:(NSArray<NSString *> *)pinnedAddresses
               timeout:(NSTimeInterval)timeout
            completion:(void (^)(NSData * _Nullable, NSHTTPURLResponse * _Nullable, NSError * _Nullable))completion;
+ (void)performRequest:(NSURLRequest *)request
       pinnedAddresses:(NSArray<NSString *> *)pinnedAddresses
          addressIndex:(NSUInteger)addressIndex
               timeout:(NSTimeInterval)timeout
            completion:(void (^)(NSData * _Nullable, NSHTTPURLResponse * _Nullable, NSError * _Nullable))completion;
@end

@implementation PDSPinnedHTTPTransport

+ (NSError *)connectionError:(NSString *)description {
    return [NSError errorWithDomain:NSURLErrorDomain
                               code:NSURLErrorCannotConnectToHost
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

+ (void)performRequest:(NSURLRequest *)request
       pinnedAddresses:(NSArray<NSString *> *)pinnedAddresses
               timeout:(NSTimeInterval)timeout
            completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    [self performRequest:request pinnedAddresses:pinnedAddresses addressIndex:0 timeout:timeout completion:completion];
}

+ (void)performRequest:(NSURLRequest *)request
       pinnedAddresses:(NSArray<NSString *> *)pinnedAddresses
          addressIndex:(NSUInteger)addressIndex
               timeout:(NSTimeInterval)timeout
            completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    NSURL *url = request.URL;
    NSString *address = addressIndex < pinnedAddresses.count ? pinnedAddresses[addressIndex] : nil;
    if (address.length == 0 || url.host.length == 0) {
        completion(nil, nil, [self connectionError:@"No pinned address is available"]);
        return;
    }

    NSInteger port = url.port.integerValue;
    if (port == 0) port = [[url.scheme lowercaseString] isEqualToString:@"https"] ? 443 : 80;
    NSString *portString = [NSString stringWithFormat:@"%ld", (long)port];
    BOOL secure = [[url.scheme lowercaseString] isEqualToString:@"https"];
    nw_parameters_t parameters = secure
        ? nw_parameters_create_secure_tcp(^(nw_protocol_options_t tlsOptions) {
            sec_protocol_options_t tls = nw_tls_copy_sec_protocol_options(tlsOptions);
            sec_protocol_options_set_tls_server_name(tls, url.host.UTF8String);
        }, NW_PARAMETERS_DEFAULT_CONFIGURATION)
        : nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);

    nw_endpoint_t endpoint = nw_endpoint_create_host(address.UTF8String, portString.UTF8String);
    nw_connection_t connection = nw_connection_create(endpoint, parameters);
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    __block BOOL finished = NO;
    void (^finish)(NSData *, NSHTTPURLResponse *, NSError *) = ^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (finished) return;
        finished = YES;
        nw_connection_cancel(connection);
        if (error && addressIndex + 1 < pinnedAddresses.count) {
            [self performRequest:request
                 pinnedAddresses:pinnedAddresses
                    addressIndex:addressIndex + 1
                         timeout:timeout
                      completion:completion];
            return;
        }
        completion(data, response, error);
    };

    NSMutableString *path = [url.path mutableCopy] ?: [@"/" mutableCopy];
    if (path.length == 0) [path appendString:@"/"];
    if (url.query.length > 0) [path appendFormat:@"?%@", url.query];
    NSMutableString *wire = [NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: %@\r\nConnection: close\r\n",
                             request.HTTPMethod ?: @"GET", path, url.host];
    for (NSString *field in request.allHTTPHeaderFields) {
        if ([field caseInsensitiveCompare:@"Host"] == NSOrderedSame ||
            [field caseInsensitiveCompare:@"Connection"] == NSOrderedSame) continue;
        [wire appendFormat:@"%@: %@\r\n", field, request.allHTTPHeaderFields[field]];
    }
    NSData *body = request.HTTPBody;
    if (body.length > 0 && ![request valueForHTTPHeaderField:@"Content-Length"]) {
        [wire appendFormat:@"Content-Length: %lu\r\n", (unsigned long)body.length];
    }
    [wire appendString:@"\r\n"];
    NSMutableData *outbound = [[wire dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (body.length > 0) [outbound appendData:body];

    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t nwError) {
        if (state == nw_connection_state_failed) {
            NSError *error = nwError ? (__bridge_transfer NSError *)nw_error_copy_cf_error(nwError) : [self connectionError:@"Pinned connection failed"];
            finish(nil, nil, error);
            return;
        }
        if (state != nw_connection_state_ready) return;
        dispatch_data_t message = dispatch_data_create(outbound.bytes, outbound.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        nw_connection_send(connection, message, _nw_content_context_default_message, true, ^(nw_error_t sendError) {
            if (sendError) {
                finish(nil, nil, (__bridge_transfer NSError *)nw_error_copy_cf_error(sendError));
                return;
            }
            NSMutableData *received = [NSMutableData data];
            __block void (^receiveNext)(void);
            __weak void (^weakReceiveNext)(void);
            receiveNext = ^{
                nw_connection_receive(connection, 1, 64 * 1024, ^(dispatch_data_t content, nw_content_context_t context, bool complete, nw_error_t receiveError) {
                    if (content) {
                        dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
                            [received appendBytes:buffer length:size];
                            return true;
                        });
                    }
                    if (receiveError) {
                        finish(nil, nil, (__bridge_transfer NSError *)nw_error_copy_cf_error(receiveError));
                        return;
                    }
                    if (!complete) {
                        void (^next)(void) = weakReceiveNext;
                        if (next) next();
                        return;
                    }
                    NSRange separator = [received rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding]
                                                       options:0 range:NSMakeRange(0, received.length)];
                    if (separator.location == NSNotFound) {
                        finish(nil, nil, [self connectionError:@"Pinned server returned malformed HTTP"]);
                        return;
                    }
                    NSData *headerData = [received subdataWithRange:NSMakeRange(0, separator.location)];
                    NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSISOLatin1StringEncoding];
                    NSArray<NSString *> *lines = [headerText componentsSeparatedByString:@"\r\n"];
                    NSInteger status = lines.count > 0 ? [[[lines[0] componentsSeparatedByString:@" "] lastObject] integerValue] : 0;
                    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
                    for (NSUInteger i = 1; i < lines.count; i++) {
                        NSRange colon = [lines[i] rangeOfString:@":"];
                        if (colon.location != NSNotFound) {
                            headers[[lines[i] substringToIndex:colon.location]] = [[lines[i] substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                        }
                    }
                    NSData *responseBody = [received subdataWithRange:NSMakeRange(separator.location + separator.length, received.length - separator.location - separator.length)];
                    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:headers];
                    finish(responseBody, response, nil);
                });
            };
            weakReceiveNext = receiveNext;
            receiveNext();
        });
    });
    nw_connection_set_queue(connection, queue);
    nw_connection_start(connection);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), queue, ^{
        if (!finished) finish(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]);
    });
}

@end

@interface ATProtoSafeHTTPClient () <NSURLSessionTaskDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSError *> *redirectErrors;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, ATProtoSafeHTTPClientOptions *> *taskOptions;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *completedTrackingIDs;
@property (nonatomic, assign) NSUInteger nextTrackingID;
@property (nonatomic, strong) NSLock *stateLock;
@property (nonatomic, strong) NSURLSession *sharedSession;
@end

@implementation ATProtoSafeHTTPClient

+ (instancetype)sharedClient {
    static ATProtoSafeHTTPClient *client = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [[ATProtoSafeHTTPClient alloc] init];
    });
    return client;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _redirectErrors = [NSMutableDictionary dictionary];
        _taskOptions = [NSMutableDictionary dictionary];
        _completedTrackingIDs = [NSMutableSet set];
        _nextTrackingID = 0;
        _stateLock = [[NSLock alloc] init];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 60.0;
        config.HTTPShouldSetCookies = NO;
        config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.URLCache = nil;
        config.connectionProxyDictionary = @{};

        _sharedSession = [NSURLSession sessionWithConfiguration:config
                                                       delegate:self
                                                  delegateQueue:nil];
    }
    return self;
}

- (void)dealloc {
    [_sharedSession finishTasksAndInvalidate];
}

+ (NSError *)errorWithCode:(ATProtoSafeHTTPClientErrorCode)code
               description:(NSString *)description
           underlyingError:(NSError *)underlyingError {
    NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey : description ?: @"Safe HTTP request rejected"} mutableCopy];
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:ATProtoSafeHTTPClientErrorDomain code:code userInfo:userInfo];
}

+ (BOOL)validateURL:(NSURL *)url options:(ATProtoSafeHTTPClientOptions *)options error:(NSError **)error {
    ATProtoSafeHTTPClientOptions *effective = options ?: [ATProtoSafeHTTPClientOptions defaultOptions];
    if (!url || url.host.length == 0 || url.scheme.length == 0) {
        if (error) {
            *error = [self errorWithCode:ATProtoSafeHTTPClientErrorInvalidURL
                             description:@"URL must include a scheme and host"
                         underlyingError:nil];
        }
        return NO;
    }

    NSString *host = url.host.lowercaseString;
    BOOL isLoopback = PDSIsLoopbackHost(host);

    if (!isLoopback) {
        NSString *scheme = url.scheme.lowercaseString;
        BOOL allowHTTP = effective.allowHTTP;
        if (!allowHTTP) {
            NSString *envAllow = [[NSProcessInfo processInfo] environment][@"PDS_ALLOW_HTTP"];
            if ([envAllow isEqualToString:@"1"] || [envAllow isEqualToString:@"true"]) {
                allowHTTP = YES;
            }
        }

        BOOL schemeAllowed = [scheme isEqualToString:@"https"] ||
                             (allowHTTP && [scheme isEqualToString:@"http"]);
        if (!schemeAllowed) {
            if (error) {
                *error = [self errorWithCode:ATProtoSafeHTTPClientErrorUnsupportedScheme
                                 description:@"Only HTTPS is allowed for this outbound request"
                             underlyingError:nil];
            }
            return NO;
        }

        BOOL allowPrivate = effective.allowPrivateHosts;
        if (!allowPrivate) {
            NSString *envAllow = [[NSProcessInfo processInfo] environment][@"PDS_ALLOW_PRIVATE_SSRF"];
            if ([envAllow isEqualToString:@"1"] || [envAllow isEqualToString:@"true"]) {
                allowPrivate = YES;
            }
        }

        if (!allowPrivate) {
            NSError *ssrfError = nil;
            if (![SSRFValidator validateHostResolvesToPublicIP:url.host error:&ssrfError]) {
                if (error) {
                    *error = [self errorWithCode:ATProtoSafeHTTPClientErrorSSRFBlocked
                                     description:@"Outbound request target failed SSRF validation"
                                 underlyingError:ssrfError];
                }
                return NO;
            }
        }
    }

    return YES;
}

- (void)performSafeDataTaskWithRequest:(NSURLRequest *)request
                    options:(ATProtoSafeHTTPClientOptions *)options
                 completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    [self performSafeDataTaskWithRequest:request options:options redirectCount:0 completion:completion];
}

- (void)performSafeDataTaskWithRequest:(NSURLRequest *)request
                    options:(ATProtoSafeHTTPClientOptions *)options
                 redirectCount:(NSUInteger)redirectCount
                 completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    if (!completion) {
        return;
    }
    ATProtoSafeHTTPClientOptions *effective = [options copy] ?: [ATProtoSafeHTTPClientOptions defaultOptions];
    NSError *validationError = nil;
    if (![[self class] validateURL:request.URL options:effective error:&validationError]) {
        completion(nil, nil, validationError);
        return;
    }

    if (!PDSIsLoopbackHost(request.URL.host) && !effective.allowPrivateHosts) {
        NSArray<NSString *> *pinnedAddresses = nil;
        NSError *resolutionError = nil;
        if (![SSRFValidator resolvePinnedAddressesForHost:request.URL.host
                                                  timeout:effective.timeout
                                                resolver:nil
                                                addresses:&pinnedAddresses
                                                    error:&resolutionError]) {
            completion(nil, nil, [[self class] errorWithCode:ATProtoSafeHTTPClientErrorSSRFBlocked
                                                  description:@"Outbound request target failed SSRF validation"
                                              underlyingError:resolutionError]);
            return;
        }
        [PDSPinnedHTTPTransport performRequest:request
                               pinnedAddresses:pinnedAddresses
                                       timeout:effective.timeout
                                    completion:^(NSData *data, NSHTTPURLResponse *response, NSError *transportError) {
            if (transportError) {
                completion(nil, response, transportError);
                return;
            }
            if (effective.maxResponseBytes > 0 && data.length > effective.maxResponseBytes) {
                completion(nil, response, [[self class] errorWithCode:ATProtoSafeHTTPClientErrorResponseTooLarge
                                                           description:@"Outbound response exceeded size limit"
                                                       underlyingError:nil]);
                return;
            }
            NSString *location = response.allHeaderFields[@"Location"] ?: response.allHeaderFields[@"location"];
            if (effective.followRedirects && response.statusCode >= 300 && response.statusCode < 400 && location.length > 0) {
                if (redirectCount >= 5) {
                    completion(nil, response, [[self class] errorWithCode:ATProtoSafeHTTPClientErrorRedirectBlocked
                                                               description:@"Too many outbound redirects"
                                                           underlyingError:nil]);
                    return;
                }
                NSURL *target = [[NSURL URLWithString:location relativeToURL:request.URL] absoluteURL];
                NSError *redirectError = nil;
                if (!target || ![[self class] validateURL:target options:effective error:&redirectError]) {
                    completion(nil, response, [[self class] errorWithCode:ATProtoSafeHTTPClientErrorRedirectBlocked
                                                               description:@"Redirect target failed SSRF validation"
                                                           underlyingError:redirectError]);
                    return;
                }
                NSMutableURLRequest *redirectRequest = [request mutableCopy];
                redirectRequest.URL = target;
                [self performSafeDataTaskWithRequest:redirectRequest
                                              options:effective
                                         redirectCount:redirectCount + 1
                                           completion:completion];
                return;
            }
            completion(data, response, nil);
        }];
        return;
    }

    [self.stateLock lock];
    NSNumber *trackingID = @(++_nextTrackingID);
    if (self.completedTrackingIDs.count > 10000) {
        [self.completedTrackingIDs removeAllObjects];
    }
    [self.stateLock unlock];

    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    mutableRequest.timeoutInterval = effective.timeout;

    [self.stateLock lock];
    __block NSURLSessionDataTask *task =
        [self.sharedSession dataTaskWithRequest:mutableRequest
                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [self.stateLock lock];
        NSURLSessionDataTask *capturedTask = task;
        NSNumber *taskID = capturedTask ? @(capturedTask.taskIdentifier) : @0;
        
        BOOL alreadyHandled = [self.completedTrackingIDs containsObject:trackingID];
        if (!alreadyHandled) {
            [self.completedTrackingIDs addObject:trackingID];
        }
        NSError *redirectError = taskID ? self.redirectErrors[taskID] : nil;
        if (taskID) {
            [self.redirectErrors removeObjectForKey:taskID];
            [self.taskOptions removeObjectForKey:taskID];
        }
        [self.stateLock unlock];

        if (alreadyHandled) {
            return;
        }

        if (redirectError) {
            completion(nil, nil, redirectError);
            return;
        }
        if (error) {
            completion(nil, nil, error);
            return;
        }
        if (effective.maxResponseBytes > 0 && data.length > effective.maxResponseBytes) {
            NSError *sizeError = [[self class] errorWithCode:ATProtoSafeHTTPClientErrorResponseTooLarge
                                                  description:@"Outbound response exceeded size limit"
                                              underlyingError:nil];
            completion(nil, (NSHTTPURLResponse *)response, sizeError);
            return;
        }
        completion(data, (NSHTTPURLResponse *)response, nil);
    }];

    NSNumber *taskID = @(task.taskIdentifier);
    self.taskOptions[taskID] = effective;
    [self.stateLock unlock];

    [task resume];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(effective.timeout * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.stateLock lock];
        BOOL alreadyHandled = [self.completedTrackingIDs containsObject:trackingID];
        if (!alreadyHandled) {
            [self.completedTrackingIDs addObject:trackingID];
            [self.redirectErrors removeObjectForKey:taskID];
            [self.taskOptions removeObjectForKey:taskID];
        }
        [self.stateLock unlock];

        if (alreadyHandled) {
            return;
        }

        [task cancel];
        NSError *timeoutError = [NSError errorWithDomain:NSURLErrorDomain
                                                    code:NSURLErrorTimedOut
                                                userInfo:@{NSLocalizedDescriptionKey: @"Safe HTTP request timed out"}];
        completion(nil, nil, timeoutError);
    });
}

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(ATProtoSafeHTTPClientOptions *)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSData *resultData = nil;
    __block NSHTTPURLResponse *resultResponse = nil;
    __block NSError *resultError = nil;

    [self performSafeDataTaskWithRequest:request options:options completion:^(NSData *data, NSHTTPURLResponse *httpResponse, NSError *requestError) {
        resultData = data;
        resultResponse = httpResponse;
        resultError = requestError;
        dispatch_semaphore_signal(sema);
    }];

    NSTimeInterval timeout = (options ?: [ATProtoSafeHTTPClientOptions defaultOptions]).timeout + 1.0;
    if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
        resultError = [NSError errorWithDomain:NSURLErrorDomain
                                          code:NSURLErrorTimedOut
                                      userInfo:@{NSLocalizedDescriptionKey : @"Safe HTTP request timed out"}];
    }

    if (response) {
        *response = resultResponse;
    }
    if (error && resultError) {
        *error = resultError;
    }
    return resultError ? nil : resultData;
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    NSNumber *taskID = @(task.taskIdentifier);
    ATProtoSafeHTTPClientOptions *options = nil;
    [self.stateLock lock];
    options = self.taskOptions[taskID];
    [self.stateLock unlock];

    if (!options.followRedirects) {
        completionHandler(nil);
        return;
    }

    NSError *validationError = nil;
    if (![[self class] validateURL:request.URL options:options error:&validationError]) {
        NSError *redirectError = [[self class] errorWithCode:ATProtoSafeHTTPClientErrorRedirectBlocked
                                                 description:@"Redirect target failed SSRF validation"
                                             underlyingError:validationError];
        [self.stateLock lock];
        self.redirectErrors[taskID] = redirectError;
        [self.stateLock unlock];
        completionHandler(nil);
        return;
    }

    completionHandler(request);
}

@end

#endif
