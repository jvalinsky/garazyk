// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Beskid/BeskidXrpcRoutePack.h"
#import "Beskid/BeskidDatabase.h"
#import "Beskid/BeskidConfiguration.h"
#import "Beskid/BeskidRuntime.h"
#import "Core/ATProtoDIDDocumentFields.h"
#import "Core/ATURI.h"
#import "Core/DID.h"
#import "Identity/HandleResolver.h"
#import "PLC/DIDPLCResolver.h"
#import "Network/GZXrpcRouteSupport.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Network/XrpcErrorHelper.h"

@implementation BeskidXrpcRoutePack {
    BeskidDatabase *_database;
}

- (instancetype)initWithDatabase:(BeskidDatabase *)database {
    self = [super init];
    if (!self) return nil;
    _database = database;
    return self;
}

- (void)registerRoutesWithServer:(HttpServer *)server {
    // com.atproto.* queries
    [server addRoute:@"GET" path:@"/xrpc/com.atproto.repo.getRecord" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleGetRecord:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/com.atproto.identity.resolveHandle" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleResolveHandle:request response:response];
    }];

    // slingshot-specific queries (custom / microcosms namespaces)
    [server addRoute:@"GET" path:@"/xrpc/com.bad-example.repo.getUriRecord" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleGetRecordByUri:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/blue.microcosm.repo.getRecordByUri" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleGetRecordByUri:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/com.bad-example.identity.resolveMiniDoc" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleResolveMiniDoc:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/blue.microcosm.identity.resolveMiniDoc" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleResolveMiniDoc:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/com.bad-example.identity.resolveService" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleResolveService:request response:response];
    }];
    [server addRoute:@"POST" path:@"/xrpc/com.bad-example.proxy.hydrateQueryResponse" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleHydrateResponse:request response:response];
    }];
}

#pragma mark - Helper Validation & Rate Limiting

- (BOOL)checkRateLimitForRequest:(HttpRequest *)request response:(HttpResponse *)response {
    return [GZXrpcRouteSupport checkIPRateLimitForRequest:request response:response];
}

- (nullable NSString *)requiredParam:(NSString *)name request:(HttpRequest *)request response:(HttpResponse *)response {
    return [GZXrpcRouteSupport requiredQueryParam:name request:request response:response];
}

#pragma mark - Route Handlers

- (void)handleGetRecord:(HttpRequest *)request response:(HttpResponse *)response {
    if (![self checkRateLimitForRequest:request response:response]) return;

    NSString *repo = [self requiredParam:@"repo" request:request response:response];
    NSString *collection = [self requiredParam:@"collection" request:request response:response];
    NSString *rkey = [self requiredParam:@"rkey" request:request response:response];
    if (!repo || !collection || !rkey) return;

    NSString *cid = [request queryParamForKey:@"cid"];

    // Resolve repo handle to DID if needed
    NSString *did = repo;
    if (![did hasPrefix:@"did:"]) {
        NSError *resolveError = nil;
        did = [self resolveIdentifierToDID:did biDirectional:YES error:&resolveError];
        if (did.length == 0) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RecordNotFound", @"message": @"Repository DID resolution failed"}];
            return;
        }
    }

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSError *error = nil;
    NSDictionary *record = [_database recordByURI:uri cid:cid error:&error];

    if (!record) {
        // Cache miss or expired: read-through to the originating PDS
        record = [self fetchAndCacheRemoteRecordForDID:did collection:collection rkey:rkey cid:cid];
    }

    if (!record) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"RecordNotFound", @"message": @"Record not found or expired"}];
        return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:record];
}

