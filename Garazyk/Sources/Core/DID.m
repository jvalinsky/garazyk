// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
#import "App/ATProtoServiceConfiguration.h"
#import "Debug/GZLogger.h"
#import "Network/ATProtoSafeHTTPClient.h"

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
    dispatch_queue_t _cacheQueue;
    // _staleTTL and _maxTTL are synthesized properties
    // _cacheTimestamps is synthesized property
}

+ (instancetype)sharedResolver {
    static DIDResolver *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[DIDResolver alloc] init];
        shared.plcURL = [ATProtoServiceConfiguration sharedConfiguration].plcURL;
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cacheQueue = dispatch_queue_create("com.atproto.did.cache", DISPATCH_QUEUE_SERIAL);
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

- (void)seedCacheWithDID:(NSString *)did documentJSON:(NSDictionary *)json {
    if (!did || !json) return;
    NSError *error = nil;
    DIDDocument *doc = [DIDDocument documentWithJSON:json error:&error];
    if (doc) {
        [self cacheDocument:doc forDID:did];
    }
}

- (void)invalidateDID:(NSString *)did {
    if (did.length == 0) return;
    dispatch_sync(_cacheQueue, ^{
        [self.cache removeObjectForKey:did];
        [self.cacheTimestamps removeObjectForKey:did];
    });
}

