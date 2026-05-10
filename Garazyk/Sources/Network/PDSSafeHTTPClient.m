#import "Network/PDSSafeHTTPClient.h"
#import "Network/SSRFValidator.h"

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

NSErrorDomain const PDSSafeHTTPClientErrorDomain = @"com.atproto.safe-http";

@implementation PDSSafeHTTPClientOptions

+ (instancetype)defaultOptions {
    PDSSafeHTTPClientOptions *options = [[PDSSafeHTTPClientOptions alloc] init];
    options.timeout = 10.0;
    options.maxResponseBytes = 1024 * 1024;
    options.allowHTTP = NO;
    options.allowPrivateHosts = NO;
    options.followRedirects = YES;
    return options;
}

- (id)copyWithZone:(NSZone *)zone {
    PDSSafeHTTPClientOptions *copy = [[[self class] allocWithZone:zone] init];
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

@interface PDSSafeHTTPClient ()
@property (nonatomic, strong) NSLock *stateLock;
@end

@implementation PDSSafeHTTPClient

+ (instancetype)sharedClient {
    static PDSSafeHTTPClient *client = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [[PDSSafeHTTPClient alloc] init];
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

+ (NSError *)errorWithCode:(PDSSafeHTTPClientErrorCode)code
               description:(NSString *)description
           underlyingError:(NSError *)underlyingError {
    NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey : description ?: @"Safe HTTP request rejected"} mutableCopy];
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:PDSSafeHTTPClientErrorDomain code:code userInfo:userInfo];
}

