#import "PLCSyncClient.h"
#import "Network/HttpRetryPolicy.h"

NSString * const PLCSyncClientErrorDomain = @"com.atproto.plc.syncclient";

@interface PLCSyncClient () <NSURLSessionTaskDelegate>

@property (nonatomic, copy) NSString *upstreamURL;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) HttpRetryPolicy *retryPolicy;

@end

@implementation PLCSyncClient {
    dispatch_queue_t _syncQueue;
}

- (instancetype)initWithUpstreamURL:(NSString *)url {
    self = [super init];
    if (self) {
        if (!url || url.length == 0) {
            return nil;
        }
        
        if (![url hasPrefix:@"http://"] && ![url hasPrefix:@"https://"]) {
            url = [NSString stringWithFormat:@"https://%@", url];
        }
        
        _upstreamURL = [url copy];
        _timeout = 30.0;
        _maxRetries = 3;
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = _timeout;
        config.timeoutIntervalForResource = _timeout * 2;
        config.waitsForConnectivity = YES;
        
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
        _retryPolicy = [[HttpRetryPolicy alloc] init];
        _syncQueue = dispatch_queue_create("com.atproto.plc.syncclient", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(nil);
}

- (void)fetchOperationsAfterCursor:(NSInteger)cursor
                             count:(NSUInteger)count
                         completion:(void (^)(NSArray<PLCOperation *> * _Nullable, NSInteger, NSError * _Nullable))completion {
    dispatch_async(_syncQueue, ^{
        NSError *error = nil;
        NSArray<PLCOperation *> *ops = [self fetchOperationsAfterCursorSync:cursor count:count error:&error];
        
        NSInteger nextCursor = -1;
        if (ops.count > 0) {
            PLCOperation *lastOp = ops.lastObject;
            if (lastOp.createdAt) {
                nextCursor = (NSInteger)[lastOp.createdAt timeIntervalSince1970];
            }
        }
        
        if (completion) {
            completion(ops, nextCursor, error);
        }
    });
}

- (void)fetchOperationsAfterDate:(nullable NSDate *)afterDate
                           count:(NSUInteger)count
                       completion:(void (^)(NSArray<PLCOperation *> * _Nullable, NSDate * _Nullable, NSError * _Nullable))completion {
    dispatch_async(_syncQueue, ^{
        NSError *error = nil;
        
        NSString *urlString = [NSString stringWithFormat:@"%@/export", self.upstreamURL];
        if (afterDate) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
            NSString *afterStr = [formatter stringFromDate:afterDate];
            urlString = [NSString stringWithFormat:@"%@?count=%lu&after=%@", self.upstreamURL, (unsigned long)count, afterStr];
        } else {
            urlString = [NSString stringWithFormat:@"%@/export?count=%lu", self.upstreamURL, (unsigned long)count];
        }
        
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            if (completion) {
                NSError *err = [NSError errorWithDomain:PLCSyncClientErrorDomain
                                                   code:PLCSyncClientErrorInvalidURL
                                               userInfo:@{NSLocalizedDescriptionKey: @"Invalid export URL"}];
                completion(nil, nil, err);
            }
            return;
        }
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.timeoutInterval = self.timeout;
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        
        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable networkError) {
            if (networkError) {
                if (completion) {
                    NSError *err = [NSError errorWithDomain:PLCSyncClientErrorDomain
                                                       code:PLCSyncClientErrorNetworkFailure
                                                   userInfo:@{NSLocalizedDescriptionKey: networkError.localizedDescription}];
                    completion(nil, nil, err);
                }
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode != 200) {
                if (completion) {
                    NSError *err = [NSError errorWithDomain:PLCSyncClientErrorDomain
                                                       code:PLCSyncClientErrorNetworkFailure
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]}];
                    completion(nil, nil, err);
                }
                return;
            }
            
            if (!data || data.length == 0) {
                if (completion) {
                    completion(@[], nil, nil);
                }
                return;
            }
            
            NSError *parseError = nil;
            NSMutableArray<PLCOperation *> *operations = [NSMutableArray array];
            NSDate *lastDate = nil;
            
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSArray *lines = [jsonStr componentsSeparatedByString:@"\n"];
            
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
            
            for (NSString *line in lines) {
                if (line.length == 0) continue;
                
                NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:&parseError];
                if (parseError || ![entry isKindOfClass:[NSDictionary class]]) continue;
                
                NSDictionary *opDict = entry[@"operation"];
                if (!opDict) continue;
                
                PLCOperation *op = [PLCOperation operationFromDictionary:opDict error:&parseError];
                if (!op) continue;
                
                op.did = entry[@"did"];
                op.cid = entry[@"cid"];
                op.nullified = [entry[@"nullified"] boolValue];
                
                NSString *createdAtStr = entry[@"createdAt"];
                if (createdAtStr) {
                    op.createdAt = [formatter dateFromString:createdAtStr];
                    if (op.createdAt && (!lastDate || [op.createdAt compare:lastDate] == NSOrderedDescending)) {
                        lastDate = op.createdAt;
                    }
                }
                
                [operations addObject:op];
            }
            
            if (completion) {
                completion(operations, lastDate, nil);
            }
        }];
        
        [task resume];
    });
}

