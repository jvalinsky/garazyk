#import "DIDPLCResolver.h"
#import "PLCOperation.h"
#import "Network/HttpRetryPolicy.h"

NSString * const DIDPLCResolverErrorDomain = @"com.atproto.plc.resolver";
static NSString *const kDIDAcceptHeader = @"application/did+ld+json,application/json";

@interface DIDPLCResolver () <NSURLSessionTaskDelegate>

@property (nonatomic, copy) NSString *plcUrl;
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *cache;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) HttpRetryPolicy *retryPolicy;

@end

@implementation DIDPLCResolver

- (instancetype)initWithPlcUrl:(NSString *)url {
    self = [super init];
    if (self) {
        _plcUrl = [url copy];
        _timeout = 5.0;
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 1000;
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = _timeout;
        config.timeoutIntervalForResource = _timeout * 2;
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
        _retryPolicy = [[HttpRetryPolicy alloc] init];
    }
    return self;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(nil);
}

- (nullable NSDictionary *)resolveDID:(NSString *)did error:(NSError **)error {
    if (![PLCOperation isValidDidPlc:did]) {
        if (error) {
            *error = [NSError errorWithDomain:DIDPLCResolverErrorDomain
                                         code:DIDPLCResolverErrorInvalidDID
                                     userInfo:@{NSLocalizedDescriptionKey: @"Provided DID fails strictly length and character validation"}];
        }
        return nil;
    }
    
    NSDictionary *cached = [self.cache objectForKey:did];
    if (cached) {
        return cached;
    }
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSDictionary *resolvedDoc = nil;
    __block NSError *resolveError = nil;
    
    [self resolveDID:did completion:^(NSDictionary *doc, NSError *err) {
        resolvedDoc = doc;
        resolveError = err;
        dispatch_semaphore_signal(semaphore);
    }];
    
    // Wait for resolution with safety margin. The underlying task has its own configured timeout.
    dispatch_time_t waitTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)((self.timeout + 1.0) * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(semaphore, waitTime) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:DIDPLCResolverErrorDomain
                                         code:DIDPLCResolverErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Synchronous DID resolution timed out"}];
        }
        return nil;
    }
    
    if (resolveError) {
        if (error) *error = resolveError;
        return nil;
    }
    
    return resolvedDoc;
}

- (void)resolveDID:(NSString *)did completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    if (!completion) return;
    
    if (![PLCOperation isValidDidPlc:did]) {
        NSError *err = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidDID userInfo:@{NSLocalizedDescriptionKey: @"Provided DID fails strictly length and character validation"}];
        completion(nil, err);
        return;
    }
    
    NSDictionary *cached = [self.cache objectForKey:did];
    if (cached) {
        completion(cached, nil);
        return;
    }
    
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", self.plcUrl, did];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *err = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidDID userInfo:@{NSLocalizedDescriptionKey: @"Invalid constructed PLC URL"}];
        completion(nil, err);
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = self.timeout;
    [request setValue:@"application/did+ld+json,application/json" forHTTPHeaderField:@"Accept"];
    
    [self executeRequest:request attempt:0 transform:^id(NSData *data, NSError **error) {
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
            if (error) *error = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidResponse userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse JSON response"}];
            return nil;
        }
        return json;
    } completion:^(id result, NSError *err) {
        if (result) {
            [self.cache setObject:result forKey:did];
        }
        completion(result, err);
    }];
}

- (void)executeRequest:(NSURLRequest *)request attempt:(NSInteger)attempt transform:(id (^)(NSData *data, NSError **error))transform completion:(void (^)(id _Nullable result, NSError * _Nullable error))completion {
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSInteger statusCode = httpResponse ? httpResponse.statusCode : 0;
        
        HttpRetryResult *retryResult = [self.retryPolicy evaluateStatusCode:statusCode networkError:error attemptNumber:attempt];
        
        if (retryResult.decision == HttpRetryDecisionRetryAfter) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(retryResult.retryDelay * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self executeRequest:request attempt:attempt + 1 transform:transform completion:completion];
            });
            return;
        }
        
        if (retryResult.decision == HttpRetryDecisionFail) {
            if (statusCode == 404) {
                NSError *notFoundErr = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorNotFound userInfo:@{NSLocalizedDescriptionKey: @"DID not found on PLC server"}];
                completion(nil, notFoundErr);
                return;
            }
            
            if (statusCode > 0 && statusCode != 200) {
                NSError *statusErr = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidResponse userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unexpected status code: %ld", (long)statusCode]}];
                completion(nil, statusErr);
                return;
            }
            
            NSError *finalError = error ?: [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorNetworkError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server Error: %ld", (long)statusCode]}];
            completion(nil, finalError);
            return;
        }
        
        if (!data) {
            NSError *statusErr = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidResponse userInfo:@{NSLocalizedDescriptionKey: @"Empty response"}];
            completion(nil, statusErr);
            return;
        }
        
        NSError *transformError = nil;
        id result = transform(data, &transformError);
        
        if (transformError || !result) {
            completion(nil, transformError ?: [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidResponse userInfo:@{NSLocalizedDescriptionKey: @"Transform failed"}]);
            return;
        }
        
        completion(result, nil);
    }];
    
    [task resume];
}