- (void)handleGetRecordByUri:(HttpRequest *)request response:(HttpResponse *)response {
    if (![self checkRateLimitForRequest:request response:response]) return;

    NSString *atURI = [self requiredParam:@"at_uri" request:request response:response];
    if (!atURI) return;
    NSString *cid = [request queryParamForKey:@"cid"];

    NSError *parseError = nil;
    ATURI *uri = [ATURI uriWithString:atURI error:&parseError];
    if (!uri || uri.collection.length == 0 || uri.rkey.length == 0) {
        [self writeInvalidRequest:parseError.localizedDescription ?: @"Invalid at_uri" response:response];
        return;
    }

    NSString *did = uri.did;
    if (![did hasPrefix:@"did:"]) {
        NSError *resolveError = nil;
        did = [self resolveIdentifierToDID:did biDirectional:YES error:&resolveError];
        if (did.length == 0) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RecordNotFound", @"message": @"Record not found"}];
            return;
        }
    }

    NSString *canonicalURI = [NSString stringWithFormat:@"at://%@/%@/%@", did, uri.collection, uri.rkey];
    NSError *error = nil;
    NSDictionary *record = [_database recordByURI:canonicalURI cid:cid error:&error];
    if (!record) {
        record = [self fetchAndCacheRemoteRecordForDID:did collection:uri.collection rkey:uri.rkey cid:cid];
    }

    if (!record) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"RecordNotFound", @"message": @"Record not found"}];
        return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:record];
}

- (void)handleResolveHandle:(HttpRequest *)request response:(HttpResponse *)response {
    if (![self checkRateLimitForRequest:request response:response]) return;

    NSString *handle = [self requiredParam:@"handle" request:request response:response];
    if (!handle) return;

    NSError *error = nil;
    NSString *did = [self resolveIdentifierToDID:handle biDirectional:YES error:&error];
    if (did.length == 0) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"HandleNotFound", @"message": error.localizedDescription ?: @"Failed to resolve handle"}];
        return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{@"did": did}];
}

- (void)handleResolveMiniDoc:(HttpRequest *)request response:(HttpResponse *)response {
    if (![self checkRateLimitForRequest:request response:response]) return;

    NSString *identifier = [self requiredParam:@"identifier" request:request response:response];
    if (!identifier) return;

    NSError *error = nil;
    NSString *did = [self resolveIdentifierToDID:identifier biDirectional:YES error:&error];
    if (did.length == 0) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"NotFound", @"message": error.localizedDescription ?: @"Identity not found"}];
        return;
    }

    NSDictionary *cachedIdentity = [_database identityForDID:did error:nil];
    if (cachedIdentity) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"did": cachedIdentity[@"did"] ?: did,
            @"handle": cachedIdentity[@"handle"] ?: @"",
            @"pds": cachedIdentity[@"pds"] ?: @"",
            @"signing_key": cachedIdentity[@"signing_key"] ?: @""
        }];
        return;
    }

    // Cache miss: resolve fresh DID document
    DIDDocument *doc = [[DIDResolver sharedResolver] resolveDIDSync:did error:&error];
    if (!doc) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"DidNotFound", @"message": error.localizedDescription ?: @"DID not found"}];
        return;
    }

    NSString *handle = [self handleFromDocument:doc] ?: [_database resolveDIDToHandle:did error:nil] ?: @"handle.invalid";
    NSString *pds = [self pdsEndpointFromDocument:doc] ?: @"";
    NSString *signingKey = [self signingKeyFromDocument:doc] ?: @"";

    // Cache with configured identity TTL
    NSTimeInterval ttl = [BeskidRuntime sharedRuntime].configuration.cacheIdentityTtlSeconds;
    [_database saveIdentity:did handle:handle pdsEndpoint:pds signingKey:signingKey rawDocument:doc.jsonDictionary ttl:ttl error:nil];

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{
        @"did": did,
        @"handle": handle,
        @"pds": pds,
        @"signing_key": signingKey
    }];
}

- (void)handleResolveService:(HttpRequest *)request response:(HttpResponse *)response {
    if (![self checkRateLimitForRequest:request response:response]) return;

    NSString *did = [self requiredParam:@"did" request:request response:response];
    NSString *serviceId = [self requiredParam:@"id" request:request response:response];
    if (!did || !serviceId) return;

    // Resolve DID Document
    NSError *error = nil;
    DIDDocument *doc = [[DIDResolver sharedResolver] resolveDIDSync:did error:&error];
    if (!doc) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"NotFound", @"message": error.localizedDescription ?: @"DID not found"}];
        return;
    }

    NSString *endpoint = nil;
    for (NSDictionary *service in doc.service ?: @[]) {
        if (![service isKindOfClass:[NSDictionary class]]) continue;
        NSString *sid = service[@"id"];
        if ([sid isEqualToString:serviceId]) {
            endpoint = service[@"serviceEndpoint"];
            break;
        }
    }

    if (endpoint.length == 0) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"ServiceNotFound", @"message": @"Requested service ID not found in DID document"}];
        return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{@"endpoint": endpoint}];
}

