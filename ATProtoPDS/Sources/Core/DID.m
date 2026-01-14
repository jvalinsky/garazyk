/*!
 @file DID.m

 @abstract DID (Decentralized Identifier) document parsing and handling.

 @discussion This file implements DID document deserialization per the W3C
 DID specification. DIDs are used throughout ATProto for identity verification
 and are resolved to DID documents containing verification methods and services.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Core/DID.h"
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
    // _staleTTL and _maxTTL are synthesized properties
    // _cacheTimestamps is synthesized property
}

@synthesize cache = _cache;
@synthesize cacheTimestamps = _cacheTimestamps;
@synthesize staleTTL = _staleTTL;
@synthesize maxTTL = _maxTTL;

- (instancetype)init {
    self = [super init];
    if (self) {
        _log = os_log_create("com.atproto.did", "DIDResolver");

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 60.0;
        _session = [NSURLSession sessionWithConfiguration:config];

        _cache = [[NSCache alloc] init];
        _cache.countLimit = 1000; // Cache up to 1000 DIDs
        _cacheTimestamps = [[NSMutableDictionary alloc] init];
        _staleTTL = 3600.0; // 1 hour
        _maxTTL = 86400.0; // 1 day
    }
    return self;
}

- (void)resolveDID:(NSString *)did completion:(void (^)(NSDictionary *document, NSError *error))completion {
    // Check cache first with TTL logic
    DIDCacheStatus status;
    NSDictionary *entry = [self cachedEntryForDID:did status:&status];
    if (entry && status == DIDCacheStatusFresh) {
        DIDDocument *doc = entry[@"document"];
        completion(doc.jsonDictionary, nil);
        return;
    }
    if (entry && status == DIDCacheStatusStale) {
        DIDDocument *doc = entry[@"document"];
        completion(doc.jsonDictionary, nil);
        [self refreshCacheForDID:did];
        return;
    }

    // Perform resolution
    [self resolveDID:did forceRefresh:NO completion:^(DIDDocument *document, NSError *error) {
        if (document && !error) {
            completion(document.jsonDictionary, nil);
        } else {
            completion(nil, error);
        }
    }];
}

- (void)resolveMultipleDIDs:(NSArray<NSString *> *)dids completion:(void (^)(NSDictionary<NSString *, id> *results, NSError *error))completion {
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    __block NSUInteger remaining = dids.count;
    __block NSError *batchError = nil;

    for (NSString *did in dids) {
        [self resolveDID:did completion:^(NSDictionary *document, NSError *error) {
            @synchronized(results) {
                if (error) {
                    // Store error information for failed resolutions
                    results[did] = @{@"error": error};
                    if (!batchError) {
                        batchError = error; // Keep first error for batch-level error
                    }
                } else if (document) {
                    results[did] = @{@"document": document};
                }
                remaining--;
                if (remaining == 0) {
                    completion(results, batchError);
                }
            }
        }];
    }
}



- (void)resolveDID:(NSString *)did
     forceRefresh:(BOOL)forceRefresh
       completion:(void (^)(DIDDocument * _Nullable document, NSError * _Nullable error))completion {

    if (!completion) return;

    NSError *validationError = [self validateDID:did];
    if (validationError) {
        completion(nil, validationError);
        return;
    }

    // Check cache first unless force refresh
    if (!forceRefresh) {
        DIDCacheStatus status;
        NSDictionary *entry = [self cachedEntryForDID:did status:&status];
        if (entry && status == DIDCacheStatusFresh) {
            os_log_info(_log, "Returning fresh cached DID document for %@", did);
            completion(entry[@"document"], nil);
            return;
        }
        if (entry && status == DIDCacheStatusStale) {
            os_log_info(_log, "Returning stale cached DID document for %@ and refreshing", did);
            completion(entry[@"document"], nil);
            [self refreshCacheForDID:did];
            return;
        }
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
    
    [self resolveDID:did forceRefresh:NO completion:^(DIDDocument * _Nullable document, NSError * _Nullable resolveError) {
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

- (nullable NSDictionary *)cachedEntryForDID:(NSString *)did status:(DIDCacheStatus *)outStatus {
    @synchronized(self) {
        NSDictionary *document = [self.cache objectForKey:did];
        if (!document) {
            *outStatus = DIDCacheStatusExpired;
            return nil;
        }

        NSNumber *timestamp = _cacheTimestamps[did];
        if (!timestamp) {
            *outStatus = DIDCacheStatusExpired;
            return nil;
        }

        NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - [timestamp doubleValue];
        if (age > _maxTTL) {
            *outStatus = DIDCacheStatusExpired;
            [self.cache removeObjectForKey:did];
            [_cacheTimestamps removeObjectForKey:did];
            return nil;
        } else if (age > _staleTTL) {
            *outStatus = DIDCacheStatusStale;
        } else {
            *outStatus = DIDCacheStatusFresh;
        }

        return @{@"document": document};
    }
}

- (void)cacheDocument:(DIDDocument *)document forDID:(NSString *)did {
    @synchronized(self) {
        [self.cache setObject:document forKey:did];
        _cacheTimestamps[did] = @([[NSDate date] timeIntervalSince1970]);
    }
}

- (nullable NSDictionary *)resolveAtprotoDataForDID:(NSString *)did error:(NSError **)error {
    DIDDocument *doc = [self resolveDIDSync:did error:error];
    if (!doc) return nil;

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"did"] = doc.id;

    // Extract handle from alsoKnownAs (first one, or atproto handle)
    if (doc.alsoKnownAs.count > 0) {
        result[@"handle"] = doc.alsoKnownAs[0];
    }

    // Extract PDS from service
    if (doc.service) {
        for (NSDictionary *service in doc.service) {
            NSString *type = service[@"type"];
            if ([type isEqualToString:@"AtprotoPersonalDataServer"]) {
                result[@"pds"] = service[@"serviceEndpoint"];
                break;
            }
        }
    }

    // Extract signing key (first verification method)
    NSDictionary *json = doc.jsonDictionary;
    NSArray *verificationMethods = json[@"verificationMethod"];
    if (verificationMethods.count > 0) {
        NSDictionary *method = verificationMethods[0];
        result[@"signingKey"] = method[@"publicKeyMultibase"];
    }

    return [result copy];
}

- (void)refreshCacheForDID:(NSString *)did {
    [self resolveDID:did forceRefresh:YES completion:^(DIDDocument *document, NSError *error) {
        if (document) {
            @synchronized(self) {
                [self.cache setObject:document forKey:did];
                _cacheTimestamps[did] = @([[NSDate date] timeIntervalSince1970]);
            }
        }
    }];
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