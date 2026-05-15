// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Constellation/ConstellationXrpcRoutePack.h"
#import "Constellation/ConstellationDatabase.h"
#import "Constellation/ConstellationSourceSpec.h"
#import "Core/ATURI.h"
#import "Core/DID.h"
#import "Identity/HandleResolver.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation ConstellationXrpcRoutePack {
    ConstellationDatabase *_database;
}

- (instancetype)initWithDatabase:(ConstellationDatabase *)database {
    self = [super init];
    if (!self) return nil;
    _database = database;
    return self;
}

- (void)registerRoutesWithServer:(HttpServer *)server {
    [server addRoute:@"GET" path:@"/xrpc/blue.microcosm.links.getBacklinks" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleGetBacklinks:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/blue.microcosm.links.getBacklinkDids" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleGetBacklinkDids:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/blue.microcosm.links.getBacklinksCount" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleGetBacklinksCount:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/blue.microcosm.links.getManyToMany" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleGetManyToMany:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/blue.microcosm.links.getManyToManyCounts" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleGetManyToManyCounts:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/blue.microcosm.identity.resolveMiniDoc" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleResolveMiniDoc:request response:response];
    }];
    [server addRoute:@"GET" path:@"/xrpc/blue.microcosm.repo.getRecordByUri" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleGetRecordByUri:request response:response];
    }];
}

- (void)handleGetBacklinks:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *subject = [self requiredParam:@"subject" request:request response:response];
    ConstellationSourceSpec *source = [self sourceFromRequest:request response:response];
    if (!subject || !source) return;

    NSInteger limit = 16;
    if (![self parseLimitFromRequest:request defaultLimit:16 output:&limit response:response]) return;

    NSString *next = nil;
    NSInteger total = 0;
    NSError *error = nil;
    NSArray *records = [_database backlinkRecordsForSubject:subject
                                                     source:source
                                                 didFilters:[self stringArrayParam:@"did" request:request]
                                                      limit:limit
                                                     cursor:[request queryParamForKey:@"cursor"]
                                                 nextCursor:&next
                                                      total:&total
                                                      error:&error];
    if (!records) {
        [self writeDatabaseError:error response:response];
        return;
    }
    NSMutableDictionary *body = [@{@"total": @(total), @"records": records} mutableCopy];
    if (next.length > 0) body[@"cursor"] = next;
    response.statusCode = HttpStatusOK;
    [response setJsonBody:body];
}

- (void)handleGetBacklinkDids:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *subject = [self requiredParam:@"subject" request:request response:response];
    ConstellationSourceSpec *source = [self sourceFromRequest:request response:response];
    if (!subject || !source) return;

    NSInteger limit = 16;
    if (![self parseLimitFromRequest:request defaultLimit:16 output:&limit response:response]) return;

    NSString *next = nil;
    NSInteger total = 0;
    NSError *error = nil;
    NSArray *dids = [_database backlinkDIDsForSubject:subject
                                               source:source
                                                limit:limit
                                               cursor:[request queryParamForKey:@"cursor"]
                                           nextCursor:&next
                                                total:&total
                                                error:&error];
    if (!dids) {
        [self writeDatabaseError:error response:response];
        return;
    }
    NSMutableDictionary *body = [@{@"total": @(total), @"linking_dids": dids} mutableCopy];
    if (next.length > 0) body[@"cursor"] = next;
    response.statusCode = HttpStatusOK;
    [response setJsonBody:body];
}

- (void)handleGetBacklinksCount:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *subject = [self requiredParam:@"subject" request:request response:response];
    ConstellationSourceSpec *source = [self sourceFromRequest:request response:response];
    if (!subject || !source) return;

    NSError *error = nil;
    NSInteger total = [_database backlinksCountForSubject:subject source:source error:&error];
    if (total < 0) {
        [self writeDatabaseError:error response:response];
        return;
    }
    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{@"total": @(total)}];
}

- (void)handleGetManyToMany:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *subject = [self requiredParam:@"subject" request:request response:response];
    ConstellationSourceSpec *source = [self sourceFromRequest:request response:response];
    NSString *pathToOther = [self requiredParam:@"pathToOther" request:request response:response];
    if (!subject || !source || !pathToOther) return;
    if (![self validatePath:pathToOther response:response]) return;

    NSInteger limit = 16;
    if (![self parseLimitFromRequest:request defaultLimit:16 output:&limit response:response]) return;

    NSString *next = nil;
    NSError *error = nil;
    NSArray *linkDIDs = [self combinedStringArrayParams:@[@"linkDid", @"did"] request:request];
    NSArray *items = [_database manyToManyItemsForSubject:subject
                                                   source:source
                                              pathToOther:pathToOther
                                                 linkDIDs:linkDIDs
                                            otherSubjects:[self stringArrayParam:@"otherSubject" request:request]
                                                    limit:limit
                                                   cursor:[request queryParamForKey:@"cursor"]
                                               nextCursor:&next
                                                    error:&error];
    if (!items) {
        [self writeDatabaseError:error response:response];
        return;
    }
    NSMutableDictionary *body = [@{@"items": items} mutableCopy];
    if (next.length > 0) body[@"cursor"] = next;
    response.statusCode = HttpStatusOK;
    [response setJsonBody:body];
}