+ (BOOL)validateURL:(NSURL *)url options:(PDSSafeHTTPClientOptions *)options error:(NSError **)error {
    PDSSafeHTTPClientOptions *effective = options ?: [PDSSafeHTTPClientOptions defaultOptions];
    if (!url || url.host.length == 0 || url.scheme.length == 0) {
        if (error) {
            *error = [self errorWithCode:PDSSafeHTTPClientErrorInvalidURL
                             description:@"URL must include a scheme and host"
                         underlyingError:nil];
        }
        return NO;
    }

    NSString *host = url.host.lowercaseString;
    BOOL isLoopback = [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"] || [host isEqualToString:@"::1"];

    if (!isLoopback) {
        NSString *scheme = url.scheme.lowercaseString;
        BOOL schemeAllowed = [scheme isEqualToString:@"https"] ||
                             (effective.allowHTTP && [scheme isEqualToString:@"http"]);
        if (!schemeAllowed) {
            if (error) {
                *error = [self errorWithCode:PDSSafeHTTPClientErrorUnsupportedScheme
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
                    *error = [self errorWithCode:PDSSafeHTTPClientErrorSSRFBlocked
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
                    options:(PDSSafeHTTPClientOptions *)options
                 completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    if (!completion) {
        return;
    }
    PDSSafeHTTPClientOptions *effective = [options copy] ?: [PDSSafeHTTPClientOptions defaultOptions];
    NSError *validationError = nil;
    if (![[self class] validateURL:request.URL options:effective error:&validationError]) {
        completion(nil, nil, validationError);
        return;
    }

    NSURL *url = [request.URL absoluteURL];
    NSString *urlString = [url absoluteString];
    NSTimeInterval timeout = effective.timeout;
    NSUInteger maxBytes = effective.maxResponseBytes;
    NSData *postBody = request.HTTPBody;
    NSString *method = request.HTTPMethod ?: @"GET";
    NSDictionary *requestHeaders = request.allHTTPHeaderFields;
    BOOL followRedirects = effective.followRedirects;
    PDSSafeHTTPClientOptions *opts = effective;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        CURL *curl = curl_easy_init();
        CURLM *multi = curl_multi_init();
        if (!curl || !multi) {
            if (curl) curl_easy_cleanup(curl);
            if (multi) curl_multi_cleanup(multi);
            NSError *err = [NSError errorWithDomain:PDSSafeHTTPClientErrorDomain
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

        if (followRedirects) {
            curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
            curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 5L);
        } else {
            curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
        }

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
                    redirectBlockError = [[self class] errorWithCode:PDSSafeHTTPClientErrorRedirectBlocked
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

        if (res != CURLE_OK) {
            if (writeCtx.exceededLimit) {
                NSError *sizeError = [[self class] errorWithCode:PDSSafeHTTPClientErrorResponseTooLarge
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
                           options:(PDSSafeHTTPClientOptions *)options
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

    NSTimeInterval timeout = (options ?: [PDSSafeHTTPClientOptions defaultOptions]).timeout + 1.0;
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

#else // Apple platforms — use NSURLSession

@interface PDSSafeHTTPClient () <NSURLSessionTaskDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSError *> *redirectErrors;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, PDSSafeHTTPClientOptions *> *taskOptions;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *completedTrackingIDs;
@property (nonatomic, assign) NSUInteger nextTrackingID;
@property (nonatomic, strong) NSLock *stateLock;
@property (nonatomic, strong) NSURLSession *sharedSession;
@end

@implementation PDSSafeHTTPClient

+ (instancetype)sharedClient {
    static PDSSafeHTTPClient *client = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [[PDSSafeHTTPClient alloc] init];
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

+ (NSError *)errorWithCode:(PDSSafeHTTPClientErrorCode)code
               description:(NSString *)description
           underlyingError:(NSError *)underlyingError {
    NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey : description ?: @"Safe HTTP request rejected"} mutableCopy];
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:PDSSafeHTTPClientErrorDomain code:code userInfo:userInfo];
}

+ (BOOL)validateURL:(NSURL *)url options:(PDSSafeHTTPClientOptions *)options error:(NSError **)error {
    PDSSafeHTTPClientOptions *effective = options ?: [PDSSafeHTTPClientOptions defaultOptions];
    if (!url || url.host.length == 0 || url.scheme.length == 0) {
        if (error) {
            *error = [self errorWithCode:PDSSafeHTTPClientErrorInvalidURL
                             description:@"URL must include a scheme and host"
                         underlyingError:nil];
        }
        return NO;
    }

    NSString *host = url.host.lowercaseString;
    BOOL isLoopback = [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"] || [host isEqualToString:@"::1"];

    if (!isLoopback) {
        NSString *scheme = url.scheme.lowercaseString;
        BOOL schemeAllowed = [scheme isEqualToString:@"https"] ||
                             (effective.allowHTTP && [scheme isEqualToString:@"http"]);
        if (!schemeAllowed) {
            if (error) {
                *error = [self errorWithCode:PDSSafeHTTPClientErrorUnsupportedScheme
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
                    *error = [self errorWithCode:PDSSafeHTTPClientErrorSSRFBlocked
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
                    options:(PDSSafeHTTPClientOptions *)options
                 completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    if (!completion) {
        return;
    }
    PDSSafeHTTPClientOptions *effective = [options copy] ?: [PDSSafeHTTPClientOptions defaultOptions];
    NSError *validationError = nil;
    if (![[self class] validateURL:request.URL options:effective error:&validationError]) {
        completion(nil, nil, validationError);
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

    __block NSURLSessionDataTask *task =
        [self.sharedSession dataTaskWithRequest:mutableRequest
                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSNumber *taskID = @(task.taskIdentifier);
        [self.stateLock lock];
        BOOL alreadyHandled = [self.completedTrackingIDs containsObject:trackingID];
        if (!alreadyHandled) {
            [self.completedTrackingIDs addObject:trackingID];
        }
        NSError *redirectError = self.redirectErrors[taskID];
        [self.redirectErrors removeObjectForKey:taskID];
        [self.taskOptions removeObjectForKey:taskID];
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
            NSError *sizeError = [[self class] errorWithCode:PDSSafeHTTPClientErrorResponseTooLarge
                                                  description:@"Outbound response exceeded size limit"
                                              underlyingError:nil];
            completion(nil, (NSHTTPURLResponse *)response, sizeError);
            return;
        }
        completion(data, (NSHTTPURLResponse *)response, nil);
    }];

    NSNumber *taskID = @(task.taskIdentifier);
    [self.stateLock lock];
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
                           options:(PDSSafeHTTPClientOptions *)options
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

    NSTimeInterval timeout = (options ?: [PDSSafeHTTPClientOptions defaultOptions]).timeout + 1.0;
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
    PDSSafeHTTPClientOptions *options = nil;
    [self.stateLock lock];
    options = self.taskOptions[taskID];
    [self.stateLock unlock];

    if (!options.followRedirects) {
        completionHandler(nil);
        return;
    }

    NSError *validationError = nil;
    if (![[self class] validateURL:request.URL options:options error:&validationError]) {
        NSError *redirectError = [[self class] errorWithCode:PDSSafeHTTPClientErrorRedirectBlocked
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
