#import "Network/PDSSafeHTTPClient.h"
#import "Network/SSRFValidator.h"

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

@interface PDSSafeHTTPClient () <NSURLSessionTaskDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSError *> *redirectErrors;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, PDSSafeHTTPClientOptions *> *taskOptions;
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
        _redirectErrors = [NSMutableDictionary dictionary];
        _taskOptions = [NSMutableDictionary dictionary];
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

    if (!effective.allowPrivateHosts) {
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

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = effective.timeout;
    configuration.timeoutIntervalForResource = effective.timeout;
    configuration.HTTPShouldSetCookies = NO;
    configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration
                                                          delegate:self
                                                     delegateQueue:nil];
    NSURLSessionDataTask *task =
        [session performSafeDataTaskWithRequest:request
                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSNumber *taskID = @(task.taskIdentifier);
        NSError *redirectError = nil;
        [self.stateLock lock];
        redirectError = self.redirectErrors[taskID];
        [self.redirectErrors removeObjectForKey:taskID];
        [self.taskOptions removeObjectForKey:taskID];
        [self.stateLock unlock];

        [session finishTasksAndInvalidate];

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

    [self.stateLock lock];
    self.taskOptions[@(task.taskIdentifier)] = effective;
    [self.stateLock unlock];

    [task resume];
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
