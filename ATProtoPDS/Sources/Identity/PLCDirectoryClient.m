#import "Identity/PLCDirectoryClient.h"
#import <os/log.h>

NSErrorDomain const PLCDirectoryErrorDomain = @"com.atproto.plc.directory";

@interface PLCDirectoryClient ()

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) os_log_t log;

@end

@implementation PLCDirectoryClient

- (instancetype)init {
    return [self initWithBaseURL:@"https://plc.directory"];
}

- (instancetype)initWithBaseURL:(NSString *)baseURL {
    self = [super init];
    if (self) {
        _baseURL = [baseURL copy];
        _timeoutInterval = 30.0;
        _log = os_log_create("com.atproto.plc", "directory");
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = _timeoutInterval;
        config.timeoutIntervalForResource = _timeoutInterval * 2;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - Operations

- (void)submitOperation:(NSDictionary *)operation
                 forDID:(NSString *)did
             completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    
    // Build URL: POST /<did>
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", self.baseURL, did];
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                 code:PLCDirectoryErrorInvalidResponse
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
            completion(NO, error);
        }
        return;
    }
    
    // Serialize operation to JSON
    NSError *jsonError;
    NSData *body = [NSJSONSerialization dataWithJSONObject:operation options:0 error:&jsonError];
    if (!body) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                 code:PLCDirectoryErrorInvalidResponse
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize operation",
                                                       NSUnderlyingErrorKey: jsonError}];
            completion(NO, error);
        }
        return;
    }
    
    // Create request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    os_log_info(self.log, "Submitting PLC operation for DID: %{public}@", did);
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData * _Nullable data,
                                                                     NSURLResponse * _Nullable response,
                                                                     NSError * _Nullable networkError) {
        if (networkError) {
            os_log_error(self.log, "Network error submitting PLC operation: %{public}@", networkError.localizedDescription);
            if (completion) {
                NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                     code:PLCDirectoryErrorNetworkError
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Network error",
                                                           NSUnderlyingErrorKey: networkError}];
                completion(NO, error);
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSInteger statusCode = httpResponse.statusCode;
        
        if (statusCode >= 200 && statusCode < 300) {
            os_log_info(self.log, "Successfully submitted PLC operation for DID: %{public}@", did);
            if (completion) {
                completion(YES, nil);
            }
            return;
        }
        
        // Handle error responses
        NSString *errorMessage = @"Unknown error";
        if (data) {
            NSDictionary *errorBody = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (errorBody[@"message"]) {
                errorMessage = errorBody[@"message"];
            } else if (errorBody[@"error"]) {
                errorMessage = errorBody[@"error"];
            }
        }
        
        os_log_error(self.log, "PLC directory rejected operation: HTTP %ld - %{public}@", 
                     (long)statusCode, errorMessage);
        
        PLCDirectoryErrorCode errorCode;
        if (statusCode == 409) {
            errorCode = PLCDirectoryErrorConflict;
        } else if (statusCode == 404) {
            errorCode = PLCDirectoryErrorDIDNotFound;
        } else if (statusCode >= 400 && statusCode < 500) {
            errorCode = PLCDirectoryErrorOperationRejected;
        } else {
            errorCode = PLCDirectoryErrorInvalidResponse;
        }
        
        if (completion) {
            NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                 code:errorCode
                                             userInfo:@{NSLocalizedDescriptionKey: errorMessage,
                                                       @"HTTPStatusCode": @(statusCode)}];
            completion(NO, error);
        }
    }];
    
    [task resume];
}

- (BOOL)submitOperationSync:(NSDictionary *)operation
                     forDID:(NSString *)did
                      error:(NSError **)error {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL success = NO;
    __block NSError *resultError = nil;
    
    [self submitOperation:operation forDID:did completion:^(BOOL succeeded, NSError * _Nullable err) {
        success = succeeded;
        resultError = err;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.timeoutInterval * 2 * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(semaphore, timeout) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                         code:PLCDirectoryErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timed out"}];
        }
        return NO;
    }
    
    if (error) {
        *error = resultError;
    }
    return success;
}

#pragma mark - Queries