- (void)handleHydrateResponse:(HttpRequest *)request response:(HttpResponse *)response {
    if (![self checkRateLimitForRequest:request response:response]) return;

    NSData *bodyData = request.body;
    if (bodyData.length == 0) {
        [self writeInvalidRequest:@"Missing request body" response:response];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        [self writeInvalidRequest:@"Invalid JSON payload" response:response];
        return;
    }

    NSString *xrpc = payload[@"xrpc"];
    NSString *proxyService = payload[@"atproto_proxy"];
    NSArray *hydrationSources = payload[@"hydration_sources"];
    if (xrpc.length == 0 || proxyService.length == 0 || !hydrationSources) {
        [self writeInvalidRequest:@"xrpc, atproto_proxy, and hydration_sources are required fields" response:response];
        return;
    }

    // Resolve proxy service endpoint
    NSString *serviceEndpoint = nil;
    if ([proxyService hasPrefix:@"did:"]) {
        NSArray *parts = [proxyService componentsSeparatedByString:@"#"];
        NSString *baseDid = parts.firstObject;
        NSString *fragment = parts.count > 1 ? [@"#" stringByAppendingString:parts[1]] : @"";

        NSError *error = nil;
        DIDDocument *doc = [[DIDResolver sharedResolver] resolveDIDSync:baseDid error:&error];
        if (doc) {
            for (NSDictionary *service in doc.service ?: @[]) {
                if (fragment.length > 0) {
                    if ([service[@"id"] hasSuffix:fragment]) {
                        serviceEndpoint = service[@"serviceEndpoint"];
                        break;
                    }
                } else if ([service[@"type"] isEqualToString:@"AtprotoPersonalDataServer"]) {
                    serviceEndpoint = service[@"serviceEndpoint"];
                    break;
                }
            }
        }
    } else {
        serviceEndpoint = proxyService;
    }
    serviceEndpoint = [self effectivePDSEndpointForEndpoint:serviceEndpoint];

    if (serviceEndpoint.length == 0) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{@"error": @"InvalidProxy", @"message": @"Could not resolve proxy service endpoint"}];
        return;
    }

    // Construct forwarded URL request
    NSURLComponents *components = [NSURLComponents componentsWithString:serviceEndpoint];
    components.path = [NSString stringWithFormat:@"/xrpc/%@", xrpc];

    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
    NSDictionary *params = payload[@"params"];
    [params enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:[NSString stringWithFormat:@"%@", obj]]];
    }];
    components.queryItems = queryItems;

    NSMutableURLRequest *forwardReq = [NSMutableURLRequest requestWithURL:components.URL];
    forwardReq.HTTPMethod = @"GET";
    forwardReq.timeoutInterval = 5.0;

    NSString *auth = payload[@"authorization"];
    if (auth.length > 0) [forwardReq setValue:auth forHTTPHeaderField:@"Authorization"];

    // Send synchronous HTTP request to upstream service
    NSHTTPURLResponse *upstreamHttp = nil;
    NSError *networkError = nil;
    ATProtoSafeHTTPClientOptions *opts = [ATProtoSafeHTTPClientOptions defaultOptions];
    opts.allowHTTP = YES;
    opts.allowPrivateHosts = YES;

    NSData *resData = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:forwardReq
                                                                          options:opts
                                                                         response:&upstreamHttp
                                                                            error:&networkError];

    if (networkError || upstreamHttp.statusCode < 200 || upstreamHttp.statusCode >= 300 || resData.length == 0) {
        NSString *upstreamResponseBody = [[NSString alloc] initWithData:resData encoding:NSUTF8StringEncoding];
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"UpstreamFailure",
            @"message": networkError.localizedDescription ?: [NSString stringWithFormat:@"Upstream service request failed: %ld - %@", (long)upstreamHttp.statusCode, upstreamResponseBody]
        }];
        return;
    }

    id resJson = [NSJSONSerialization JSONObjectWithData:resData options:0 error:nil];
    if (!resJson) {
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{@"error": @"UpstreamInvalidJson", @"message": @"Upstream returned invalid JSON"}];
        return;
    }

    // Perform payload traversal & record extraction
    NSMutableSet<NSString *> *extractedUris = [NSMutableSet set];
    for (NSDictionary *source in hydrationSources) {
        if (![source isKindOfClass:[NSDictionary class]]) continue;
        NSString *path = source[@"path"];
        if (path.length > 0) {
            [self extractURIsFromJSON:resJson path:path collector:extractedUris];
        }
    }

    // Hydrate all extracted URIs using caching / read-through
    NSMutableDictionary *hydratedRecords = [NSMutableDictionary dictionary];
    for (NSString *uriStr in extractedUris) {
        NSError *parseError = nil;
        ATURI *uri = [ATURI uriWithString:uriStr error:&parseError];
        if (!uri || uri.collection.length == 0 || uri.rkey.length == 0) continue;

        NSString *did = uri.did;
        if (![did hasPrefix:@"did:"]) {
            did = [self resolveIdentifierToDID:did biDirectional:YES error:nil];
        }
        if (did.length == 0) continue;

        NSString *canonicalURI = [NSString stringWithFormat:@"at://%@/%@/%@", did, uri.collection, uri.rkey];
        NSDictionary *rec = [_database recordByURI:canonicalURI cid:nil error:nil];
        if (!rec) {
            rec = [self fetchAndCacheRemoteRecordForDID:did collection:uri.collection rkey:uri.rkey cid:nil];
        }

        if (rec) {
            hydratedRecords[uriStr] = @{
                @"status": @"found",
                @"uri": rec[@"uri"] ?: canonicalURI,
                @"cid": rec[@"cid"] ?: @"",
                @"value": rec[@"value"] ?: @{}
            };
        } else {
            hydratedRecords[uriStr] = @{
                @"status": @"error",
                @"reason": @"Could not resolve record"
            };
        }
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{
        @"output": resJson,
        @"records": hydratedRecords,
        @"identifiers": @{} // MiniDocs currently omitted from minimal hydration
    }];
}

