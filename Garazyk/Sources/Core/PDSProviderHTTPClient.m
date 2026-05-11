// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSProviderHTTPClient.m

 @abstract Shared HTTP client for outbound provider API calls.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Core/PDSProviderHTTPClient.h"
#import "Network/PDSSafeHTTPClient.h"
#import "Debug/PDSLogger.h"

// Suppress -Wblock-capture-autoreleasing: the error out-parameter captured
// by dispatch_sync in the safe HTTP client is safe because dispatch_sync
// completes before the method returns.
#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

NSString *const PDSProviderHTTPClientErrorDomain = @"com.atproto.pds.providerhttpclient";

@interface PDSProviderHTTPClient ()
@property (nonatomic, strong, readwrite) NSURL *baseURL;
@property (nonatomic, copy, readwrite) NSString *authHeader;
@property (nonatomic, strong) id safeHTTPClient;
@end

@implementation PDSProviderHTTPClient

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

+ (instancetype)new {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithBaseURL:(NSURL *)baseURL authHeader:(NSString *)authHeader {
    self = [super init];
    if (self) {
        _baseURL = baseURL;
        _authHeader = [authHeader copy];
        _timeoutInterval = 30.0;
        _maxRetries = 3;
        _safeHTTPClient = [PDSSafeHTTPClient sharedClient];
    }
    return self;
}

- (instancetype)initWithBaseURL:(NSURL *)baseURL apiKey:(NSString *)apiKey {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", apiKey];
    return [self initWithBaseURL:baseURL authHeader:authHeader];
}

#pragma mark - POST

- (nullable NSDictionary *)postPath:(NSString *)path
                               body:(NSDictionary *)body
                              error:(NSError **)error {
    return [self postPath:path body:body headers:nil error:error];
}

- (nullable NSDictionary *)postPath:(NSString *)path
                               body:(NSDictionary *)body
                            headers:(nullable NSDictionary<NSString *, NSString *> *)extraHeaders
                              error:(NSError **)error {
    NSURL *url = [self.baseURL URLByAppendingPathComponent:path];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:self.authHeader forHTTPHeaderField:@"Authorization"];
    request.timeoutInterval = self.timeoutInterval;

    if (extraHeaders) {
        for (NSString *key in extraHeaders) {
            [request setValue:extraHeaders[key] forHTTPHeaderField:key];
        }
    }

    NSError *jsonError = nil;
    NSData *jsonData = nil;
    @try {
        jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    } @catch (NSException *exception) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        userInfo[NSLocalizedDescriptionKey] = @"Failed to serialize JSON body";
        if (exception.name) userInfo[@"exceptionName"] = exception.name;
        if (exception.reason) userInfo[@"exceptionReason"] = exception.reason;
        if (error) {
            *error = [NSError errorWithDomain:PDSProviderHTTPClientErrorDomain
                                         code:PDSProviderHTTPClientErrorSerializationFailed
                                     userInfo:userInfo];
        }
        return nil;
    }
    if (jsonError || !jsonData) {
        if (error) {
            *error = jsonError ?: [NSError errorWithDomain:PDSProviderHTTPClientErrorDomain
                                                      code:PDSProviderHTTPClientErrorSerializationFailed
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize JSON body"}];
        }
        return nil;
    }
    request.HTTPBody = jsonData;

    return [self executeRequestWithRetry:request error:error];
}

#pragma mark - Form POST

- (nullable NSDictionary *)postFormPath:(NSString *)path
                                 params:(NSDictionary *)params
                                  error:(NSError **)error {
    NSURL *url = [self.baseURL URLByAppendingPathComponent:path];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:self.authHeader forHTTPHeaderField:@"Authorization"];
    request.timeoutInterval = self.timeoutInterval;

    // URL-encode parameters
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [params enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSString class]]) {
            NSString *encodedKey = [self urlEncode:key];
            NSString *encodedValue = [self urlEncode:obj];
            [parts addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
        }
    }];
    NSString *formBody = [parts componentsJoinedByString:@"&"];
    request.HTTPBody = [formBody dataUsingEncoding:NSUTF8StringEncoding];

    return [self executeRequestWithRetry:request error:error];
}

