// NSURLSession compatibility implementation for GNUstep
#import "NSURLSessionCompat.h"

#ifdef GNUSTEP

@implementation NSURLSessionConfiguration

+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    return [[NSURLSessionConfiguration alloc] init];
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    return [[NSURLSessionConfiguration alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _timeoutIntervalForRequest = 60.0;
        _timeoutIntervalForResource = 604800.0;
    }
    return self;
}

@end

@interface NSURLSessionDataTask ()
@property (nonatomic, copy) NSURLSessionDataTaskCompletionHandler completionHandler;
@property (nonatomic, strong) NSURLRequest *taskRequest;
@property (nonatomic, strong) NSURLSessionConfiguration *config;
@end

@implementation NSURLSessionTask
- (void)cancel {}
- (void)resume {
    // Subclasses implement
}
@end

@implementation NSURLSessionDataTask {
    NSURLRequest *_originalRequest;
    NSURLResponse *_response;
    NSError *_error;
}

- (NSURLRequest *)originalRequest { return _originalRequest; }
- (NSURLResponse *)response { return _response; }
- (NSError *)error { return _error; }

- (void)resume {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURLResponse *response = nil;
        NSError *error = nil;
        
        NSMutableURLRequest *request = [self.taskRequest mutableCopy];
        if (self.config.timeoutIntervalForRequest > 0) {
            request.timeoutInterval = self.config.timeoutIntervalForRequest;
        }
        
        // Add additional headers from config
        if (self.config.HTTPAdditionalHeaders) {
            for (NSString *key in self.config.HTTPAdditionalHeaders) {
                [request setValue:self.config.HTTPAdditionalHeaders[key] forHTTPHeaderField:key];
            }
        }
        
        NSData *data = [NSURLConnection sendSynchronousRequest:request
                                             returningResponse:&response
                                                         error:&error];
        
        if (self.completionHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.completionHandler(data, response, error);
            });
        }
    });
}

@end

@implementation NSURLSession {
    NSURLSessionConfiguration *_configuration;
}

static NSURLSession *_sharedSession = nil;

+ (NSURLSession *)sharedSession {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedSession = [[NSURLSession alloc] initWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    });
    return _sharedSession;
}

+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    return [[NSURLSession alloc] initWithConfiguration:configuration];
}

- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration ?: [NSURLSessionConfiguration defaultSessionConfiguration];
    }
    return self;
}

- (NSURLSessionConfiguration *)configuration {
    return _configuration;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(NSURLSessionDataTaskCompletionHandler)completionHandler {
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    return [self dataTaskWithRequest:request completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(NSURLSessionDataTaskCompletionHandler)completionHandler {
    NSURLSessionDataTask *task = [[NSURLSessionDataTask alloc] init];
    task.taskRequest = request;
    task.completionHandler = completionHandler;
    task.config = _configuration;
    return task;
}

@end

#endif // GNUSTEP