- (void)handleGetManyToManyCounts:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *subject = [self requiredParam:@"subject" request:request response:response];
    ConstellationSourceSpec *source = [self sourceFromRequest:request response:response];
    NSString *pathToOther = [self requiredParam:@"pathToOther" request:request response:response];
    if (!subject || !source || !pathToOther) return;
    if (![self validatePath:pathToOther response:response]) return;

    NSInteger limit = 16;
    if (![self parseLimitFromRequest:request defaultLimit:16 output:&limit response:response]) return;

    NSString *next = nil;
    NSError *error = nil;
    NSArray *counts = [_database manyToManyCountsForSubject:subject
                                                     source:source
                                                pathToOther:pathToOther
                                                       dids:[self stringArrayParam:@"did" request:request]
                                              otherSubjects:[self stringArrayParam:@"otherSubject" request:request]
                                                      limit:limit
                                                     cursor:[request queryParamForKey:@"cursor"]
                                                 nextCursor:&next
                                                      error:&error];
    if (!counts) {
        [self writeDatabaseError:error response:response];
        return;
    }
    NSMutableDictionary *body = [@{@"counts_by_other_subject": counts} mutableCopy];
    if (next.length > 0) body[@"cursor"] = next;
    response.statusCode = HttpStatusOK;
    [response setJsonBody:body];
}

- (void)handleResolveMiniDoc:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *identifier = [self requiredParam:@"identifier" request:request response:response];
    if (!identifier) return;

    NSError *error = nil;
    NSString *did = [self resolveIdentifierToDID:identifier error:&error];
    if (did.length == 0) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"NotFound", @"message": error.localizedDescription ?: @"Identity not found"}];
        return;
    }

    DIDDocument *doc = [[DIDResolver sharedResolver] resolveDIDSync:did error:&error];
    if (!doc) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"DidNotFound", @"message": error.localizedDescription ?: @"DID not found"}];
        return;
    }

    NSString *handle = [self handleFromDocument:doc] ?: [_database resolveDIDToHandle:did error:nil] ?: @"handle.invalid";
    NSString *pds = [self pdsEndpointFromDocument:doc] ?: @"";
    NSString *signingKey = [self signingKeyFromDocument:doc] ?: @"";
    [_database saveHandle:handle did:did error:nil];

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{
        @"did": did,
        @"handle": handle,
        @"pds": pds,
        @"signing_key": signingKey
    }];
}

- (void)handleGetRecordByUri:(HttpRequest *)request response:(HttpResponse *)response {
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
        did = [self resolveIdentifierToDID:did error:&resolveError];
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
        record = [self fetchRemoteRecordForDID:did collection:uri.collection rkey:uri.rkey cid:cid];
    }

    if (!record) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"RecordNotFound", @"message": @"Record not found"}];
        return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:record];
}

#pragma mark - Helpers

- (NSString *)requiredParam:(NSString *)name request:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *value = [request queryParamForKey:name];
    if (value.length == 0) {
        [self writeInvalidRequest:[NSString stringWithFormat:@"%@ parameter is required", name] response:response];
        return nil;
    }
    return value;
}

- (ConstellationSourceSpec *)sourceFromRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *sourceValue = [self requiredParam:@"source" request:request response:response];
    if (!sourceValue) return nil;
    NSError *error = nil;
    ConstellationSourceSpec *source = [ConstellationSourceSpec sourceSpecWithString:sourceValue error:&error];
    if (!source) {
        [self writeInvalidRequest:error.localizedDescription ?: @"Invalid source" response:response];
        return nil;
    }
    return source;
}

- (BOOL)validatePath:(NSString *)path response:(HttpResponse *)response {
    NSError *error = nil;
    if (![ConstellationSourceSpec validatePath:path error:&error]) {
        [self writeInvalidRequest:error.localizedDescription ?: @"Invalid path" response:response];
        return NO;
    }
    return YES;
}

- (BOOL)parseLimitFromRequest:(HttpRequest *)request
                 defaultLimit:(NSInteger)defaultLimit
                       output:(NSInteger *)output
                     response:(HttpResponse *)response {
    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = defaultLimit;
    if (limitParam.length > 0) {
        NSScanner *scanner = [NSScanner scannerWithString:limitParam];
        scanner.charactersToBeSkipped = nil;
        if (![scanner scanInteger:&limit] || !scanner.isAtEnd || limit < 1 || limit > 100) {
            [self writeInvalidRequest:@"limit must be an integer between 1 and 100" response:response];
            return NO;
        }
    }
    if (output) *output = limit;
    return YES;
}

- (NSArray<NSString *> *)stringArrayParam:(NSString *)name request:(HttpRequest *)request {
    NSArray<NSString *> *raw = [request queryParamsForKey:name] ?: @[];
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *entry in raw) {
        if (![entry isKindOfClass:[NSString class]]) continue;
        NSArray<NSString *> *parts = [entry componentsSeparatedByString:@","];
        for (NSString *part in parts) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length == 0 || [seen containsObject:trimmed]) continue;
            [seen addObject:trimmed];
            [values addObject:trimmed];
        }
    }
    return [values copy];
}

