// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/ATProtoSafeHTTPClient.h"
#import "PLCSyncClient.h"
#import "Network/HttpRetryPolicy.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "PLC/PLCConstants.h"

NSString * const PLCSyncClientErrorDomain = @"com.atproto.plc.syncclient";

@interface PLCSyncClient ()

@property (nonatomic, copy) NSString *upstreamURL;
@property (nonatomic, strong) HttpRetryPolicy *retryPolicy;

@end

static NSError *PLCSyncParseError(NSString *message) {
    return [NSError errorWithDomain:PLCSyncClientErrorDomain
                               code:PLCSyncClientErrorParseFailure
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Failed to parse PLC export"}];
}

static NSArray<PLCOperation *> *PLCSyncParseSequencedJSONL(NSData *data, NSError **error) {
    NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!jsonStr) {
        if (error) *error = PLCSyncParseError(@"Export response is not UTF-8");
        return nil;
    }

    NSMutableArray<PLCOperation *> *operations = [NSMutableArray array];
    NSArray<NSString *> *lines = [jsonStr componentsSeparatedByString:@"\n"];
    NSInteger previousSeq = -1;
    for (NSString *line in lines) {
        if (line.length == 0) continue;

        NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSError *lineError = nil;
        NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:&lineError];
        if (lineError || ![entry isKindOfClass:[NSDictionary class]]) {
            if (error) *error = PLCSyncParseError(@"Malformed JSONL export line");
            return nil;
        }

        if (![entry[@"type"] isEqualToString:@"sequenced_op"] ||
            ![entry[@"operation"] isKindOfClass:[NSDictionary class]] ||
            ![entry[@"did"] isKindOfClass:[NSString class]] ||
            ![entry[@"cid"] isKindOfClass:[NSString class]] ||
            ![entry[@"createdAt"] isKindOfClass:[NSString class]] ||
            ![entry[@"seq"] respondsToSelector:@selector(longLongValue)]) {
            if (error) *error = PLCSyncParseError(@"Sequenced export line is missing required fields");
            return nil;
        }

        NSInteger seq = [entry[@"seq"] integerValue];
        if (seq <= previousSeq) {
            if (error) *error = PLCSyncParseError(@"Sequenced export line regressed");
            return nil;
        }
        previousSeq = seq;

        NSError *opError = nil;
        PLCOperation *op = [PLCOperation operationFromDictionary:entry[@"operation"] error:&opError];
        if (!op) {
            if (error) *error = opError ?: PLCSyncParseError(@"Invalid operation in export line");
            return nil;
        }
        op.did = entry[@"did"];
        op.cid = entry[@"cid"];
        op.sequence = @(seq);
        op.createdAt = [NSDateFormatter atproto_dateFromString:entry[@"createdAt"]];
        if (!op.createdAt) {
            if (error) *error = PLCSyncParseError(@"Invalid createdAt in export line");
            return nil;
        }
        [operations addObject:op];
    }
    return operations;
}

@implementation PLCSyncClient {
    dispatch_queue_t _syncQueue;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
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

        _retryPolicy = [[HttpRetryPolicy alloc] init];
        _syncQueue = dispatch_queue_create("com.atproto.plc.syncclient", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)fetchOperationsAfterCursor:(NSInteger)cursor
                             count:(NSUInteger)count
                         completion:(void (^)(NSArray<PLCOperation *> * _Nullable, NSInteger, NSError * _Nullable))completion {
    dispatch_async(_syncQueue, ^{
        NSError *error = nil;
        NSArray<PLCOperation *> *ops = [self fetchOperationsAfterCursorSync:cursor count:count error:&error];
        
        NSInteger nextCursor = cursor;
        if (ops.count > 0) {
            PLCOperation *lastOp = ops.lastObject;
            nextCursor = lastOp.sequence.integerValue;
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
            urlString = [NSString stringWithFormat:@"%@/export?count=%lu&after=%@", self.upstreamURL, (unsigned long)count, afterStr];
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
        
        ATProtoSafeHTTPClientOptions *syncOptions = [[ATProtoSafeHTTPClientOptions defaultOptions] copy];
        syncOptions.timeout = self.timeout;
        [[ATProtoSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request options:syncOptions completion:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable networkError) {
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
        
    });
}

- (nullable NSArray<PLCOperation *> *)fetchOperationsAfterCursorSync:(NSInteger)cursor
                                                                count:(NSUInteger)count
                                                               error:(NSError **)error {
    NSString *urlString = [NSString stringWithFormat:@"%@/export?count=%lu&after=%ld",
                           self.upstreamURL,
                           (unsigned long)MIN(count, PLCExportMaxCount),
                           (long)MAX(cursor, 0)];
    
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
    
    ATProtoSafeHTTPClientOptions *syncOptions = [[ATProtoSafeHTTPClientOptions defaultOptions] copy];
    syncOptions.timeout = self.timeout;
    [[ATProtoSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request options:syncOptions completion:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable networkError) {
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
        resultOps = PLCSyncParseSequencedJSONL(data, &parseError);
        resultError = parseError;
        dispatch_semaphore_signal(semaphore);
    }];
    
    
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
    return latestOp.sequence.integerValue;
}

@end