- (void)resolveDID:(NSString *)did completion:(void (^)(NSDictionary *document, NSError *error))completion {
    // Check cache first with TTL logic
    DIDCacheStatus status;
    NSDictionary *entry = [self cachedEntryForDID:did status:&status];
    if (entry && status == DIDCacheStatusFresh) {
        GZ_LOG_CORE_DEBUG(@"Returning fresh cached DID document");
        DIDDocument *doc = entry[@"document"];
        completion(doc.jsonDictionary, nil);
        return;
    }
    if (entry && status == DIDCacheStatusStale) {
        GZ_LOG_CORE_DEBUG(@"Returning stale cached DID document and refreshing");
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
            dispatch_sync(self->_cacheQueue, ^{
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
            });
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
            GZ_LOG_CORE_DEBUG(@"Returning fresh cached DID document");
            completion(entry[@"document"], nil);
            return;
        }
        if (entry && status == DIDCacheStatusStale) {
            GZ_LOG_CORE_DEBUG(@"Returning stale cached DID document and refreshing");
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
    __block NSDictionary *result = nil;
    dispatch_sync(_cacheQueue, ^{
        NSDictionary *document = [self.cache objectForKey:did];
        if (!document) {
            *outStatus = DIDCacheStatusExpired;
            return;
        }

        NSNumber *timestamp = _cacheTimestamps[did];
        if (!timestamp) {
            *outStatus = DIDCacheStatusExpired;
            return;
        }

        NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - [timestamp doubleValue];
        if (age > _maxTTL) {
            *outStatus = DIDCacheStatusExpired;
            [self.cache removeObjectForKey:did];
            [_cacheTimestamps removeObjectForKey:did];
            return;
        } else if (age > _staleTTL) {
            *outStatus = DIDCacheStatusStale;
        } else {
            *outStatus = DIDCacheStatusFresh;
        }

        result = @{@"document": document};
    });
    return result;
}

- (void)cacheDocument:(DIDDocument *)document forDID:(NSString *)did {
    dispatch_sync(_cacheQueue, ^{
        [self.cache setObject:document forKey:did];
        _cacheTimestamps[did] = @([[NSDate date] timeIntervalSince1970]);
    });
}

- (nullable NSDictionary *)resolveAtprotoDataForDID:(NSString *)did error:(NSError **)error {
    return [self resolveAtprotoDataForDID:did forceRefresh:NO error:error];
}

- (nullable NSDictionary *)resolveAtprotoDataForDID:(NSString *)did forceRefresh:(BOOL)forceRefresh error:(NSError **)error {
    DIDDocument *doc = [self resolveDIDSync:did forceRefresh:forceRefresh error:error];
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
            dispatch_sync(self->_cacheQueue, ^{
                [self.cache setObject:document forKey:did];
                self->_cacheTimestamps[did] = @([[NSDate date] timeIntervalSince1970]);
            });
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
    
    GZ_LOG_CORE_DEBUG(@"Resolving did:web URL: %@", urlString ?: @"");
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:kDefaultUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/did+ld+json,application/json" forHTTPHeaderField:@"Accept"];
    
    [[ATProtoSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request
                                                   options:[ATProtoSafeHTTPClientOptions defaultOptions]
                                                completion:^(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {
        
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
}

- (void)processPLCResponseData:(NSData *)data did:(NSString *)did completion:(void (^)(DIDDocument *_Nullable, NSError *_Nullable))completion {
    if (!data || data.length == 0) {
        completion(nil, [NSError errorWithDomain:DIDErrorDomain
                                           code:DIDErrorResolutionFailed
                                       userInfo:@{NSLocalizedDescriptionKey: @"No data received from PLC DID resolution"}]);
        return;
    }

    NSError *jsonError;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonError) {
        completion(nil, [NSError errorWithDomain:DIDErrorDomain
                                           code:DIDErrorInvalidDocument
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON in PLC DID document",
                                                  NSUnderlyingErrorKey: jsonError}]);
        return;
    }

    DIDDocument *document = [DIDDocument documentWithJSON:json error:&jsonError];
    if (!document) {
        completion(nil, [NSError errorWithDomain:DIDErrorDomain
                                           code:DIDErrorInvalidDocument
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid PLC DID document structure",
                                                  NSUnderlyingErrorKey: jsonError}]);
        return;
    }

    [self cacheDocument:document forDID:did];
    completion(document, nil);
}

- (void)resolveDIDPLC:(NSString *)did completion:(void (^)(DIDDocument * _Nullable, NSError * _Nullable))completion {
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", self.plcURL, did];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        completion(nil, [NSError errorWithDomain:DIDErrorDomain
                                           code:DIDErrorInvalidIdentifier
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from PLC DID"}]);
        return;
    }

    GZ_LOG_CORE_DEBUG(@"Resolving did:plc URL: %@", urlString ?: @"");

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:kDefaultUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/did+ld+json,application/json" forHTTPHeaderField:@"Accept"];

    ATProtoSafeHTTPClientOptions *httpOptions = [ATProtoSafeHTTPClientOptions defaultOptions];
#if defined(GNUSTEP)
    httpOptions.timeout = 2.0;
#endif

    [[ATProtoSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request
                                                   options:httpOptions
                                                completion:^(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {

        if (!error && response.statusCode == 200 && data.length > 0) {
            [self processPLCResponseData:data did:did completion:completion];
            return;
        }

#if defined(GNUSTEP)
        GZ_LOG_CORE_DEBUG(@"NSURLSession failed, trying curl fallback: %@", urlString ?: @"");

        NSTask *curlTask = [[NSTask alloc] init];
        [curlTask setLaunchPath:@"/usr/bin/curl"];
        [curlTask setArguments:@[
            @"-s", @"--noproxy", @"*", @"--max-time", @"10",
            @"-H", @"Accept: application/did+ld+json,application/json",
            urlString
        ]];

        NSPipe *outPipe = [NSPipe pipe];
        [curlTask setStandardOutput:outPipe];
        [curlTask setStandardError:[NSFileHandle fileHandleWithNullDevice]];

        @try {
            [curlTask launch];
            [curlTask waitUntilExit];

            if (curlTask.terminationStatus == 0) {
                NSData *curlData = [[outPipe fileHandleForReading] readDataToEndOfFile];
                if (curlData.length > 0) {
                    [self processPLCResponseData:curlData did:did completion:completion];
                    return;
                }
            }
        } @catch (NSException *exception) {
            GZ_LOG_CORE_WARN(@"curl fallback exception: %@", exception.reason);
        }

        GZ_LOG_CORE_WARN(@"All PLC resolution methods failed for DID: %@", did);
#endif

        NSError *underlying = error ?: [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
        completion(nil, [NSError errorWithDomain:DIDErrorDomain
                                           code:DIDErrorNetworkError
                                       userInfo:@{NSLocalizedDescriptionKey: @"Network error during PLC DID resolution",
                                                  NSUnderlyingErrorKey: underlying}]);
    }];
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
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    ATProtoSafeHTTPClientOptions *options = [ATProtoSafeHTTPClientOptions defaultOptions];
    options.timeout = 10.0;

    NSHTTPURLResponse *httpResponse = nil;
    NSError *requestError = nil;
    NSData *data = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                    options:options
                                                                   response:&httpResponse
                                                                      error:&requestError];
    
    if (requestError) {
        if (error) *error = requestError;
        return nil;
    }

    if (!httpResponse || httpResponse.statusCode != 200) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                        code:DIDErrorResolutionFailed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Handle resolution failed"}];
        }
        return nil;
    }

    NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!responseString) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                        code:DIDErrorInvalidDocument
                                    userInfo:@{NSLocalizedDescriptionKey: @"Invalid response encoding"}];
        }
        return nil;
    }

    // Response should be a DID string
    responseString = [responseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([responseString hasPrefix:@"did:"]) {
        return responseString;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                        code:DIDErrorInvalidDocument
                                    userInfo:@{NSLocalizedDescriptionKey: @"Response is not a valid DID"}];
        }
        return nil;
    }
}

@end
