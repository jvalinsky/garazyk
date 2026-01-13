#import "PLCClient.h"
#import <os/log.h>

NSErrorDomain const PLCClientErrorDomain = @"com.atproto.plc.client";

static os_log_t PLCClientLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.atproto.plc", "client");
    });
    return log;
}

@interface PLCClient ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation PLCClient

- (instancetype)initWithDirectoryURL:(NSString *)directoryURL {
    self = [super init];
    if (self) {
        _directoryURL = [directoryURL copy];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 60.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (BOOL)submitOperation:(PLCOperation *)operation
               forDID:(NSString *)did
                error:(NSError **)error {
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", self.directoryURL, did];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorInvalidResponse
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from DID"}];
        }
        return NO;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *jsonBody = [operation toJSON];
    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:jsonBody options:0 error:&jsonError];
    if (!bodyData) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorInvalidResponse
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize operation to JSON",
                                                NSUnderlyingErrorKey: jsonError}];
        }
        return NO;
    }
    request.HTTPBody = bodyData;

    NSString *jsonString = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
    NSLog(@"[PLCClient] Submitting operation to %@", urlString);
    NSLog(@"[PLCClient] Request body: %@", jsonString);

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *resultError = nil;
    __block NSHTTPURLResponse *resultResponse = nil;
    __block NSData *resultData = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable err) {
        resultError = err;
        resultResponse = (NSHTTPURLResponse *)response;
        resultData = data;

        NSString *responseStr = data.length > 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"(empty)";
        NSLog(@"[PLCClient] Response status: %ld, body: %@", (long)resultResponse.statusCode, responseStr);

        if (!resultError && data.length > 0) {
            NSDictionary *responseJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([responseJson isKindOfClass:[NSDictionary class]] && responseJson[@"message"]) {
                resultError = [NSError errorWithDomain:PLCClientErrorDomain
                                                 code:PLCClientErrorValidationFailed
                                             userInfo:@{NSLocalizedDescriptionKey: responseJson[@"message"] ?: @"Validation failed"}];
            }
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (resultError) {
        if (error) *error = resultError;
        return NO;
    }

    NSInteger statusCode = resultResponse.statusCode;
    if (statusCode == 404) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorDIDNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID not registered"}];
        }
        return NO;
    }

    if (statusCode >= 400) {
        if (error) {
            NSString *message = @"Server error";
            if (resultData.length > 0) {
                NSDictionary *responseJson = [NSJSONSerialization JSONObjectWithData:resultData options:0 error:nil];
                if ([responseJson isKindOfClass:[NSDictionary class]]) {
                    message = responseJson[@"message"] ?: message;
                }
            }
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorServerError
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld: %@", (long)statusCode, message]}];
        }
        return NO;
    }

    return YES;
}

- (nullable NSDictionary *)getDocumentDataForDID:(NSString *)did
                                            error:(NSError **)error {
    NSString *urlString = [NSString stringWithFormat:@"%@/%@/data", self.directoryURL, did];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorInvalidResponse
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from DID"}];
        }
        return nil;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *resultError = nil;
    __block NSHTTPURLResponse *resultResponse = nil;
    __block NSDictionary *resultData = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable err) {
        resultError = err;
        resultResponse = (NSHTTPURLResponse *)response;

        if (!resultError && data.length > 0) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]]) {
                resultData = json;
            } else {
                resultError = [NSError errorWithDomain:PLCClientErrorDomain
                                                 code:PLCClientErrorInvalidResponse
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON response from PLC directory"}];
            }
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (resultError) {
        if (error) *error = resultError;
        return nil;
    }

    if (resultResponse.statusCode == 404) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorDIDNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID not found"}];
        }
        return nil;
    }

    if (resultResponse.statusCode != 200) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorServerError
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)resultResponse.statusCode]}];
        }
        return nil;
    }

    return resultData;
}

- (nullable NSArray<NSDictionary *> *)getAuditLogForDID:(NSString *)did
                                                   error:(NSError **)error {
    NSString *urlString = [NSString stringWithFormat:@"%@/%@/log/audit", self.directoryURL, did];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorInvalidResponse
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from DID"}];
        }
        return nil;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *resultError = nil;
    __block NSHTTPURLResponse *resultResponse = nil;
    __block NSArray *resultData = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable err) {
        resultError = err;
        resultResponse = (NSHTTPURLResponse *)response;

        if (!resultError && data.length > 0) {
            NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSArray class]]) {
                resultData = json;
            } else {
                resultError = [NSError errorWithDomain:PLCClientErrorDomain
                                                 code:PLCClientErrorInvalidResponse
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON response from PLC directory"}];
            }
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (resultError) {
        if (error) *error = resultError;
        return nil;
    }

    if (resultResponse.statusCode != 200) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorServerError
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)resultResponse.statusCode]}];
        }
        return nil;
    }

    return resultData;
}

- (nullable NSString *)resolveHandle:(NSString *)handle
                               error:(NSError **)error {
    NSString *urlString = [NSString stringWithFormat:@"%@/resolve/%@", self.directoryURL, handle];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorInvalidResponse
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL for handle resolution"}];
        }
        return nil;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *resultError = nil;
    __block NSHTTPURLResponse *resultResponse = nil;
    __block NSString *resultDID = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable err) {
        resultError = err;
        resultResponse = (NSHTTPURLResponse *)response;

        if (!resultError && data.length > 0) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]]) {
                NSString *did = json[@"did"];
                if (did) {
                    resultDID = did;
                } else {
                    resultError = [NSError errorWithDomain:PLCClientErrorDomain
                                                     code:PLCClientErrorInvalidResponse
                                                 userInfo:@{NSLocalizedDescriptionKey: @"No DID in response"}];
                }
            } else {
                resultError = [NSError errorWithDomain:PLCClientErrorDomain
                                                 code:PLCClientErrorInvalidResponse
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON response"}];
            }
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (resultError) {
        if (error) *error = resultError;
        return nil;
    }

    if (resultResponse.statusCode == 404) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorDIDNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Handle not found"}];
        }
        return nil;
    }

    if (resultResponse.statusCode != 200) {
        if (error) {
            *error = [NSError errorWithDomain:PLCClientErrorDomain
                                         code:PLCClientErrorServerError
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)resultResponse.statusCode]}];
        }
        return nil;
    }

    return resultDID;
}

@end
