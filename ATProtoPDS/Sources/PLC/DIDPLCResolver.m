#import "DIDPLCResolver.h"
#import "PLCOperation.h"

NSString * const DIDPLCResolverErrorDomain = @"com.atproto.plc.resolver";

@interface DIDPLCResolver ()

@property (nonatomic, copy) NSString *plcUrl;
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *cache;

@end

@implementation DIDPLCResolver

- (instancetype)initWithPlcUrl:(NSString *)url {
    self = [super init];
    if (self) {
        _plcUrl = [url copy];
        _timeout = 5.0; // Default timeout
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 1000;
    }
    return self;
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
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    [self executeRequest:request retries:3 currentDelay:0.5 completion:^(NSDictionary *doc, NSError *err) {
        if (doc) {
            [self.cache setObject:doc forKey:did];
        }
        completion(doc, err);
    }];
}

- (void)executeRequest:(NSURLRequest *)request retries:(NSInteger)retries currentDelay:(NSTimeInterval)delay completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if (error || (httpResponse && httpResponse.statusCode >= 500)) {
            if (retries > 0) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self executeRequest:request retries:retries - 1 currentDelay:delay * 2 completion:completion];
                });
                return;
            }
            
            NSError *finalError = error ?: [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorNetworkError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server Error: %ld", (long)httpResponse.statusCode]}];
            completion(nil, finalError);
            return;
        }
        
        if (httpResponse.statusCode == 404) {
            NSError *notFoundErr = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorNotFound userInfo:@{NSLocalizedDescriptionKey: @"DID not found on PLC server"}];
            completion(nil, notFoundErr);
            return;
        }
        
        if (httpResponse.statusCode != 200 || !data) {
            NSError *statusErr = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidResponse userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unexpected status code: %ld", (long)httpResponse.statusCode]}];
            completion(nil, statusErr);
            return;
        }
        
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
            NSError *parseErr = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidResponse userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse JSON response"}];
            completion(nil, parseErr);
            return;
        }
        
        completion(json, nil);
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
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    [self executeRawRequest:request retries:3 currentDelay:0.5 completion:^(NSData *data, NSError *err) {
        if (err || !data) {
            completion(nil, err);
            return;
        }
        
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSArray class]]) {
            completion(json, nil);
            return;
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
                completion(ops, nil);
            } else {
                NSError *parseErr = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidResponse userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse NDJSON response"}];
                completion(nil, parseErr);
            }
        }
    }];
}

- (void)executeRawRequest:(NSURLRequest *)request retries:(NSInteger)retries currentDelay:(NSTimeInterval)delay completion:(void (^)(NSData * _Nullable, NSError * _Nullable))completion {
    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if (error || (httpResponse && httpResponse.statusCode >= 500)) {
            if (retries > 0) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self executeRawRequest:request retries:retries - 1 currentDelay:delay * 2 completion:completion];
                });
                return;
            }
            
            NSError *finalError = error ?: [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorNetworkError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server Error: %ld", (long)httpResponse.statusCode]}];
            completion(nil, finalError);
            return;
        }
        
        if (httpResponse.statusCode == 404) {
            NSError *notFoundErr = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorNotFound userInfo:@{NSLocalizedDescriptionKey: @"DID not found on PLC server"}];
            completion(nil, notFoundErr);
            return;
        }
        
        if (httpResponse.statusCode != 200 || !data) {
            NSError *statusErr = [NSError errorWithDomain:DIDPLCResolverErrorDomain code:DIDPLCResolverErrorInvalidResponse userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unexpected status code: %ld", (long)httpResponse.statusCode]}];
            completion(nil, statusErr);
            return;
        }
        
    }];
    
    [task resume];
}

@end
