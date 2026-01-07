#import "DID.h"
#import <os/log.h>

NSErrorDomain const DIDErrorDomain = @"com.atproto.did";

@implementation DIDDocument

+ (nullable instancetype)documentWithJSON:(NSDictionary *)json error:(NSError **)error {
    if (!json || ![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                      code:DIDErrorInvalidDocument
                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON for DID document"}];
        }
        return nil;
    }
    
    NSString *id = json[@"id"];
    if (!id || ![id isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                      code:DIDErrorInvalidDocument
                                  userInfo:@{NSLocalizedDescriptionKey: @"DID document missing 'id' field"}];
        }
        return nil;
    }
    
    DIDDocument *document = [[DIDDocument alloc] init];
    if (document) {
        document->_jsonDictionary = [json copy];
        document->_id = [id copy];
        document->_alsoKnownAs = json[@"alsoKnownAs"];
        document->_service = json[@"service"];
    }
    return document;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.jsonDictionary forKey:@"jsonDictionary"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSDictionary *json = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"jsonDictionary"];
    if (!json) {
        return nil;
    }
    
    NSError *error;
    return [DIDDocument documentWithJSON:json error:&error];
}

@end

@implementation DIDResolver {
    os_log_t _log;
    NSURLSession *_session;
    NSMutableDictionary<NSString *, NSDictionary *> *_cache;
    NSTimeInterval _cacheTTL;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _log = os_log_create("com.atproto.did", "DIDResolver");

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 60.0;
        _session = [NSURLSession sessionWithConfiguration:config];

        _cache = [[NSMutableDictionary alloc] init];
        _cacheTTL = 300.0; // 5 minutes
    }
    return self;
}