- (NSString *)urlEncode:(NSString *)string {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

#pragma mark - GET

- (nullable NSDictionary *)getPath:(NSString *)path
                            params:(nullable NSDictionary *)params
                             error:(NSError **)error {
    // Build URL with query parameters
    NSURL *baseURL = [self.baseURL URLByAppendingPathComponent:path];
    if (params.count > 0) {
        NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
        [params enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSString class]]) {
                [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:obj]];
            }
        }];
        NSURLComponents *components = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
        components.queryItems = queryItems;
        baseURL = components.URL;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:baseURL];
    request.HTTPMethod = @"GET";
    [request setValue:self.authHeader forHTTPHeaderField:@"Authorization"];
    request.timeoutInterval = self.timeoutInterval;

    return [self executeRequestWithRetry:request error:error];
}

#pragma mark - Request Execution

- (nullable NSDictionary *)executeRequestWithRetry:(NSURLRequest *)request
                                             error:(NSError **)error {
    __block NSDictionary *result = nil;
    __block NSError *requestError = nil;

    PDS_LOG_HTTP_INFO(@"Provider HTTP request: %@ %@", request.HTTPMethod, request.URL);

    NSUInteger attempt = 0;
    __block BOOL success = NO;

    while (attempt <= self.maxRetries && !success) {
        if (attempt > 0) {
            NSTimeInterval delay = pow(2.0, (double)attempt);
            PDS_LOG_HTTP_INFO(@"Retrying request (attempt %lu) in %.1f seconds...",
                              (unsigned long)attempt, delay);
            [NSThread sleepForTimeInterval:delay];
        }

        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [self.safeHTTPClient performSafeDataTaskWithRequest:request
                                                    options:[PDSSafeHTTPClientOptions defaultOptions]
                                                completion:^(NSData * _Nullable data,
                                                             NSURLResponse * _Nullable response,
                                                             NSError * _Nullable taskError) {
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
                // HTTP error
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
                userInfo[NSLocalizedDescriptionKey] = [NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode];
                userInfo[@"statusCode"] = @(httpResponse.statusCode);

                if (data && data.length > 0) {
                    NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (responseString) {
                        userInfo[@"responseBody"] = responseString;
                    }
                    id errorBody = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([errorBody isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *errorDict = errorBody;
                        if (errorDict[@"message"]) {
                            userInfo[NSLocalizedDescriptionKey] = errorDict[@"message"];
                        }
                        if (errorDict[@"name"]) {
                            userInfo[@"providerErrorName"] = errorDict[@"name"];
                        }
                    }
                }

                requestError = [NSError errorWithDomain:PDSProviderHTTPClientErrorDomain
                                                    code:PDSProviderHTTPClientErrorHTTPError
                                                userInfo:userInfo];
            }

            dispatch_semaphore_signal(semaphore);
        }];

        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

        if (success) {
            break;
        }

        // Check if we should stop retrying
        if (requestError && [requestError.domain isEqualToString:PDSProviderHTTPClientErrorDomain]) {
            if (requestError.code == PDSProviderHTTPClientErrorHTTPError) {
                NSInteger httpStatus = [requestError.userInfo[@"statusCode"] integerValue];
                // Only retry on server errors and rate limits
                if (httpStatus >= 400 && httpStatus < 500 && httpStatus != 429) {
                    break;
                }
            } else {
                // Non-HTTP errors (serialization, etc.) — don't retry
                break;
            }
        }

        attempt++;
    }

    if (!success && attempt > self.maxRetries) {
        if (error && !requestError) {
            *error = [NSError errorWithDomain:PDSProviderHTTPClientErrorDomain
                                          code:PDSProviderHTTPClientErrorMaxRetriesExceeded
                                      userInfo:@{NSLocalizedDescriptionKey: @"Max retries exceeded"}];
        }
    }

    if (error && requestError) {
        *error = requestError;
    }

    return result;
}

@end