- (NSArray<NSString *> *)combinedStringArrayParams:(NSArray<NSString *> *)names request:(HttpRequest *)request {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *name in names) {
        for (NSString *value in [self stringArrayParam:name request:request]) {
            if ([seen containsObject:value]) continue;
            [seen addObject:value];
            [values addObject:value];
        }
    }
    return [values copy];
}

- (NSString *)resolveIdentifierToDID:(NSString *)identifier error:(NSError **)error {
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
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    if (resolved.length > 0) {
        [_database saveHandle:identifier did:resolved error:nil];
        return resolved;
    }
    if (error) *error = resolvedError ?: [NSError errorWithDomain:@"blue.microcosm.identity"
                                                             code:404
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Identifier not found"}];
    return nil;
}

- (nullable NSString *)handleFromDocument:(DIDDocument *)doc {
    for (NSString *aka in doc.alsoKnownAs ?: @[]) {
        if (![aka isKindOfClass:[NSString class]]) continue;
        NSString *candidate = aka;
        if ([candidate hasPrefix:@"at://"]) candidate = [candidate substringFromIndex:5];
        if ([candidate hasSuffix:@"/"]) candidate = [candidate substringToIndex:candidate.length - 1];
        if (candidate.length > 0) return [candidate lowercaseString];
    }
    return nil;
}

- (nullable NSString *)pdsEndpointFromDocument:(DIDDocument *)doc {
    for (NSDictionary *service in doc.service ?: @[]) {
        if (![service isKindOfClass:[NSDictionary class]]) continue;
        if (![service[@"type"] isEqualToString:@"AtprotoPersonalDataServer"]) continue;
        NSString *endpoint = service[@"serviceEndpoint"];
        if (endpoint.length > 0) return endpoint;
    }
    return nil;
}

- (nullable NSString *)signingKeyFromDocument:(DIDDocument *)doc {
    id verificationMethods = doc.jsonDictionary[@"verificationMethod"];
    if ([verificationMethods isKindOfClass:[NSArray class]]) {
        NSString *fallback = nil;
        for (NSDictionary *method in (NSArray *)verificationMethods) {
            if (![method isKindOfClass:[NSDictionary class]]) continue;
            NSString *key = method[@"publicKeyMultibase"];
            if (key.length == 0) continue;
            NSString *methodId = method[@"id"];
            if ([methodId hasSuffix:@"#atproto"]) return key;
            if (!fallback) fallback = key;
        }
        if (fallback.length > 0) return fallback;
    }

    id legacyMethods = doc.jsonDictionary[@"verificationMethods"];
    if ([legacyMethods isKindOfClass:[NSDictionary class]]) {
        NSString *atproto = legacyMethods[@"atproto"];
        if (atproto.length > 0) return atproto;
    }
    return nil;
}

- (nullable NSDictionary *)fetchRemoteRecordForDID:(NSString *)did
                                       collection:(NSString *)collection
                                             rkey:(NSString *)rkey
                                              cid:(nullable NSString *)cid {
    NSError *error = nil;
    DIDDocument *doc = [[DIDResolver sharedResolver] resolveDIDSync:did error:&error];
    NSString *endpoint = doc ? [self pdsEndpointFromDocument:doc] : nil;
    if (endpoint.length == 0) return nil;

    NSURLComponents *components = [NSURLComponents componentsWithString:endpoint];
    if (!components.host) return nil;
    NSString *basePath = components.path ?: @"";
    if (basePath.length == 0 || [basePath isEqualToString:@"/"]) {
        components.path = @"/xrpc/com.atproto.repo.getRecord";
    } else if ([basePath hasSuffix:@"/"]) {
        components.path = [basePath stringByAppendingString:@"xrpc/com.atproto.repo.getRecord"];
    } else {
        components.path = [basePath stringByAppendingString:@"/xrpc/com.atproto.repo.getRecord"];
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

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 10.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __block NSData *data = nil;
    __block NSHTTPURLResponse *http = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                     completionHandler:^(NSData *body, NSURLResponse *response, NSError *fetchError) {
        data = body;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) http = (NSHTTPURLResponse *)response;
        dispatch_semaphore_signal(semaphore);
    }] resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    if (http.statusCode < 200 || http.statusCode >= 300 || data.length == 0) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (void)writeInvalidRequest:(NSString *)message response:(HttpResponse *)response {
    response.statusCode = HttpStatusBadRequest;
    [response setJsonBody:@{@"error": @"InvalidRequest", @"message": message ?: @"Invalid request"}];
}

- (void)writeDatabaseError:(NSError *)error response:(HttpResponse *)response {
    if ([error.domain isEqualToString:ConstellationDatabaseErrorDomain] && error.code == 400) {
        [self writeInvalidRequest:error.localizedDescription response:response];
        return;
    }
    response.statusCode = HttpStatusInternalServerError;
    [response setJsonBody:@{@"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Database error"}];
}

@end
