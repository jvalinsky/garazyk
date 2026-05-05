/*!
 @file DID.m

 @abstract DID (Decentralized Identifier) document parsing and handling.

 @discussion This file implements DID document deserialization per the W3C
 DID specification. DIDs are used throughout ATProto for identity verification
 and are resolved to DID documents containing verification methods and services.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Core/DID.h"
#import "Core/ATURI.h"
#import "Core/CID.h"
#import "App/PDSConfiguration.h"
#import "Debug/PDSLogger.h"

NSErrorDomain const DIDErrorDomain = @"com.atproto.did";
static NSString *const kDefaultUserAgent = @"atprotopds/0.1.0";
static NSString *const kDIDAcceptHeader = @"application/did+ld+json,application/json";

@interface DIDResolver () <NSURLSessionTaskDelegate>
@end

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
    
    NSString *documentId = json[@"id"];
    if (!documentId || ![documentId isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                      code:DIDErrorInvalidDocument
                                  userInfo:@{NSLocalizedDescriptionKey: @"DID document missing 'id' field"}];
        }
        return nil;
    }
    
    NSArray<NSString *> *alsoKnownAs = nil;
    id alsoKnownAsValue = json[@"alsoKnownAs"];
    if ([alsoKnownAsValue isKindOfClass:[NSArray class]]) {
        alsoKnownAs = alsoKnownAsValue;
    }

    NSArray<NSDictionary *> *service = nil;
    id serviceValue = json[@"service"];
    if ([serviceValue isKindOfClass:[NSArray class]]) {
        service = serviceValue;
    } else if ([serviceValue isKindOfClass:[NSDictionary class]]) {
        service = @[serviceValue];
    }

    DIDDocument *document = [[DIDDocument alloc] init];
    if (document) {
        document->_jsonDictionary = [json copy];
        document->_id = [documentId copy];
        document->_alsoKnownAs = [alsoKnownAs copy];
        document->_service = [service copy];
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
    NSURLSession *_session;
    dispatch_queue_t _didQueue;
    // _staleTTL and _maxTTL are synthesized properties
    // _cacheTimestamps is synthesized property
}

@synthesize cache = _cache;
@synthesize cacheTimestamps = _cacheTimestamps;
@synthesize staleTTL = _staleTTL;
@synthesize maxTTL = _maxTTL;

+ (instancetype)sharedResolver {
    static DIDResolver *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[DIDResolver alloc] init];
        shared.plcURL = [PDSConfiguration sharedConfiguration].plcURL;
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _didQueue = dispatch_queue_create("com.atproto.did", DISPATCH_QUEUE_SERIAL);
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        config.timeoutIntervalForResource = 15.0;
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];

        _cache = [[NSCache alloc] init];
        _cache.countLimit = 1000;
        _cacheTimestamps = [[NSMutableDictionary alloc] init];
        _staleTTL = 3600.0;
        _maxTTL = 86400.0;
        NSString *envPlc = NSProcessInfo.processInfo.environment[@"PDS_PLC_URL"];
        _plcURL = envPlc ?: @"https://plc.directory";
    }
    return self;
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(nil);
}

- (void)resolveDID:(NSString *)did completion:(void (^)(NSDictionary *document, NSError *error))completion {
    // Check cache first with TTL logic
    DIDCacheStatus status;
    NSDictionary *entry = [self cachedEntryForDID:did status:&status];
    if (entry && status == DIDCacheStatusFresh) {
        PDS_LOG_CORE_DEBUG(@"Returning fresh cached DID document");
        DIDDocument *doc = entry[@"document"];
        completion(doc.jsonDictionary, nil);
        return;
    }
    if (entry && status == DIDCacheStatusStale) {
        PDS_LOG_CORE_DEBUG(@"Returning stale cached DID document and refreshing");
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
            PDS_LOG_CORE_DEBUG(@"Returning fresh cached DID document");
            completion(entry[@"document"], nil);
            return;
        }
        if (entry && status == DIDCacheStatusStale) {
            PDS_LOG_CORE_DEBUG(@"Returning stale cached DID document and refreshing");
            completion(entry[@"document"], nil);
            [self refreshCacheForDID:did];
            return;
        }
    }

    // Parse DID method using ATDID primitive
    ATDID *parsedDID = [ATDID didWithString:did error:nil];
    if (!parsedDID) {
        NSError *error = [NSError errorWithDomain:DIDErrorDomain
                                          code:DIDErrorInvalidIdentifier
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid DID format"}];
        completion(nil, error);
        return;
    }

    NSString *method = parsedDID.method;

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
    return [self resolveDIDSync:did forceRefresh:NO error:error];
}

- (nullable DIDDocument *)resolveDIDSync:(NSString *)did forceRefresh:(BOOL)forceRefresh error:(NSError **)error {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block DIDDocument *result = nil;
    __block NSError *resultError = nil;
    
    [self resolveDID:did forceRefresh:forceRefresh completion:^(DIDDocument * _Nullable document, NSError * _Nullable resolveError) {
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

    // Extract handle from alsoKnownAs (prefer at:// entry)
    if (doc.alsoKnownAs.count > 0) {
        NSString *handle = nil;
        for (id entry in doc.alsoKnownAs) {
            if ([entry isKindOfClass:[NSString class]] && [entry hasPrefix:@"at://"]) {
                handle = entry;
                break;
            }
        }
        if (!handle) {
            for (id entry in doc.alsoKnownAs) {
                if ([entry isKindOfClass:[NSString class]]) {
                    handle = entry;
                    break;
                }
            }
        }
        if (handle) {
            result[@"handle"] = handle;
        }
    }

    // Extract PDS from service
    if (doc.service) {
        for (id service in doc.service) {
            if (![service isKindOfClass:[NSDictionary class]]) {
                continue;
            }
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
    if ([verificationMethods isKindOfClass:[NSArray class]] && verificationMethods.count > 0) {
        NSDictionary *selectedMethod = nil;
        for (id entry in verificationMethods) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSString *candidateKey = entry[@"publicKeyMultibase"];
            if (!candidateKey) {
                continue;
            }
            NSString *methodId = entry[@"id"];
            NSString *methodType = entry[@"type"];
            if ([methodId isKindOfClass:[NSString class]] && [methodId containsString:@"#atproto"]) {
                selectedMethod = entry;
                break;
            }
            if (!selectedMethod && [methodType isKindOfClass:[NSString class]] && [methodType isEqualToString:@"Multikey"]) {
                selectedMethod = entry;
            } else if (!selectedMethod) {
                selectedMethod = entry;
            }
        }

        NSString *signingKey = selectedMethod[@"publicKeyMultibase"];
        if ([signingKey isKindOfClass:[NSString class]]) {
            result[@"signingKey"] = signingKey;

            if (signingKey.length > 1) {
                unichar prefix = [signingKey characterAtIndex:0];
                NSString *payload = [signingKey substringFromIndex:1];
                NSData *keyBytes = nil;
                if (prefix == 'z') {
                    keyBytes = [CID base58btcDecode:payload];
                } else if (prefix == 'b') {
                    keyBytes = [CID base32Decode:payload];
                }

                if (keyBytes.length > 2) {
                    const uint8_t *bytes = keyBytes.bytes;
                    if (bytes[0] == 0xE7 && bytes[1] == 0x01) {
                        keyBytes = [keyBytes subdataWithRange:NSMakeRange(2, keyBytes.length - 2)];
                    }
                }

                if (keyBytes) {
                    result[@"signingKeyBytes"] = keyBytes;
                }
            }
        }
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
    
    ATDID *parsedDID = [ATDID didWithString:did error:nil];
    if (!parsedDID) {
        NSError *error = [NSError errorWithDomain:DIDErrorDomain
                                         code:DIDErrorInvalidIdentifier
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid did:web format"}];
        completion(nil, error);
        return;
    }
    
    NSArray<NSString *> *identifierParts = [parsedDID.identifier componentsSeparatedByString:@":"];
    NSString *domain = identifierParts[0];
    NSString *path = @".well-known/did.json";
    
    if (identifierParts.count > 1) {
        // Additional path components
        NSArray<NSString *> *pathComponents = [identifierParts subarrayWithRange:NSMakeRange(1, identifierParts.count - 1)];
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
    
    PDS_LOG_CORE_DEBUG(@"Resolving did:web URL: %@", urlString ?: @"");
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:kDefaultUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/did+ld+json,application/json" forHTTPHeaderField:@"Accept"];
    
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request
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
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", self.plcURL, did];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        NSError *error = [NSError errorWithDomain:DIDErrorDomain
                                          code:DIDErrorInvalidIdentifier
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from PLC DID"}];
        completion(nil, error);
        return;
    }

    PDS_LOG_CORE_DEBUG(@"Resolving did:plc URL: %@", urlString ?: @"");
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:kDefaultUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/did+ld+json,application/json" forHTTPHeaderField:@"Accept"];
    
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request
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

- (nullable NSString *)resolveHandleSync:(NSString *)handle error:(NSError **)error {
    if (!handle || handle.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                          code:DIDErrorInvalidIdentifier
                                      userInfo:@{NSLocalizedDescriptionKey: @"Handle is empty"}];
        }
        return nil;
    }

    // Normalize handle (remove @ prefix if present)
    NSString *normalizedHandle = handle;
    if ([normalizedHandle hasPrefix:@"@"]) {
        normalizedHandle = [normalizedHandle substringFromIndex:1];
    }

    // Build well-known URL: https://{handle}/.well-known/atproto-did
    NSString *urlString = [NSString stringWithFormat:@"https://%@/.well-known/atproto-did", normalizedHandle];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                          code:DIDErrorInvalidIdentifier
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid handle URL"}];
        }
        return nil;
    }

    // Synchronous network request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10.0];
    request.HTTPMethod = @"GET";

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSString *resolvedDID = nil;
    __block NSError *requestError = nil;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err) {
                requestError = err;
                dispatch_semaphore_signal(sem);
                return;
            }

            NSHTTPURLResponse *httpResponse = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
            if (!httpResponse || httpResponse.statusCode != 200) {
                requestError = [NSError errorWithDomain:DIDErrorDomain
                                                    code:DIDErrorResolutionFailed
                                                userInfo:@{NSLocalizedDescriptionKey: @"Handle resolution failed"}];
                dispatch_semaphore_signal(sem);
                return;
            }

            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!responseString) {
                requestError = [NSError errorWithDomain:DIDErrorDomain
                                                    code:DIDErrorInvalidDocument
                                                userInfo:@{NSLocalizedDescriptionKey: @"Invalid response encoding"}];
                dispatch_semaphore_signal(sem);
                return;
            }

            // Response should be a DID string
            responseString = [responseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([responseString hasPrefix:@"did:"]) {
                resolvedDID = responseString;
            } else {
                requestError = [NSError errorWithDomain:DIDErrorDomain
                                                    code:DIDErrorInvalidDocument
                                                userInfo:@{NSLocalizedDescriptionKey: @"Response is not a valid DID"}];
            }
            dispatch_semaphore_signal(sem);
        }];

    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (requestError && error) {
        *error = requestError;
    }
    return resolvedDID;
}

@end