- (nullable NSArray<PLCOperation *> *)fetchOperationsAfterCursorSync:(NSInteger)cursor
                                                                count:(NSUInteger)count
                                                               error:(NSError **)error {
    NSString *urlString;
    if (cursor > 0) {
        NSDate *afterDate = [NSDate dateWithTimeIntervalSince1970:cursor];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
        NSString *afterStr = [formatter stringFromDate:afterDate];
        urlString = [NSString stringWithFormat:@"%@/export?count=%lu&after=%@", self.upstreamURL, (unsigned long)count, afterStr];
    } else {
        urlString = [NSString stringWithFormat:@"%@/export?count=%lu", self.upstreamURL, (unsigned long)count];
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:PLCSyncClientErrorDomain
                                         code:PLCSyncClientErrorInvalidURL
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid export URL"}];
        }
        return nil;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = self.timeout;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block NSArray<PLCOperation *> *resultOps = nil;
    __block NSError *resultError = nil;
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable networkError) {
        if (networkError) {
            resultError = [NSError errorWithDomain:PLCSyncClientErrorDomain
                                              code:PLCSyncClientErrorNetworkFailure
                                          userInfo:@{NSLocalizedDescriptionKey: networkError.localizedDescription}];
            dispatch_semaphore_signal(semaphore);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            resultError = [NSError errorWithDomain:PLCSyncClientErrorDomain
                                              code:PLCSyncClientErrorNetworkFailure
                                          userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]}];
            dispatch_semaphore_signal(semaphore);
            return;
        }
        
        if (!data || data.length == 0) {
            resultOps = @[];
            dispatch_semaphore_signal(semaphore);
            return;
        }
        
        NSError *parseError = nil;
        NSMutableArray<PLCOperation *> *operations = [NSMutableArray array];
        
        NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSArray *lines = [jsonStr componentsSeparatedByString:@"\n"];
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
        
        for (NSString *line in lines) {
            if (line.length == 0) continue;
            
            NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:&parseError];
            if (parseError || ![entry isKindOfClass:[NSDictionary class]]) continue;
            
            NSDictionary *opDict = entry[@"operation"];
            if (!opDict) continue;
            
            PLCOperation *op = [PLCOperation operationFromDictionary:opDict error:&parseError];
            if (!op) continue;
            
            op.did = entry[@"did"];
            op.cid = entry[@"cid"];
            op.nullified = [entry[@"nullified"] boolValue];
            
            NSString *createdAtStr = entry[@"createdAt"];
            if (createdAtStr) {
                op.createdAt = [formatter dateFromString:createdAtStr];
            }
            
            [operations addObject:op];
        }
        
        resultOps = operations;
        dispatch_semaphore_signal(semaphore);
    }];
    
    [task resume];
    
    dispatch_time_t waitTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.timeout * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(semaphore, waitTime) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCSyncClientErrorDomain
                                         code:PLCSyncClientErrorNetworkFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timed out"}];
        }
        return nil;
    }
    
    if (resultError) {
        if (error) *error = resultError;
        return nil;
    }
    
    return resultOps;
}

- (NSInteger)getLatestCursorWithError:(NSError **)error {
    NSArray<PLCOperation *> *ops = [self fetchOperationsAfterCursorSync:0 count:1 error:error];
    if (!ops || ops.count == 0) {
        return 0;
    }
    
    PLCOperation *latestOp = ops.firstObject;
    if (latestOp.createdAt) {
        return (NSInteger)[latestOp.createdAt timeIntervalSince1970];
    }
    
    return 0;
}

@end