- (void)resolveDID:(NSString *)did
        completion:(void (^)(DIDDocument * _Nullable document, NSError * _Nullable error))completion {

    if (!completion) return;

    NSError *validationError = [self validateDID:did];
    if (validationError) {
        completion(nil, validationError);
        return;
    }

    // Check cache first
    DIDDocument *cached = [self cachedDocumentForDID:did];
    if (cached) {
        os_log_info(_log, "Returning cached DID document for %@", did);
        completion(cached, nil);
        return;
    }

    // Parse DID method
    NSArray<NSString *> *components = [did componentsSeparatedByString:@":"];
    if (components.count < 3) {
        NSError *error = [NSError errorWithDomain:DIDErrorDomain
                                          code:DIDErrorInvalidIdentifier
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid DID format"}];
        completion(nil, error);
        return;
    }

    NSString *method = components[1];

    if ([method isEqualToString:@"web"]) {
        [self resolveDIDWeb:did completion:completion];
    } else if ([method isEqualToString:@"plc"]) {
        [self resolveDIDPLC:did completion:completion];
    } else {
        NSError *error = [NSError errorWithDomain:DIDErrorDomain
                                          code:DIDErrorInvalidIdentifier
                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported DID method: %@", method]}];
        completion(nil, error);
    }
}

- (nullable DIDDocument *)resolveDIDSync:(NSString *)did error:(NSError **)error {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block DIDDocument *result = nil;
    __block NSError *resultError = nil;
    
    [self resolveDID:did completion:^(DIDDocument * _Nullable document, NSError * _Nullable resolveError) {
        result = document;
        resultError = resolveError;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    
    if (error) {
        *error = resultError;
    }
    return result;
}

#pragma mark - Private Methods

- (nullable DIDDocument *)cachedDocumentForDID:(NSString *)did {
    @synchronized(self) {
        NSDictionary *entry = _cache[did];
        if (!entry) return nil;

        NSDate *timestamp = entry[@"timestamp"];
        if ([[NSDate date] timeIntervalSinceDate:timestamp] > _cacheTTL) {
            [_cache removeObjectForKey:did];
            return nil;
        }

        return entry[@"document"];
    }
}

- (void)cacheDocument:(DIDDocument *)document forDID:(NSString *)did {
    @synchronized(self) {
        NSDictionary *entry = @{@"document": document, @"timestamp": [NSDate date]};
        _cache[did] = entry;
    }
}

- (NSError *)validateDID:(NSString *)did {
    if (!did || did.length == 0) {
        return [NSError errorWithDomain:DIDErrorDomain
                                code:DIDErrorInvalidIdentifier
                            userInfo:@{NSLocalizedDescriptionKey: @"DID cannot be empty"}];
    }
    
    if (![did hasPrefix:@"did:"]) {
        return [NSError errorWithDomain:DIDErrorDomain
                                code:DIDErrorInvalidIdentifier
                            userInfo:@{NSLocalizedDescriptionKey: @"DID must start with 'did:'"}];
    }
    
    return nil;
}

- (void)resolveDIDWeb:(NSString *)did completion:(void (^)(DIDDocument * _Nullable, NSError * _Nullable))completion {
    // did:web:example.com -> https://example.com/.well-known/did.json
    // did:web:example.com:user -> https://example.com/user/did.json
    
    NSArray<NSString *> *parts = [did componentsSeparatedByString:@":"];
    if (parts.count < 3) {
        NSError *error = [NSError errorWithDomain:DIDErrorDomain
                                         code:DIDErrorInvalidIdentifier
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid did:web format"}];
        completion(nil, error);
        return;
    }
    
    NSString *domain = parts[2];
    NSString *path = @".well-known/did.json";
    
    if (parts.count > 3) {
        // Additional path components
        NSArray<NSString *> *pathComponents = [parts subarrayWithRange:NSMakeRange(3, parts.count - 3)];
        path = [[pathComponents componentsJoinedByString:@"/"] stringByAppendingPathComponent:@"did.json"];
    }
    
    NSString *urlString = [NSString stringWithFormat:@"https://%@/%@", domain, path];
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url) {
        NSError *error = [NSError errorWithDomain:DIDErrorDomain
                                         code:DIDErrorInvalidIdentifier
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from DID"}];
        completion(nil, error);
        return;
    }
    
    os_log_info(_log, "Resolving did:web at URL: %@", urlString);
    
    NSURLSessionDataTask *task = [_session dataTaskWithURL:url
                                         completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        if (error) {
            NSError *resolveError = [NSError errorWithDomain:DIDErrorDomain
                                                     code:DIDErrorNetworkError
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Network error during DID resolution",
                                                           NSUnderlyingErrorKey: error}];
            completion(nil, resolveError);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSError *resolveError = [NSError errorWithDomain:DIDErrorDomain
                                                     code:DIDErrorResolutionFailed
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld when resolving DID", (long)httpResponse.statusCode]}];
            completion(nil, resolveError);
            return;
        }
        
        if (!data) {
            NSError *resolveError = [NSError errorWithDomain:DIDErrorDomain
                                                     code:DIDErrorResolutionFailed
                                                 userInfo:@{NSLocalizedDescriptionKey: @"No data received from DID resolution"}];
            completion(nil, resolveError);
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            NSError *resolveError = [NSError errorWithDomain:DIDErrorDomain
                                                     code:DIDErrorInvalidDocument
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON in DID document",
                                                           NSUnderlyingErrorKey: jsonError}];
            completion(nil, resolveError);
            return;
        }
        
        DIDDocument *document = [DIDDocument documentWithJSON:json error:&jsonError];
        if (!document) {
            NSError *resolveError = [NSError errorWithDomain:DIDErrorDomain
                                                      code:DIDErrorInvalidDocument
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid DID document structure",
                                                            NSUnderlyingErrorKey: jsonError}];
            completion(nil, resolveError);
            return;
        }

        [self cacheDocument:document forDID:did];
        completion(document, nil);
    }];
    
    [task resume];
}

- (void)resolveDIDPLC:(NSString *)did completion:(void (^)(DIDDocument * _Nullable, NSError * _Nullable))completion {
    // did:plc:<id> -> https://plc.directory/<did>
    NSString *urlString = [NSString stringWithFormat:@"https://plc.directory/%@", did];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        NSError *error = [NSError errorWithDomain:DIDErrorDomain
                                          code:DIDErrorInvalidIdentifier
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from PLC DID"}];
        completion(nil, error);
        return;
    }

    os_log_info(_log, "Resolving did:plc at URL: %@", urlString);

    NSURLSessionDataTask *task = [_session dataTaskWithURL:url
                                          completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {

        if (error) {
            NSError *resolveError = [NSError errorWithDomain:DIDErrorDomain
                                                      code:DIDErrorNetworkError
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Network error during PLC DID resolution",
                                                            NSUnderlyingErrorKey: error}];
            completion(nil, resolveError);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSError *resolveError = [NSError errorWithDomain:DIDErrorDomain
                                                      code:DIDErrorResolutionFailed
                                                  userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld when resolving PLC DID", (long)httpResponse.statusCode]}];
            completion(nil, resolveError);
            return;
        }

        if (!data) {
            NSError *resolveError = [NSError errorWithDomain:DIDErrorDomain
                                                      code:DIDErrorResolutionFailed
                                                  userInfo:@{NSLocalizedDescriptionKey: @"No data received from PLC DID resolution"}];
            completion(nil, resolveError);
            return;
        }

        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            NSError *resolveError = [NSError errorWithDomain:DIDErrorDomain
                                                      code:DIDErrorInvalidDocument
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON in PLC DID document",
                                                            NSUnderlyingErrorKey: jsonError}];
            completion(nil, resolveError);
            return;
        }

        DIDDocument *document = [DIDDocument documentWithJSON:json error:&jsonError];
        if (!document) {
            NSError *resolveError = [NSError errorWithDomain:DIDErrorDomain
                                                      code:DIDErrorInvalidDocument
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid PLC DID document structure",
                                                            NSUnderlyingErrorKey: jsonError}];
            completion(nil, resolveError);
            return;
        }

        [self cacheDocument:document forDID:did];
        completion(document, nil);
    }];

    [task resume];
}

@end