- (void)getOperationLog:(NSString *)did
             completion:(void (^)(NSArray<NSDictionary *> * _Nullable operations, NSError * _Nullable error))completion {
    
    // Build URL: GET /<did>/log/audit
    NSString *urlString = [NSString stringWithFormat:@"%@/%@/log/audit", self.baseURL, did];
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                 code:PLCDirectoryErrorInvalidResponse
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
            completion(nil, error);
        }
        return;
    }
    
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData * _Nullable data,
                                                                 NSURLResponse * _Nullable response,
                                                                 NSError * _Nullable networkError) {
        if (networkError) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                     code:PLCDirectoryErrorNetworkError
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Network error",
                                                           NSUnderlyingErrorKey: networkError}];
                completion(nil, error);
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode == 404) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                     code:PLCDirectoryErrorDIDNotFound
                                                 userInfo:@{NSLocalizedDescriptionKey: @"DID not found"}];
                completion(nil, error);
            }
            return;
        }
        
        if (httpResponse.statusCode != 200 || !data) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                     code:PLCDirectoryErrorInvalidResponse
                                                 userInfo:@{NSLocalizedDescriptionKey: 
                                                     [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]}];
                completion(nil, error);
            }
            return;
        }
        
        NSError *jsonError;
        NSArray *operations = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (!operations || ![operations isKindOfClass:[NSArray class]]) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                     code:PLCDirectoryErrorInvalidResponse
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON response",
                                                           NSUnderlyingErrorKey: jsonError ?: [NSNull null]}];
                completion(nil, error);
            }
            return;
        }
        
        if (completion) {
            completion(operations, nil);
        }
    }];
    
    [task resume];
}

- (nullable NSArray<NSDictionary *> *)getOperationLogSync:(NSString *)did
                                                    error:(NSError **)error {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSArray *resultOperations = nil;
    __block NSError *resultError = nil;
    
    [self getOperationLog:did completion:^(NSArray<NSDictionary *> * _Nullable operations, NSError * _Nullable err) {
        resultOperations = operations;
        resultError = err;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.timeoutInterval * 2 * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(semaphore, timeout) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                         code:PLCDirectoryErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timed out"}];
        }
        return nil;
    }
    
    if (error) {
        *error = resultError;
    }
    return resultOperations;
}

- (void)resolveDID:(NSString *)did
        completion:(void (^)(NSDictionary * _Nullable document, NSError * _Nullable error))completion {
    
    // Build URL: GET /<did>
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", self.baseURL, did];
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                 code:PLCDirectoryErrorInvalidResponse
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
            completion(nil, error);
        }
        return;
    }
    
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData * _Nullable data,
                                                                 NSURLResponse * _Nullable response,
                                                                 NSError * _Nullable networkError) {
        if (networkError) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                     code:PLCDirectoryErrorNetworkError
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Network error",
                                                           NSUnderlyingErrorKey: networkError}];
                completion(nil, error);
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode == 404) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                     code:PLCDirectoryErrorDIDNotFound
                                                 userInfo:@{NSLocalizedDescriptionKey: @"DID not found"}];
                completion(nil, error);
            }
            return;
        }
        
        if (httpResponse.statusCode != 200 || !data) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                     code:PLCDirectoryErrorInvalidResponse
                                                 userInfo:@{NSLocalizedDescriptionKey: 
                                                     [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]}];
                completion(nil, error);
            }
            return;
        }
        
        NSError *jsonError;
        NSDictionary *document = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (!document || ![document isKindOfClass:[NSDictionary class]]) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                                     code:PLCDirectoryErrorInvalidResponse
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON response",
                                                           NSUnderlyingErrorKey: jsonError ?: [NSNull null]}];
                completion(nil, error);
            }
            return;
        }
        
        if (completion) {
            completion(document, nil);
        }
    }];
    
    [task resume];
}

- (nullable NSDictionary *)resolveDIDSync:(NSString *)did
                                    error:(NSError **)error {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSDictionary *resultDocument = nil;
    __block NSError *resultError = nil;
    
    [self resolveDID:did completion:^(NSDictionary * _Nullable document, NSError * _Nullable err) {
        resultDocument = document;
        resultError = err;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.timeoutInterval * 2 * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(semaphore, timeout) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCDirectoryErrorDomain
                                         code:PLCDirectoryErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timed out"}];
        }
        return nil;
    }
    
    if (error) {
        *error = resultError;
    }
    return resultDocument;
}

- (void)checkDIDExists:(NSString *)did
            completion:(void (^)(BOOL exists, NSError * _Nullable error))completion {
    [self resolveDID:did completion:^(NSDictionary * _Nullable document, NSError * _Nullable error) {
        if (error) {
            if (error.code == PLCDirectoryErrorDIDNotFound) {
                completion(NO, nil);
            } else {
                completion(NO, error);
            }
        } else {
            completion(document != nil, nil);
        }
    }];
}

@end