- (nullable NSArray *)resolveAuditLogForDID:(NSString *)did error:(NSError **)error {
    if (![PLCOperation isValidDidPlc:did]) {
        if (error) {
            *error = [NSError errorWithDomain:DIDPLCResolverErrorDomain
                                         code:DIDPLCResolverErrorInvalidDID
                                     userInfo:@{NSLocalizedDescriptionKey: @"Provided DID fails strictly length and character validation"}];
        }
        return nil;
    }
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSArray *resolvedLog = nil;
    __block NSError *resolveError = nil;
    
    [self resolveAuditLogForDID:did completion:^(NSArray *log, NSError *err) {
        resolvedLog = log;
        resolveError = err;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_time_t waitTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)((self.timeout + 1.0) * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(semaphore, waitTime) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:DIDPLCResolverErrorDomain
                                         code:DIDPLCResolverErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Synchronous audit log resolution timed out"}];
        }
        return nil;
    }
    
    if (resolveError) {
        if (error) *error = resolveError;
        return nil;
    }
    
    return resolvedLog;
}

- (void)resolveAuditLogForDID:(NSString *)did completion:(void (^)(NSArray * _Nullable, NSError * _Nullable))completion {
    if (!completion) return;
    
    if (![PLCOperation isValidDidPlc:did]) {
        NSError *err = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidDID userInfo:@{NSLocalizedDescriptionKey: @"Provided DID fails strictly length and character validation"}];
        completion(nil, err);
        return;
    }
    
    NSString *urlString = [NSString stringWithFormat:@"%@/%@/log/audit", self.plcUrl, did];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *err = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidDID userInfo:@{NSLocalizedDescriptionKey: @"Invalid constructed PLC URL"}];
        completion(nil, err);
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = self.timeout;
    [request setValue:@"application/did+ld+json,application/json" forHTTPHeaderField:@"Accept"];
    
    [self executeRequest:request attempt:0 transform:^id(NSData *data, NSError **error) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSArray class]]) {
            return json;
        } else {
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSArray *lines = [str componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            NSMutableArray *ops = [NSMutableArray array];
            for (NSString *line in lines) {
                if (line.length > 0) {
                    id opObj = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                    if (opObj) [ops addObject:opObj];
                }
            }
            if (ops.count > 0) {
                return ops;
            } else {
                if (error) *error = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidResponse userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse NDJSON response"}];
                return nil;
            }
        }
    } completion:^(id result, NSError *err) {
        completion(result, err);
    }];
}

- (nullable NSData *)submitOperation:(NSDictionary *)operation did:(NSString *)did statusCode:(NSInteger *)statusCode error:(NSError **)error {
    if (!did) {
        if (error) {
            *error = [NSError errorWithDomain:DIDPLCResolverErrorDomain
                                         code:DIDPLCResolverErrorInvalidDID
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID missing"}];
        }
        return nil;
    }
    
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", self.plcUrl, did];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (error) *error = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorNetworkError userInfo:@{NSLocalizedDescriptionKey: @"Invalid constructed PLC URL"}];
        return nil;
    }
    
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:operation options:0 error:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = bodyData;
    request.timeoutInterval = self.timeout;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSInteger code = 0;
    __block NSError *netError = nil;
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        responseData = data;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            code = [(NSHTTPURLResponse *)response statusCode];
        }
        netError = err;
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((self.timeout + 2.0) * NSEC_PER_SEC)));
    
    if (statusCode) *statusCode = code;
    if (netError && error) *error = netError;
    
    return responseData;
}

@end
