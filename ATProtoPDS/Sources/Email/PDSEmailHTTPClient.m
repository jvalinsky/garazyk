#import "PDSEmailHTTPClient.h"
#import "Debug/PDSLogger.h"

@interface PDSEmailHTTPClient ()
@property (nonatomic, strong, readwrite) NSURL *baseURL;
@property (nonatomic, strong, readwrite) NSString *apiKey;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation PDSEmailHTTPClient

- (instancetype)initWithBaseURL:(NSURL *)baseURL apiKey:(NSString *)apiKey {
    self = [super init];
    if (self) {
        _baseURL = baseURL;
        _apiKey = apiKey;
        _timeoutInterval = 30.0;
        _maxRetries = 3;
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (nullable NSDictionary *)postPath:(NSString *)path
                               body:(NSDictionary *)body
                              error:(NSError * _Nullable *)error {
    NSURL *url = [self.baseURL URLByAppendingPathComponent:path];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"];
    request.timeoutInterval = self.timeoutInterval;
    
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (jsonError) {
        if (error) *error = jsonError;
        PDS_LOG_HTTP_ERROR(@"Failed to serialize JSON body: %@", jsonError);
        return nil;
    }
    request.HTTPBody = jsonData;
    
    __block NSDictionary *result = nil;
    __block NSError *requestError = nil;
    
    // Log the request (sanitized)
    PDS_LOG_HTTP_INFO(@"Sending email request to: %@", url);
    
    NSUInteger attempt = 0;
    __block BOOL success = NO;
    
    while (attempt <= self.maxRetries && !success) {
        if (attempt > 0) {
            NSTimeInterval delay = pow(2.0, attempt);
            PDS_LOG_HTTP_INFO(@"Retrying request (attempt %lu) in %.1f seconds...", (unsigned long)attempt, delay);
            [NSThread sleepForTimeInterval:delay];
        }
        
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable taskError) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            
            if (taskError) {
                requestError = taskError;
            } else if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
                NSError *parseError = nil;
                if (data && data.length > 0) {
                    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
                    if ([jsonObject isKindOfClass:[NSDictionary class]]) {
                        result = jsonObject;
                    }
                }
                if (!parseError) {
                    success = YES;
                    requestError = nil;
                } else {
                    requestError = parseError;
                }
            } else {
                // Handle HTTP errors
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
                userInfo[NSLocalizedDescriptionKey] = [NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode];
                userInfo[@"statusCode"] = @(httpResponse.statusCode);
                
                if (data && data.length > 0) {
                    NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (responseString) {
                        userInfo[@"responseBody"] = responseString;
                    }
                }
                
                requestError = [NSError errorWithDomain:@"PDSEmailHTTPClientErrorDomain"
                                                   code:httpResponse.statusCode
                                               userInfo:userInfo];
                
                // Determine if we should retry
                BOOL shouldRetry = NO;
                if (httpResponse.statusCode >= 500) {
                    shouldRetry = YES; // Server errors
                } else if (httpResponse.statusCode == 429) {
                    shouldRetry = YES; // Rate limit
                }
                
                // If we shouldn't retry, we need to signal that to the outer loop
                // We do this by checking the error code in the outer loop
            }
            
            dispatch_semaphore_signal(semaphore);
        }];
        
        [task resume];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        if (success) {
            break;
        }
        
        // Check if we should stop retrying based on the error code
        if (requestError && [requestError.domain isEqualToString:@"PDSEmailHTTPClientErrorDomain"]) {
            NSInteger code = requestError.code;
            if (code >= 400 && code < 500 && code != 429) {
                PDS_LOG_HTTP_ERROR(@"Client error (%ld), not retrying: %@", (long)code, requestError);
                break;
            }
        }
        
        attempt++;
    }
    
    if (error && requestError) {
        *error = requestError;
    }
    
    return result;
}

@end