#pragma mark - Core Logic Traversal & Verification helpers

- (void)extractURIsFromJSON:(id)json path:(NSString *)path collector:(NSMutableSet<NSString *> *)collector {
    NSArray *components = [path componentsSeparatedByString:@"."];
    [self extractRecursively:json pathComponents:components index:0 collector:collector];
}

- (void)extractRecursively:(id)current pathComponents:(NSArray *)components index:(NSUInteger)idx collector:(NSMutableSet<NSString *> *)collector {
    if (!current) return;
    if (idx >= components.count) {
        if ([current isKindOfClass:[NSString class]]) {
            [collector addObject:current];
        }
        return;
    }

    NSString *comp = components[idx];
    if ([comp hasSuffix:@"[]"]) {
        NSString *key = [comp substringToIndex:comp.length - 2];
        id array = key.length > 0 ? current[key] : current;
        if ([array isKindOfClass:[NSArray class]]) {
            for (id item in (NSArray *)array) {
                [self extractRecursively:item pathComponents:components index:idx + 1 collector:collector];
            }
        }
    } else {
        id next = current[comp];
        [self extractRecursively:next pathComponents:components index:idx + 1 collector:collector];
    }
}

- (nullable NSString *)resolveIdentifierToDID:(NSString *)identifier biDirectional:(BOOL)biDirectional error:(NSError **)error {
    if ([identifier hasPrefix:@"did:"]) return identifier;

    NSString *local = [_database resolveHandleToDID:[identifier lowercaseString] error:nil];
    if (local.length > 0) return local;

    __block NSString *resolved = nil;
    __block NSError *resolvedError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    HandleResolver *resolver = [[HandleResolver alloc] init];
    [resolver resolveHandle:[identifier lowercaseString] completion:^(NSString * _Nullable did, NSError * _Nullable handleError) {
        resolved = did;
        resolvedError = handleError;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    if (resolved.length == 0) {
        NSString *plcUrl = NSProcessInfo.processInfo.environment[@"PDS_PLC_URL"] ?: NSProcessInfo.processInfo.environment[@"PLC_URL"] ?: [DIDResolver sharedResolver].plcURL;
        if (plcUrl.length > 0 && ![plcUrl isEqualToString:@"mock"] && ![plcUrl isEqualToString:@"skip"]) {
            DIDPLCResolver *plcResolver = [[DIDPLCResolver alloc] initWithPlcUrl:plcUrl];
            plcResolver.timeout = 2.0;

            NSURL *listURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/_list", plcUrl]];
            NSURLRequest *listReq = [NSURLRequest requestWithURL:listURL
                                                     cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                 timeoutInterval:5.0];
            __block NSData *listData = nil;
            __block NSError *listError = nil;
            dispatch_semaphore_t listSem = dispatch_semaphore_create(0);
            [[[NSURLSession sharedSession] dataTaskWithRequest:listReq
                                            completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
                listData = data;
                listError = err;
                dispatch_semaphore_signal(listSem);
            }] resume];
            dispatch_semaphore_wait(listSem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

            if (listData && !listError) {
                NSArray *didsList = [NSJSONSerialization JSONObjectWithData:listData options:0 error:nil];
                if ([didsList isKindOfClass:[NSArray class]]) {
                    NSString *normalizedTarget = [identifier lowercaseString];
                    for (NSString *candidateDid in didsList) {
                        if (![candidateDid isKindOfClass:[NSString class]]) continue;
                        NSError *docError = nil;
                        NSDictionary *doc = [plcResolver resolveDID:candidateDid error:&docError];
                        if (!doc) continue;
                        NSArray *alsoKnownAs = doc[@"alsoKnownAs"];
                        if (![alsoKnownAs isKindOfClass:[NSArray class]]) continue;
                        for (NSString *aka in alsoKnownAs) {
                            if (![aka isKindOfClass:[NSString class]]) continue;
                            NSString *normalizedAka = aka;
                            if ([normalizedAka hasPrefix:@"at://"]) {
                                normalizedAka = [normalizedAka substringFromIndex:5];
                            }
                            if ([[normalizedAka lowercaseString] isEqualToString:normalizedTarget]) {
                                resolved = candidateDid;
                                break;
                            }
                        }
                        if (resolved.length > 0) break;
                    }
                }
            }
        }
    }

    if (resolved.length == 0) {
        if (error) *error = resolvedError ?: [NSError errorWithDomain:@"blue.microcosm.beskid" code:404 userInfo:@{NSLocalizedDescriptionKey: @"Handle resolution failed"}];
        return nil;
    }

    if (biDirectional) {
        NSError *docError = nil;
        DIDDocument *doc = [[DIDResolver sharedResolver] resolveDIDSync:resolved error:&docError];
        if (!doc) {
            if (error) *error = docError ?: [NSError errorWithDomain:@"blue.microcosm.beskid" code:404 userInfo:@{NSLocalizedDescriptionKey: @"DID Document resolution failed"}];
            return nil;
        }

        NSString *verifiedHandle = [self handleFromDocument:doc];
        if (!verifiedHandle || ![verifiedHandle isEqualToString:[identifier lowercaseString]]) {
            [_database saveHandle:identifier did:@"handle.invalid" error:nil];
            if (error) *error = [NSError errorWithDomain:@"blue.microcosm.beskid" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Bi-directional handle verification failed"}];
            return nil;
        }
    }

    [_database saveHandle:identifier did:resolved error:nil];
    return resolved;
}

- (nullable NSString *)handleFromDocument:(DIDDocument *)doc {
    return [ATProtoDIDDocumentFields normalizedHandleFromDocument:doc];
}

- (nullable NSString *)pdsEndpointFromDocument:(DIDDocument *)doc {
    return [ATProtoDIDDocumentFields pdsEndpointFromDocument:doc];
}

- (nullable NSString *)configuredPDSEndpointOverride {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *beskidOverride = env[@"BESKID_PDS_URL"];
    if (beskidOverride.length > 0) return beskidOverride;
    NSString *genericOverride = env[@"PDS_URL"];
    if (genericOverride.length > 0) return genericOverride;
    return nil;
}

- (BOOL)isLoopbackEndpoint:(NSString *)endpoint {
    NSURLComponents *components = [NSURLComponents componentsWithString:endpoint ?: @""];
    NSString *host = components.host.lowercaseString;
    if (host.length == 0) return NO;
    return [host isEqualToString:@"localhost"] ||
           [host isEqualToString:@"127.0.0.1"] ||
           [host isEqualToString:@"::1"];
}

- (nullable NSString *)effectivePDSEndpointForEndpoint:(nullable NSString *)endpoint {
    NSString *override = [self configuredPDSEndpointOverride];
    if (override.length > 0 && (endpoint.length == 0 || [self isLoopbackEndpoint:endpoint])) {
        return override;
    }
    return endpoint;
}

- (nullable NSString *)signingKeyFromDocument:(DIDDocument *)doc {
    return [ATProtoDIDDocumentFields atprotoSigningKeyMultibaseFromDocument:doc];
}

- (nullable NSDictionary *)fetchAndCacheRemoteRecordForDID:(NSString *)did
                                               collection:(NSString *)collection
                                                     rkey:(NSString *)rkey
                                                      cid:(nullable NSString *)cid {
    NSError *error = nil;
    DIDDocument *doc = [[DIDResolver sharedResolver] resolveDIDSync:did error:&error];
    NSString *endpoint = [self effectivePDSEndpointForEndpoint:(doc ? [self pdsEndpointFromDocument:doc] : nil)];
    if (endpoint.length == 0) return nil;

    NSURLComponents *components = [NSURLComponents componentsWithString:endpoint];
    if (!components.host) return nil;
    NSString *basePath = components.path ?: @"";
    if (basePath.length == 0 || [basePath isEqualToString:@"/"]) {
        components.path = @"/xrpc/com.atproto.repo.getRecord";
    } else {
        components.path = [[basePath stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] stringByAppendingPathComponent:@"xrpc/com.atproto.repo.getRecord"];
    }

    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithArray:@[
        [NSURLQueryItem queryItemWithName:@"repo" value:did],
        [NSURLQueryItem queryItemWithName:@"collection" value:collection],
        [NSURLQueryItem queryItemWithName:@"rkey" value:rkey]
    ]];
    if (cid.length > 0) [items addObject:[NSURLQueryItem queryItemWithName:@"cid" value:cid]];
    components.queryItems = items;
    NSURL *url = components.URL;
    if (!url) return nil;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 5.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    ATProtoSafeHTTPClientOptions *options = [ATProtoSafeHTTPClientOptions defaultOptions];
    options.allowHTTP = YES;
    options.allowPrivateHosts = YES;

    NSHTTPURLResponse *http = nil;
    NSError *fetchError = nil;
    NSData *data = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:req
                                                                        options:options
                                                                       response:&http
                                                                          error:&fetchError];

    if (fetchError || http.statusCode < 200 || http.statusCode >= 300 || data.length == 0) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;

    // Cache the record with configured record TTL
    NSDictionary *recValue = json[@"value"];
    NSString *recCid = json[@"cid"] ?: cid;
    NSTimeInterval ttl = [BeskidRuntime sharedRuntime].configuration.cacheRecordTtlSeconds;

    if (recValue && recCid.length > 0) {
        NSError *saveError = nil;
        BOOL saved = [_database saveRecord:recValue did:did collection:collection rkey:rkey cid:recCid ttl:ttl error:&saveError];
        if (!saved) {
            NSLog(@"[Beskid ERROR] Failed to save record to cache: %@", saveError);
        } else {
            NSLog(@"[Beskid] Saved record to cache: at://%@/%@/%@", did, collection, rkey);
        }
    } else {
        NSLog(@"[Beskid ERROR] Missing recValue or recCid! recCid = %@", recCid);
    }

    return json;
}

- (void)writeInvalidRequest:(NSString *)message response:(HttpResponse *)response {
    [XrpcErrorHelper setInvalidRequestError:response message:message ?: @"Invalid request"];
}

@end
