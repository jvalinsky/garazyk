#import "Network/XrpcMethodRegistry.h"
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "App/Services/PDSAccountService.h"
#import "App/Services/PDSRecordService.h"
#import "Admin/PDSAdminController.h"
#import "Admin/PDSAdminAuth.h"
#import "Blob/BlobStorage.h"
#import "Database/ActorStore/ActorStore.h"
#import "Core/CID.h"
#import "Core/DID.h"
#import "Core/TID.h"
#import "Core/ATProtoValidator.h"
#import "Identity/HandleResolver.h"
#import "AppView/ActorService.h"
#import "AppView/FeedService.h"
#import "AppView/NotificationService.h"
#import "Auth/JWT.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Auth/OAuth2.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "App/PDSConfiguration.h"
#import "Security/PDSAuthzManager.h"
#import "App/Services/PDSBlobService.h"
#import "App/Services/PDSRepositoryService.h"
#import "Services/PDSPhoneVerificationProvider.h"
#import "Repository/CAR.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Identity/ATProtoHandleValidator.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCRotationKeyManager.h"
#import "PLC/DIDPLCResolver.h"
#import "Email/PDSEmailProvider.h"
#import "Database/PDSDatabase.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import <CommonCrypto/CommonKeyDerivation.h>
#include <errno.h>

static NSString *const kServiceAuthLxmCreateAccount = @"com.atproto.server.createAccount";
static NSString *const kLexiconResolveErrorDomain = @"XrpcLexiconResolve";
static NSString *const kTempFetchLabelsDeprecationWarning =
    @"299 - \"com.atproto.temp.fetchLabels is deprecated; use com.atproto.label.queryLabels or com.atproto.label.subscribeLabels\"";
static NSString *const kTempFetchLabelsSunsetDate = @"2027-12-31T00:00:00Z";
static NSString *const kTempFetchLabelsSuccessorLink =
    @"</xrpc/com.atproto.label.queryLabels>; rel=\"successor-version\", </xrpc/com.atproto.label.subscribeLabels>; rel=\"successor-version\"";

@interface JWT (Base64URL)
+ (nullable NSData *)base64URLDecode:(NSString *)string error:(NSError **)error;
@end

static NSDictionary *payloadDictionaryFromJWT(JWT *jwt, NSError **error) {
    NSData *payloadData = [JWT base64URLDecode:jwt.rawPayload error:error];
    if (!payloadData) return nil;
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:error];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT"
                                         code:JWTErrorDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWT payload JSON"}];
        }
        return nil;
    }
    return payload;
}

@interface XrpcMethodRegistry (AuthHelpers)
+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request;
+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request
                              response:(HttpResponse *)response;
+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             controller:(PDSController *)controller
                                request:(HttpRequest *)request
                               response:(HttpResponse *)response;
+ (void)storePlcOperationToken:(NSString *)token forDid:(NSString *)did;
+ (BOOL)validatePlcOperationToken:(NSString *)token forDid:(NSString *)did;
@end

static BOOL authorizeAdminRequest(HttpRequest *request, HttpResponse *response,
                                   PDSServiceDatabases *serviceDatabases,
                                   JWTMinter *jwtMinter,
                                   id<PDSAdminController> adminController) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader
                                                      jwtMinter:jwtMinter
                                                adminController:adminController
                                                        request:request];
    if (!did) {
        if (response.statusCode == HttpStatusOK) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Admin authentication required"}];
        }
        return NO;
    }

    NSError *dbError = nil;
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:&dbError];
    if (!db) {
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{@"error": @"DatabaseUnavailable", @"message": dbError.localizedDescription ?: @"Failed to open service database"}];
        return NO;
    }

    PDSAdminAuth *adminAuth = [PDSAdminAuth sharedAuth];
    NSError *authError = nil;
    if (![adminAuth isAuthenticatedWithRequest:request.headers]) {
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Admin privileges required (valid admin token)"}];
        return NO;
    }
    
    return YES;
}

static NSString *didWebIdentifierFromIssuer(NSString *issuer, NSString *fallbackHost) {
    NSURLComponents *components = [NSURLComponents componentsWithString:issuer];
    NSString *scheme = [components.scheme.lowercaseString copy];
    NSString *host = [components.host.lowercaseString copy];
    if (host.length == 0) {
        host = [fallbackHost.lowercaseString copy];
    }
    if (host.length == 0) {
        host = @"localhost";
    }

    NSUInteger port = components.port != nil ? (NSUInteger)MAX((NSInteger)0, components.port.integerValue) : 0;
    BOOL includePort = NO;
    if (port > 0) {
        BOOL defaultPort = ([scheme isEqualToString:@"https"] && port == 443) ||
                           ([scheme isEqualToString:@"http"] && port == 80);
        includePort = !defaultPort;
    }

    if (includePort) {
        return [NSString stringWithFormat:@"did:web:%@%%3A%lu", host, (unsigned long)port];
    }
    return [NSString stringWithFormat:@"did:web:%@", host];
}

static NSArray<NSString *> *serviceAuthExpectedAudiences(PDSConfiguration *config) {
    NSString *issuer = [config canonicalIssuerWithPortHint:0];
    NSString *canonicalHost = [config canonicalHostname];
    NSMutableOrderedSet<NSString *> *audiences = [NSMutableOrderedSet orderedSet];
    [audiences addObject:didWebIdentifierFromIssuer(issuer, canonicalHost)];
    if (canonicalHost.length > 0) {
        [audiences addObject:[NSString stringWithFormat:@"did:web:%@", canonicalHost]];
    }
    return audiences.array;
}

static NSArray<NSString *> *jwtAllowedAlgorithmsForMinter(JWTMinter *minter) {
    if (!minter) {
        return nil;
    }

    NSMutableOrderedSet<NSString *> *algorithms = [NSMutableOrderedSet orderedSet];
    NSString *configuredAlgorithm = [[minter.signingAlgorithm stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if (configuredAlgorithm.length > 0) {
        [algorithms addObject:configuredAlgorithm];
    }

    if (minter.keyManager) {
        [algorithms addObjectsFromArray:@[@"ES256", @"RS256"]];
    }

    if (algorithms.count == 0 && minter.publicKey) {
        [algorithms addObject:@"ES256K"];
    }

    return algorithms.count > 0 ? algorithms.array : nil;
}

// Implementation of resolveDid
static NSDictionary *resolveDid(NSString *did, PDSServiceDatabases *dbs, PDSConfiguration *config, NSError **error) {
    fprintf(stderr, "[resolveDid] Resolving DID: %s\n", did.UTF8String);
    PDSDatabaseAccount *account = [dbs getAccountByDid:did error:error];
    if (!account) {
        fprintf(stderr, "[resolveDid] Account not found for DID: %s\n", did.UTF8String);
        if (error && *error) {
            fprintf(stderr, "[resolveDid] DB Error: %s\n", (*error).description.UTF8String);
        }
        return nil;
    }
    fprintf(stderr, "[resolveDid] Found account handle: %s\n", account.handle.UTF8String);

    
    NSString *handle = account.handle;
    if (handle.length == 0) {
        if (error) {
           *error = [NSError errorWithDomain:@"com.atproto.identity" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Account has no handle"}];
        }
        return nil;
    }
    
    NSString *serviceEndpoint = [config canonicalIssuerWithPortHint:0];
    
    return @{
        @"@context": @[
            @"https://www.w3.org/ns/did/v1",
            @"https://w3id.org/security/multikey/v1",
            @"https://w3id.org/security/suites/secp256k1-2019/v1"
        ],
        @"id": did,
        @"alsoKnownAs": @[[@"at://" stringByAppendingString:handle]],
        @"verificationMethod": @[
            @{
                @"id": [NSString stringWithFormat:@"%@#atproto", did],
                @"type": @"Multikey",
                @"controller": did,
                @"publicKeyMultibase": @"zQ3sh...", // Placeholder
            }
        ],
        @"service": @[
            @{
                @"id": @"#atproto_pds",
                @"type": @"AtprotoPersonalDataServer",
                @"serviceEndpoint": serviceEndpoint
            }
        ]
    };
}

static NSDictionary *loadLexiconJSONForNSID(NSString *nsid,
                                            NSString *dataDirectory,
                                            NSError **error) {
    ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
    NSArray<NSString *> *searchPaths = [registry searchPathsForDirectory:dataDirectory];
    NSString *relativePath = [[nsid stringByReplacingOccurrencesOfString:@"." withString:@"/"] stringByAppendingString:@".json"];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    for (NSString *basePath in searchPaths) {
        NSString *candidate = [basePath stringByAppendingPathComponent:relativePath];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] || isDirectory) {
            continue;
        }

        NSError *readError = nil;
        NSData *data = [NSData dataWithContentsOfFile:candidate options:0 error:&readError];
        if (!data) {
            if (error) {
                *error = readError ?: [NSError errorWithDomain:kLexiconResolveErrorDomain
                                                           code:500
                                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to read lexicon file"}];
            }
            return nil;
        }

        NSError *parseError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (![json isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = parseError ?: [NSError errorWithDomain:kLexiconResolveErrorDomain
                                                            code:500
                                                        userInfo:@{NSLocalizedDescriptionKey: @"Lexicon JSON is not an object"}];
            }
            return nil;
        }

        return (NSDictionary *)json;
    }

    if (error) {
        *error = [NSError errorWithDomain:kLexiconResolveErrorDomain
                                     code:404
                                 userInfo:@{NSLocalizedDescriptionKey: @"Lexicon not found"}];
    }
    return nil;
}

static NSDictionary *resolveLexiconResponseForNSID(NSString *nsid,
                                                   PDSConfiguration *config,
                                                   NSError **error) {
    NSDictionary *schema = loadLexiconJSONForNSID(nsid, config.dataDirectory, error);
    if (!schema) {
        return nil;
    }

    NSError *cborError = nil;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:schema error:&cborError];
    if (!cborData) {
        if (error) {
            *error = cborError ?: [NSError errorWithDomain:kLexiconResolveErrorDomain
                                                      code:500
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode lexicon schema"}];
        }
        return nil;
    }

    CID *schemaCID = [CID cidWithDigest:[CID sha256Digest:cborData] codec:0x71];
    if (!schemaCID) {
        if (error) {
            *error = [NSError errorWithDomain:kLexiconResolveErrorDomain
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute lexicon CID"}];
        }
        return nil;
    }

    NSString *hostname = config.serverHost ?: @"localhost";
    NSString *serverDid = [NSString stringWithFormat:@"did:web:%@", hostname];
    NSString *uri = [NSString stringWithFormat:@"at://%@/com.atproto.lexicon.schema/%@", serverDid, nsid];

    return @{
        @"uri": uri,
        @"cid": schemaCID.stringValue ?: @"",
        @"schema": schema
    };
}

static NSString *trimmedNonEmptyString(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

static BOOL parseUnsignedLongLongString(NSString *value, unsigned long long *result) {
    NSString *trimmed = trimmedNonEmptyString(value);
    if (trimmed.length == 0) {
        return NO;
    }

    errno = 0;
    char *end = NULL;
    unsigned long long parsed = strtoull(trimmed.UTF8String, &end, 10);
    if (errno != 0 || !end || end == trimmed.UTF8String || *end != '\0') {
        return NO;
    }

    if (result) {
        *result = parsed;
    }
    return YES;
}

static BOOL isProxyHopByHopHeader(NSString *headerKey) {
    static NSSet<NSString *> *blocked = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blocked = [NSSet setWithArray:@[
            @"connection",
            @"keep-alive",
            @"proxy-authenticate",
            @"proxy-authorization",
            @"te",
            @"trailer",
            @"transfer-encoding",
            @"upgrade",
            @"host",
            @"content-length",
            @"atproto-proxy"
        ]];
    });
    return [blocked containsObject:headerKey.lowercaseString];
}

static BOOL serviceIdentifierMatchesFragment(NSString *serviceIdentifier,
                                             NSString *did,
                                             NSString *fragment) {
    NSString *normalizedIdentifier = serviceIdentifier.lowercaseString;
    NSString *normalizedFragment = fragment.lowercaseString;
    if (![normalizedFragment hasPrefix:@"#"]) {
        normalizedFragment = [@"#" stringByAppendingString:normalizedFragment];
    }

    if ([normalizedIdentifier isEqualToString:normalizedFragment]) {
        return YES;
    }
    if ([normalizedIdentifier hasSuffix:normalizedFragment]) {
        return YES;
    }

    NSString *fullyQualified = [[did.lowercaseString stringByAppendingString:normalizedFragment] lowercaseString];
    return [normalizedIdentifier isEqualToString:fullyQualified];
}

static NSDictionary *proxyServiceEntryFromDocument(DIDDocument *document,
                                                   NSString *did,
                                                   NSString *serviceFragment) {
    NSArray<NSDictionary *> *services = document.service ?: @[];
    if (services.count == 0) {
        return nil;
    }

    if (serviceFragment.length > 0) {
        for (NSDictionary *entry in services) {
            NSString *identifier = entry[@"id"];
            if ([identifier isKindOfClass:[NSString class]] &&
                serviceIdentifierMatchesFragment(identifier, did, serviceFragment)) {
                return entry;
            }
        }
        return nil;
    }

    for (NSDictionary *entry in services) {
        NSString *type = [entry[@"type"] lowercaseString];
        NSString *identifier = [entry[@"id"] lowercaseString];
        if (([type containsString:@"appview"] || [identifier containsString:@"appview"]) &&
            [entry[@"serviceEndpoint"] isKindOfClass:[NSString class]]) {
            return entry;
        }
    }

    for (NSDictionary *entry in services) {
        if ([entry[@"serviceEndpoint"] isKindOfClass:[NSString class]]) {
            return entry;
        }
    }

    return nil;
}

static NSURL *proxyBaseURLFromDescriptor(NSString *descriptor,
                                         PDSConfiguration *config,
                                         NSError **error) {
    NSString *trimmedDescriptor = trimmedNonEmptyString(descriptor);
    if (trimmedDescriptor.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"XrpcProxy"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Proxy target is empty"}];
        }
        return nil;
    }

    NSURL *directURL = [NSURL URLWithString:trimmedDescriptor];
    if (directURL.scheme.length > 0 && directURL.host.length > 0) {
        return directURL;
    }

    NSString *did = trimmedDescriptor;
    NSString *serviceFragment = nil;
    NSRange fragmentRange = [trimmedDescriptor rangeOfString:@"#"];
    if (fragmentRange.location != NSNotFound) {
        did = [trimmedDescriptor substringToIndex:fragmentRange.location];
        serviceFragment = [trimmedDescriptor substringFromIndex:fragmentRange.location + 1];
    }

    if (![did hasPrefix:@"did:"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"XrpcProxy"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Proxy target must be an absolute URL or DID reference"}];
        }
        return nil;
    }

    DIDResolver *resolver = [[DIDResolver alloc] init];
    if (config.plcURL.length > 0) {
        resolver.plcURL = config.plcURL;
    }

    NSError *resolveError = nil;
    DIDDocument *document = [resolver resolveDIDSync:did error:&resolveError];
    if (!document) {
        if (error) {
            *error = resolveError ?: [NSError errorWithDomain:@"XrpcProxy"
                                                         code:3
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to resolve proxy DID"}];
        }
        return nil;
    }

    NSDictionary *serviceEntry = proxyServiceEntryFromDocument(document, did, serviceFragment);
    if (!serviceEntry) {
        if (error) {
            NSString *message = serviceFragment.length > 0
                ? [NSString stringWithFormat:@"Service '#%@' was not found in DID document", serviceFragment]
                : @"No service endpoint found in DID document";
            *error = [NSError errorWithDomain:@"XrpcProxy"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    NSString *endpoint = trimmedNonEmptyString(serviceEntry[@"serviceEndpoint"]);
    NSURL *endpointURL = endpoint.length > 0 ? [NSURL URLWithString:endpoint] : nil;
    if (endpointURL.scheme.length == 0 || endpointURL.host.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"XrpcProxy"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Resolved service endpoint is not a valid absolute URL"}];
        }
        return nil;
    }
    return endpointURL;
}

static NSURL *proxyURLForMethodAndQuery(NSURL *baseURL,
                                        NSString *methodId,
                                        NSString *queryString) {
    NSURLComponents *components = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
    if (!components) {
        return nil;
    }

    NSString *path = components.path ?: @"";
    while (path.length > 1 && [path hasSuffix:@"/"]) {
        path = [path substringToIndex:path.length - 1];
    }

    NSString *methodPath = [NSString stringWithFormat:@"/xrpc/%@", methodId];
    if ([path hasSuffix:methodPath]) {
        // already points to this method path
    } else if ([path hasSuffix:@"/xrpc"]) {
        path = [path stringByAppendingFormat:@"/%@", methodId];
    } else if (path.length == 0 || [path isEqualToString:@"/"]) {
        path = methodPath;
    } else {
        path = [path stringByAppendingString:methodPath];
    }

    components.path = path;
    components.percentEncodedQuery = queryString.length > 0 ? queryString : nil;
    return components.URL;
}

static NSString *configuredAppViewProxyTarget(PDSConfiguration *config) {
    NSString *envTarget = trimmedNonEmptyString([[NSProcessInfo processInfo] environment][@"PDS_APPVIEW_URL"]);
    if (envTarget.length > 0) {
        return envTarget;
    }

    NSString *configTarget = trimmedNonEmptyString([config stringForKey:@"appview.url"]);
    if (configTarget.length > 0) {
        return configTarget;
    }

    return trimmedNonEmptyString([config stringForKey:@"app_view.url"]);
}

static BOOL proxyXrpcRequest(HttpRequest *request,
                             HttpResponse *response,
                             NSString *methodId,
                             NSString *proxyDescriptor,
                             PDSConfiguration *config,
                             BOOL explicitProxyHeader) {
    NSError *targetError = nil;
    NSURL *baseURL = proxyBaseURLFromDescriptor(proxyDescriptor, config, &targetError);
    if (!baseURL) {
        response.statusCode = explicitProxyHeader ? HttpStatusBadRequest : 502;
        [response setJsonBody:@{
            @"error": explicitProxyHeader ? @"InvalidAtprotoProxy" : @"AppViewProxyUnavailable",
            @"message": targetError.localizedDescription ?: @"Failed to resolve proxy target"
        }];
        return YES;
    }

    NSURL *targetURL = proxyURLForMethodAndQuery(baseURL, methodId, request.queryString ?: @"");
    if (!targetURL) {
        response.statusCode = explicitProxyHeader ? HttpStatusBadRequest : 502;
        [response setJsonBody:@{
            @"error": @"ProxyTargetInvalid",
            @"message": @"Failed to construct upstream URL"
        }];
        return YES;
    }

    NSInteger hopCount = [[request headerForKey:@"x-objpds-proxy-hop"] integerValue];
    if (hopCount >= 4) {
        response.statusCode = 502;
        [response setJsonBody:@{
            @"error": @"ProxyLoopDetected",
            @"message": @"Rejected proxy request after too many proxy hops"
        }];
        return YES;
    }

    NSMutableURLRequest *upstreamRequest = [NSMutableURLRequest requestWithURL:targetURL
                                                                    cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                                timeoutInterval:30.0];
    upstreamRequest.HTTPMethod = request.methodString ?: @"GET";
    if (request.body.length > 0 && request.method != HttpMethodGET && request.method != HttpMethodHEAD) {
        upstreamRequest.HTTPBody = request.body;
    }

    for (NSString *key in request.headers) {
        NSString *lowercaseKey = key.lowercaseString;
        if (isProxyHopByHopHeader(lowercaseKey)) {
            continue;
        }
        NSString *value = request.headers[key];
        if (![value isKindOfClass:[NSString class]] || value.length == 0) {
            continue;
        }
        [upstreamRequest setValue:value forHTTPHeaderField:key];
    }
    [upstreamRequest setValue:[NSString stringWithFormat:@"%ld", (long)(hopCount + 1)]
           forHTTPHeaderField:@"x-objpds-proxy-hop"];

    NSError *proxyError = nil;
    NSHTTPURLResponse *upstreamResponse = nil;
    NSData *upstreamBody = [NSURLConnection sendSynchronousRequest:upstreamRequest
                                                 returningResponse:&upstreamResponse
                                                             error:&proxyError];
    if (!upstreamResponse) {
        response.statusCode = 502;
        [response setJsonBody:@{
            @"error": @"ProxyRequestFailed",
            @"message": proxyError.localizedDescription ?: @"Upstream request failed"
        }];
        return YES;
    }

    response.statusCode = (HttpStatusCode)upstreamResponse.statusCode;
    response.contentType = nil;

    NSDictionary *upstreamHeaders = upstreamResponse.allHeaderFields ?: @{};
    for (id rawKey in upstreamHeaders) {
        NSString *key = [rawKey isKindOfClass:[NSString class]] ? (NSString *)rawKey : [rawKey description];
        NSString *value = [upstreamHeaders[rawKey] isKindOfClass:[NSString class]] ? upstreamHeaders[rawKey] : [upstreamHeaders[rawKey] description];
        if (key.length == 0 || value.length == 0) {
            continue;
        }

        NSString *lowercaseKey = key.lowercaseString;
        if ([lowercaseKey isEqualToString:@"content-type"]) {
            response.contentType = value;
            continue;
        }
        if (isProxyHopByHopHeader(lowercaseKey)) {
            continue;
        }
        [response setHeader:value forKey:key];
    }

    if (request.method != HttpMethodHEAD && upstreamBody.length > 0) {
        [response setBodyData:upstreamBody];
    } else if (request.method != HttpMethodHEAD && upstreamBody && upstreamBody.length == 0) {
        [response setBodyData:[NSData data]];
    }

    return YES;
}

static void installXrpcProxyInterceptor(XrpcDispatcher *dispatcher,
                                        PDSConfiguration *config) {
    dispatcher.requestInterceptor = ^BOOL(HttpRequest *request,
                                          HttpResponse *response,
                                          NSString *methodId,
                                          BOOL hasLocalHandler) {
        NSString *explicitProxyTarget = trimmedNonEmptyString([request headerForKey:@"atproto-proxy"]);
        if (explicitProxyTarget.length > 0) {
            return proxyXrpcRequest(request, response, methodId, explicitProxyTarget, config, YES);
        }

        if (hasLocalHandler || ![methodId hasPrefix:@"app.bsky."]) {
            return NO;
        }

        if ([[request headerForKey:@"x-objpds-proxy-hop"] integerValue] > 0) {
            return NO;
        }

        NSString *fallbackTarget = configuredAppViewProxyTarget(config);
        if (fallbackTarget.length == 0) {
            return NO;
        }

        return proxyXrpcRequest(request, response, methodId, fallbackTarget, config, NO);
    };
}

static BOOL parseByteRangeHeader(NSString *rangeHeader,
                                 unsigned long long totalLength,
                                 BOOL *hasRange,
                                 BOOL *satisfiable,
                                 unsigned long long *start,
                                 unsigned long long *end,
                                 NSString **failureReason) {
    if (hasRange) {
        *hasRange = NO;
    }
    if (satisfiable) {
        *satisfiable = YES;
    }
    if (start) {
        *start = 0;
    }
    if (end) {
        *end = totalLength > 0 ? (totalLength - 1) : 0;
    }
    if (failureReason) {
        *failureReason = nil;
    }

    NSString *trimmedRange = trimmedNonEmptyString(rangeHeader);
    if (trimmedRange.length == 0) {
        return YES;
    }

    if (hasRange) {
        *hasRange = YES;
    }

    if (![trimmedRange.lowercaseString hasPrefix:@"bytes="]) {
        if (failureReason) {
            *failureReason = @"Range header must use bytes units";
        }
        return NO;
    }

    NSString *spec = [trimmedRange substringFromIndex:6];
    if ([spec containsString:@","]) {
        if (failureReason) {
            *failureReason = @"Multiple ranges are not supported";
        }
        return NO;
    }

    NSRange dashRange = [spec rangeOfString:@"-"];
    if (dashRange.location == NSNotFound) {
        if (failureReason) {
            *failureReason = @"Range header is malformed";
        }
        return NO;
    }

    NSString *startPart = [spec substringToIndex:dashRange.location];
    NSString *endPart = [spec substringFromIndex:dashRange.location + 1];
    if (startPart.length == 0 && endPart.length == 0) {
        if (failureReason) {
            *failureReason = @"Range header is malformed";
        }
        return NO;
    }

    if (totalLength == 0) {
        if (satisfiable) {
            *satisfiable = NO;
        }
        return YES;
    }

    if (startPart.length > 0) {
        unsigned long long parsedStart = 0;
        if (!parseUnsignedLongLongString(startPart, &parsedStart)) {
            if (failureReason) {
                *failureReason = @"Range start is invalid";
            }
            return NO;
        }

        unsigned long long parsedEnd = totalLength - 1;
        if (endPart.length > 0) {
            if (!parseUnsignedLongLongString(endPart, &parsedEnd)) {
                if (failureReason) {
                    *failureReason = @"Range end is invalid";
                }
                return NO;
            }
        }

        if (parsedStart >= totalLength) {
            if (satisfiable) {
                *satisfiable = NO;
            }
            return YES;
        }
        if (parsedEnd < parsedStart) {
            if (satisfiable) {
                *satisfiable = NO;
            }
            return YES;
        }
        if (parsedEnd >= totalLength) {
            parsedEnd = totalLength - 1;
        }

        if (start) {
            *start = parsedStart;
        }
        if (end) {
            *end = parsedEnd;
        }
        return YES;
    }

    unsigned long long suffixLength = 0;
    if (!parseUnsignedLongLongString(endPart, &suffixLength) || suffixLength == 0) {
        if (satisfiable) {
            *satisfiable = NO;
        }
        return YES;
    }

    unsigned long long parsedStart = (suffixLength >= totalLength) ? 0 : (totalLength - suffixLength);
    if (start) {
        *start = parsedStart;
    }
    if (end) {
        *end = totalLength - 1;
    }
    return YES;
}

static HttpResponseBodyChunkProducer blobFileChunkProducer(NSString *path,
                                                           unsigned long long startOffset,
                                                           unsigned long long endOffset,
                                                           NSError **error) {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fileHandle) {
        if (error) {
            *error = [NSError errorWithDomain:@"XrpcBlobStream"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to open blob file for streaming"}];
        }
        return nil;
    }

    @try {
        [fileHandle seekToFileOffset:startOffset];
    } @catch (NSException *exception) {
        @try {
            [fileHandle closeFile];
        } @catch (__unused NSException *closeException) {
        }
        if (error) {
            *error = [NSError errorWithDomain:@"XrpcBlobStream"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Failed to seek blob file"}];
        }
        return nil;
    }

    __block NSFileHandle *capturedHandle = fileHandle;
    __block unsigned long long bytesRemaining = (endOffset >= startOffset) ? (endOffset - startOffset + 1) : 0;
    static const NSUInteger kBlobChunkSize = 64 * 1024;

    return ^NSData * _Nullable (NSError **producerError) {
        if (!capturedHandle || bytesRemaining == 0) {
            if (capturedHandle) {
                @try {
                    [capturedHandle closeFile];
                } @catch (__unused NSException *closeException) {
                }
                capturedHandle = nil;
            }
            return nil;
        }

        NSUInteger readLength = (NSUInteger)MIN((unsigned long long)kBlobChunkSize, bytesRemaining);
        NSData *chunk = [capturedHandle readDataOfLength:readLength];
        if (chunk.length == 0) {
            @try {
                [capturedHandle closeFile];
            } @catch (__unused NSException *closeException) {
            }
            capturedHandle = nil;
            if (producerError && bytesRemaining > 0) {
                *producerError = [NSError errorWithDomain:@"XrpcBlobStream"
                                                     code:3
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Unexpected end-of-file while streaming blob"}];
            }
            bytesRemaining = 0;
            return nil;
        }

        bytesRemaining -= (unsigned long long)chunk.length;
        if (bytesRemaining == 0) {
            @try {
                [capturedHandle closeFile];
            } @catch (__unused NSException *closeException) {
            }
            capturedHandle = nil;
        }

        return chunk;
    };
}

static void registerServerDescribeAndResolveLexiconMethods(XrpcDispatcher *dispatcher,
                                                           PDSConfiguration *config) {
    [dispatcher registerComAtprotoServerDescribeServer:^(HttpRequest *request, HttpResponse *response) {
        NSString *issuer = [config canonicalIssuerWithPortHint:0];
        NSString *hostname = [config canonicalHostname];
        NSString *serverDid = didWebIdentifierFromIssuer(issuer, hostname);
        NSArray *availableUserDomains = config.availableUserDomains ?: (hostname.length > 0 ? @[hostname] : @[]);

        NSDictionary *result = @{
            @"inviteCodeRequired": @(config.inviteCodeRequired),
            @"phoneVerificationRequired": @NO,
            @"availableUserDomains": availableUserDomains,
            @"links": @{
                @"privacyPolicy": config.privacyPolicyURL ?: @"",
                @"termsOfService": config.termsOfServiceURL ?: @""
            },
            @"did": serverDid,
            @"version": @"0.1.0"
        };

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoLexiconResolveLexicon:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *nsid = [request queryParamForKey:@"nsid"];
        if (nsid.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing nsid parameter"}];
            return;
        }

        NSError *nsidError = nil;
        if (![ATProtoValidator validateNSID:nsid error:&nsidError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": nsidError.localizedDescription ?: @"Invalid NSID"}];
            return;
        }

        NSError *resolveError = nil;
        NSDictionary *result = resolveLexiconResponseForNSID(nsid, config, &resolveError);
        if (!result) {
            if ([resolveError.domain isEqualToString:kLexiconResolveErrorDomain] && resolveError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"LexiconNotFound", @"message": resolveError.localizedDescription ?: @"Lexicon not found"}];
                return;
            }
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": resolveError.localizedDescription ?: @"Failed to resolve lexicon"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
}

static NSString *inviteAlphabet(void) {
    return @"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
}

static NSString *generateInviteCode(NSUInteger groupCount, NSUInteger groupLength) {
    NSString *alphabet = inviteAlphabet();
    NSMutableString *code = [NSMutableString string];
    for (NSUInteger groupIndex = 0; groupIndex < groupCount; groupIndex++) {
        if (groupIndex > 0) {
            [code appendString:@"-"];
        }
        for (NSUInteger i = 0; i < groupLength; i++) {
            unichar c = [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
            [code appendFormat:@"%C", c];
        }
    }
    return code;
}

static BOOL createInviteCodeInDatabase(PDSServiceDatabases *serviceDatabases,
                                       NSString *accountDid,
                                       NSInteger maxUses,
                                       NSString **outCode,
                                       NSError **error) {
    if (maxUses <= 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.server"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"useCount must be > 0"}];
        }
        return NO;
    }

    const NSUInteger kMaxAttempts = 10;
    NSError *lastError = nil;
    for (NSUInteger attempt = 0; attempt < kMaxAttempts; attempt++) {
        NSString *code = generateInviteCode(4, 5);
        NSError *createError = nil;
        if ([serviceDatabases createInviteCode:code forAccount:accountDid maxUses:maxUses error:&createError]) {
            if (outCode) {
                *outCode = code;
            }
            return YES;
        }
        lastError = createError;
    }

    if (error) {
        *error = lastError ?: [NSError errorWithDomain:@"com.atproto.server"
                                                 code:500
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to create invite code"}];
    }
    return NO;
}

static void setSubscribeReposUpgradeRequired(HttpRequest *request, HttpResponse *response) {
    if (request.method != HttpMethodGET) {
        response.statusCode = HttpStatusMethodNotAllowed;
        [response setHeader:@"GET" forKey:@"Allow"];
        [response setJsonBody:@{
            @"error": @"MethodNotAllowed",
            @"message": @"subscribeRepos only supports GET"
        }];
        return;
    }

    response.statusCode = 426;
    [response setHeader:@"websocket" forKey:@"Upgrade"];
    [response setHeader:@"Upgrade" forKey:@"Connection"];
    [response setJsonBody:@{
        @"error": @"UpgradeRequired",
        @"message": @"WebSocket upgrade required for subscribeRepos"
    }];
    response.keepAlive = NO;
}

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

static BOOL isLikelyEmail(NSString *email) {
    if (![email isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSRange atRange = [email rangeOfString:@"@"];
    if (atRange.location == NSNotFound || atRange.location == 0 || atRange.location == email.length - 1) {
        return NO;
    }
    NSString *domain = [email substringFromIndex:atRange.location + 1];
    return [domain containsString:@"."];
}

static BOOL isLikelyPhoneNumber(NSString *phoneNumber) {
    if (![phoneNumber isKindOfClass:[NSString class]]) {
        return NO;
    }

    NSString *trimmed = [phoneNumber stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 7 || trimmed.length > 32) {
        return NO;
    }

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789 -()."];
    NSCharacterSet *disallowed = [allowed invertedSet];
    if ([trimmed rangeOfCharacterFromSet:disallowed].location != NSNotFound) {
        return NO;
    }

    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSUInteger digitCount = 0;
    for (NSUInteger index = 0; index < trimmed.length; index += 1) {
        unichar character = [trimmed characterAtIndex:index];
        if ([digits characterIsMember:character]) {
            digitCount += 1;
        }
    }
    return digitCount >= 7;
}

static NSDictionary<NSString *, NSString *> *scopeReferenceMap(void) {
    static NSDictionary<NSString *, NSString *> *mapping = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mapping = @{
            @"com.atproto.transition:generic": @"atproto transition:generic",
            @"com.atproto.transition:email": @"atproto transition:email",
            @"com.atproto.transition:chat.bsky": @"atproto transition:generic transition:chat.bsky"
        };
    });
    return mapping;
}

static BOOL parseStrictIntegerString(NSString *value, NSInteger *outValue) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    NSInteger parsed = 0;
    if (![scanner scanInteger:&parsed] || !scanner.isAtEnd) {
        return NO;
    }
    if (outValue) {
        *outValue = parsed;
    }
    return YES;
}

static BOOL isReservedHandle(NSString *normalizedHandle,
                             PDSServiceDatabases *serviceDatabases,
                             NSError **error) {
    if (normalizedHandle.length == 0) {
        return NO;
    }
    return [serviceDatabases isHandleReserved:normalizedHandle error:error];
}

static BOOL reserveHandle(NSString *normalizedHandle,
                          PDSServiceDatabases *serviceDatabases,
                          NSError **error) {
    if (normalizedHandle.length == 0) {
        return NO;
    }
    return [serviceDatabases reserveHandle:normalizedHandle error:error];
}

static NSArray<NSDictionary *> *buildHandleAvailabilitySuggestions(NSString *normalizedHandle,
                                                                   PDSServiceDatabases *serviceDatabases) {
    NSArray<NSString *> *parts = [normalizedHandle componentsSeparatedByString:@"."];
    if (parts.count < 2) {
        return @[];
    }

    NSString *stem = parts.firstObject.length > 0 ? parts.firstObject : @"user";
    NSString *domain = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"."];
    NSMutableArray<NSDictionary *> *suggestions = [NSMutableArray array];

    for (NSInteger suffix = 1; suffix <= 25 && suggestions.count < 3; suffix += 1) {
        NSString *candidate = [NSString stringWithFormat:@"%@%ld.%@", stem, (long)suffix, domain];
        NSError *handleError = nil;
        if (![ATProtoHandleValidator validateHandle:candidate error:&handleError]) {
            continue;
        }
        NSError *reservedError = nil;
        if (isReservedHandle(candidate, serviceDatabases, &reservedError) || reservedError) {
            continue;
        }
        if ([serviceDatabases getAccountByHandle:candidate error:nil]) {
            continue;
        }
        [suggestions addObject:@{
            @"handle": candidate,
            @"method": @"numeric-suffix"
        }];
    }

    return suggestions;
}

static NSArray<NSDictionary *> *loadFetchedLabels(PDSServiceDatabases *serviceDatabases,
                                                  BOOL hasSince,
                                                  NSInteger sinceSeconds,
                                                  NSInteger limit,
                                                  NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return nil;
    }

    NSArray<NSDictionary *> *rows = nil;
    if (hasSince) {
        rows = [db executeParameterizedQuery:@"SELECT src, uri, cid, val, neg, cts, exp FROM labels "
                                         "WHERE CAST(COALESCE(strftime('%s', cts), '0') AS INTEGER) >= ? "
                                         "ORDER BY id ASC LIMIT ?"
                                      params:@[@(sinceSeconds), @(limit)]
                                       error:error];
    } else {
        rows = [db executeParameterizedQuery:@"SELECT src, uri, cid, val, neg, cts, exp FROM labels "
                                         "ORDER BY id ASC LIMIT ?"
                                      params:@[@(limit)]
                                       error:error];
    }

    [db close];
    return rows;
}

static BOOL resolveAccountIdentifierToDid(PDSServiceDatabases *serviceDatabases,
                                          NSString *accountIdentifier,
                                          NSString **outDid,
                                          NSError **error) {
    if (![accountIdentifier isKindOfClass:[NSString class]] || accountIdentifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.temp"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing account identifier"}];
        }
        return NO;
    }

    PDSDatabaseAccount *account = nil;
    NSError *lookupError = nil;
    if ([ATProtoValidator validateDID:accountIdentifier error:nil]) {
        account = [serviceDatabases getAccountByDid:accountIdentifier error:&lookupError];
    } else if ([ATProtoHandleValidator validateHandle:accountIdentifier error:nil]) {
        account = [serviceDatabases getAccountByHandle:accountIdentifier error:&lookupError];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.temp"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid account identifier"}];
        }
        return NO;
    }

    if (!account) {
        if (error) {
            *error = lookupError ?: [NSError errorWithDomain:@"com.atproto.temp"
                                                        code:404
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    if (outDid) {
        *outDid = account.did;
    }
    return YES;
}

static void setSubscribeLabelsUpgradeRequired(HttpRequest *request, HttpResponse *response) {
    if (request.method != HttpMethodGET) {
        response.statusCode = HttpStatusMethodNotAllowed;
        [response setHeader:@"GET" forKey:@"Allow"];
        [response setJsonBody:@{
            @"error": @"MethodNotAllowed",
            @"message": @"subscribeLabels only supports GET"
        }];
        return;
    }

    NSString *cursorString = [request queryParamForKey:@"cursor"];
    if (cursorString.length > 0) {
        NSInteger cursor = 0;
        if (!parseStrictIntegerString(cursorString, &cursor) || cursor < 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": @"Invalid cursor"
            }];
            return;
        }
    }

    response.statusCode = 426;
    [response setHeader:@"websocket" forKey:@"Upgrade"];
    [response setHeader:@"Upgrade" forKey:@"Connection"];
    [response setJsonBody:@{
        @"error": @"UpgradeRequired",
        @"message": @"WebSocket upgrade required for subscribeLabels"
    }];
    response.keepAlive = NO;
}

static NSString *currentISO8601String(void) {
    return [NSDateFormatter atproto_stringFromDate:[NSDate date]];
}

static NSString *iso8601StringFromUnixTimestamp(NSTimeInterval timestamp) {
    NSDate *date = timestamp > 0 ? [NSDate dateWithTimeIntervalSince1970:timestamp] : [NSDate date];
    return [NSDateFormatter atproto_stringFromDate:date];
}

static NSDictionary *adminAccountViewFromAccount(PDSDatabaseAccount *account) {
    NSMutableDictionary *view = [@{
        @"did": account.did ?: @"",
        @"handle": account.handle ?: @"",
        @"indexedAt": iso8601StringFromUnixTimestamp(account.createdAt)
    } mutableCopy];

    if (account.email.length > 0) {
        view[@"email"] = account.email;
    }

    return view;
}

static NSArray<NSString *> *queryArrayValues(HttpRequest *request, NSString *key) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSArray<NSString *> *pairs = [request.queryString componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        if (pair.length == 0) {
            continue;
        }
        NSRange eqRange = [pair rangeOfString:@"="];
        NSString *rawKey = eqRange.location == NSNotFound ? pair : [pair substringToIndex:eqRange.location];
        NSString *rawValue = eqRange.location == NSNotFound ? @"" : [pair substringFromIndex:eqRange.location + 1];

        NSString *decodedKey = [[rawKey stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding] ?: rawKey;
        if (![decodedKey isEqualToString:key]) {
            continue;
        }

        NSString *decodedValue = [[rawValue stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding] ?: rawValue;
        for (NSString *component in [decodedValue componentsSeparatedByString:@","]) {
            NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [values addObject:trimmed];
            }
        }
    }

    if (values.count == 0) {
        NSString *singleValue = [request queryParamForKey:key];
        for (NSString *component in [singleValue componentsSeparatedByString:@","]) {
            NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [values addObject:trimmed];
            }
        }
    }

    return values;
}

static NSDictionary *adminInviteCodeViewFromRow(NSDictionary *row) {
    NSString *code = [row[@"code"] isKindOfClass:[NSString class]] ? row[@"code"] : @"";
    NSString *accountDid = [row[@"account_did"] isKindOfClass:[NSString class]] ? row[@"account_did"] : @"";
    NSInteger uses = [row[@"uses"] respondsToSelector:@selector(integerValue)] ? [row[@"uses"] integerValue] : 0;
    NSInteger maxUses = [row[@"max_uses"] respondsToSelector:@selector(integerValue)] ? [row[@"max_uses"] integerValue] : 1;
    if (maxUses < 0) {
        maxUses = 0;
    }
    NSInteger available = maxUses - uses;
    if (available < 0) {
        available = 0;
    }
    BOOL disabled = [row[@"disabled"] respondsToSelector:@selector(boolValue)] ? [row[@"disabled"] boolValue] : NO;
    NSTimeInterval createdAt = [row[@"created_at"] respondsToSelector:@selector(doubleValue)] ? [row[@"created_at"] doubleValue] : 0;

    return @{
        @"code": code,
        @"available": @(available),
        @"disabled": @(disabled),
        @"forAccount": accountDid,
        @"createdBy": accountDid,
        @"createdAt": iso8601StringFromUnixTimestamp(createdAt),
        @"uses": @[]
    };
}

static NSArray<NSDictionary *> *loadAdminInviteCodeViews(PDSServiceDatabases *serviceDatabases,
                                                         NSString *sort,
                                                         NSInteger limit,
                                                         NSInteger offset,
                                                         NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return nil;
    }

    NSString *orderBy = [sort isEqualToString:@"usage"] ? @"uses DESC, created_at DESC, code ASC" : @"created_at DESC, code ASC";
    NSString *sql = [NSString stringWithFormat:
                     @"SELECT code, account_did, created_at, uses, max_uses, disabled "
                     @"FROM invite_codes ORDER BY %@ LIMIT ? OFFSET ?", orderBy];
    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:sql
                                                           params:@[@(limit), @(offset)]
                                                            error:error];
    [db close];
    if (!rows) {
        return nil;
    }

    NSMutableArray<NSDictionary *> *codes = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        [codes addObject:adminInviteCodeViewFromRow(row)];
    }
    return codes;
}

static NSArray<NSString *> *validatedUniqueStringArrayFromJSONValue(id value,
                                                                     NSString *fieldName,
                                                                     NSError **error) {
    if (!value) {
        return @[];
    }
    if (![value isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"%@ must be an array of strings", fieldName ?: @"field"]}];
        }
        return nil;
    }

    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id rawValue in (NSArray *)value) {
        if (![rawValue isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.admin"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"%@ must contain only strings", fieldName ?: @"field"]}];
            }
            return nil;
        }
        NSString *trimmed = [(NSString *)rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.admin"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"%@ cannot contain empty strings", fieldName ?: @"field"]}];
            }
            return nil;
        }
        if (![seen containsObject:trimmed]) {
            [seen addObject:trimmed];
            [values addObject:trimmed];
        }
    }

    return values;
}

static BOOL isNoSuchTableError(NSError *error) {
    if (!error) {
        return NO;
    }
    NSString *message = [error.localizedDescription lowercaseString];
    return [message containsString:@"no such table"];
}

static BOOL executeServiceUpdate(PDSDatabase *db,
                                 NSString *sql,
                                 NSArray *params,
                                 BOOL ignoreMissingTable,
                                 NSError **error) {
    NSError *updateError = nil;
    BOOL success = [db executeParameterizedUpdate:sql params:params error:&updateError];
    if (success || (ignoreMissingTable && isNoSuchTableError(updateError))) {
        return YES;
    }
    if (error) {
        *error = updateError ?: [NSError errorWithDomain:@"com.atproto.admin"
                                                    code:500
                                                userInfo:@{NSLocalizedDescriptionKey: @"Database update failed"}];
    }
    return NO;
}

static BOOL setInviteEnabledForAccount(PDSServiceDatabases *serviceDatabases,
                                       NSString *did,
                                       BOOL enabled,
                                       NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:error];
    if (!account) {
        [db close];
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    account.inviteEnabled = enabled;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL updated = [db updateAccount:account error:error];
    [db close];
    return updated;
}

static BOOL deleteAccountAsAdmin(PDSServiceDatabases *serviceDatabases,
                                 NSString *did,
                                 NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:error];
    if (!account) {
        [db close];
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    NSArray<NSString *> *cleanupSQL = @[
        @"DELETE FROM refresh_tokens WHERE account_did = ?",
        @"DELETE FROM app_passwords WHERE account_did = ?",
        @"DELETE FROM invite_codes WHERE account_did = ?",
        @"DELETE FROM passkeys WHERE account_did = ?"
    ];
    for (NSString *sql in cleanupSQL) {
        if (!executeServiceUpdate(db, sql, @[did], YES, error)) {
            [db close];
            return NO;
        }
    }

    BOOL deleted = [db deleteAccount:did error:error];
    [db close];
    return deleted;
}

static NSString *normalizedHostnameString(NSString *hostInput) {
    if (![hostInput isKindOfClass:[NSString class]]) {
        return @"localhost";
    }

    NSString *trimmed = [hostInput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @"localhost";
    }

    NSString *urlString = trimmed;
    if ([trimmed rangeOfString:@"://"].location == NSNotFound) {
        urlString = [@"https://" stringByAppendingString:trimmed];
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    NSString *hostname = components.host ?: trimmed;
    if ([[hostname lowercaseString] isEqualToString:@"0.0.0.0"]) {
        return @"localhost";
    }
    return [hostname lowercaseString];
}

static NSDictionary *localSyncHostEntry(PDSServiceDatabases *serviceDatabases, PDSConfiguration *config) {
    NSError *accountsError = nil;
    NSArray<PDSDatabaseAccount *> *accounts = [serviceDatabases getAllAccountsWithError:&accountsError];
    NSInteger accountCount = accounts ? (NSInteger)accounts.count : 0;
    return @{
        @"hostname": normalizedHostnameString(config.serverHost ?: @"localhost"),
        @"seq": @0,
        @"accountCount": @(MAX(accountCount, 0)),
        @"status": @"active"
    };
}

static NSData *pbkdf2HashPassword(NSString *password, NSData *salt, NSError **error) {
    const uint32_t iterations = 600000;
    const size_t derivedKeyLength = 32;
    unsigned char derivedKey[32];

    int result = CCKeyDerivationPBKDF(kCCPBKDF2,
                                      password.UTF8String,
                                      (size_t)password.length,
                                      salt.bytes,
                                      (size_t)salt.length,
                                      kCCPRFHmacAlgSHA256,
                                      iterations,
                                      derivedKey,
                                      derivedKeyLength);
    if (result != kCCSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.server"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive password hash"}];
        }
        return nil;
    }
    return [NSData dataWithBytes:derivedKey length:derivedKeyLength];
}

static NSString *normalizedAtHandleFromAlsoKnownAs(NSArray *alsoKnownAs) {
    if (![alsoKnownAs isKindOfClass:[NSArray class]]) {
        return nil;
    }

    for (id value in alsoKnownAs) {
        if (![value isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *candidate = (NSString *)value;
        if ([candidate hasPrefix:@"at://"]) {
            candidate = [candidate substringFromIndex:5];
        }
        if ([candidate hasSuffix:@"/"]) {
            candidate = [candidate substringToIndex:candidate.length - 1];
        }
        if (candidate.length > 0) {
            return [candidate lowercaseString];
        }
    }
    return nil;
}

static BOOL didDocumentContainsHandle(DIDDocument *doc, NSString *handle) {
    NSString *normalizedHandle = [handle lowercaseString];
    NSString *docHandle = normalizedAtHandleFromAlsoKnownAs(doc.alsoKnownAs);
    return docHandle.length > 0 && [docHandle isEqualToString:normalizedHandle];
}

static NSDictionary *defaultPdsServiceForConfig(PDSConfiguration *config) {
    NSString *serviceEndpoint = [config canonicalIssuerWithPortHint:0];
    return @{
        @"atproto_pds": @{
            @"type": @"AtprotoPersonalDataServer",
            @"endpoint": serviceEndpoint
        }
    };
}

static BOOL updateAccountEmail(PDSServiceDatabases *serviceDatabases,
                               NSString *did,
                               NSString *email,
                               NSError **error) {
    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        return NO;
    }
    account.email = email;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    return [serviceDatabases updateAccount:account error:error];
}

static BOOL updateAccountHandle(PDSServiceDatabases *serviceDatabases,
                                NSString *did,
                                NSString *handle,
                                NSError **error) {
    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        return NO;
    }
    account.handle = handle;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    return [serviceDatabases updateAccount:account error:error];
}

static NSData *generateAccountPasswordSalt(void) {
    NSMutableData *salt = [NSMutableData dataWithLength:32];
    uuid_t firstUUID;
    uuid_t secondUUID;
    [[NSUUID UUID] getUUIDBytes:firstUUID];
    [[NSUUID UUID] getUUIDBytes:secondUUID];
    [salt replaceBytesInRange:NSMakeRange(0, 16) withBytes:firstUUID];
    [salt replaceBytesInRange:NSMakeRange(16, 16) withBytes:secondUUID];
    return salt;
}

static BOOL updateAccountPassword(PDSServiceDatabases *serviceDatabases,
                                  NSString *did,
                                  NSString *password,
                                  NSError **error) {
    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    if (password.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing password"}];
        }
        return NO;
    }

    NSData *salt = account.passwordSalt;
    if (salt.length == 0) {
        salt = generateAccountPasswordSalt();
    }
    
    // ... code truncated ...
    



    NSError *hashError = nil;
    NSData *hash = pbkdf2HashPassword(password, salt, &hashError);
    if (!hash) {
        if (error) {
            *error = hashError ?: [NSError errorWithDomain:@"com.atproto.admin"
                                                      code:500
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Failed to hash password"}];
        }
        return NO;
    }

    account.passwordSalt = salt;
    account.passwordHash = hash;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    if (![serviceDatabases updateAccount:account error:error]) {
        return NO;
    }

    [serviceDatabases deleteRefreshTokensForAccount:did error:nil];
    return YES;
}

static BOOL updateAccountSigningKey(PDSServiceDatabases *serviceDatabases,
                                    NSString *did,
                                    NSString *signingKey,
                                    NSError **error) {
    if (![signingKey hasPrefix:@"did:key:"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"signingKey must be a did:key identifier"}];
        }
        return NO;
    }

    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    PDS_LOG_WARN(@"updateAccountSigningKey accepted but no DID document persistence is configured for DID %@ (signingKey=%@)", did, signingKey);
    return YES;
}

static void registerTempUtilityMethods(XrpcDispatcher *dispatcher,
                                       PDSServiceDatabases *serviceDatabases,
                                       JWTMinter *jwtMinter,
                                       id<PDSAdminController> adminController) {
    [dispatcher registerMethod:@"com.atproto.temp.addReservedHandle" handler:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *handle = body[@"handle"];
        NSError *handleError = nil;
        if (![ATProtoHandleValidator validateHandle:handle error:&handleError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidHandle", @"message": handleError.localizedDescription ?: @"Invalid handle"}];
            return;
        }

        NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];
        NSError *reserveError = nil;
        if (!reserveHandle(normalizedHandle, serviceDatabases, &reserveError)) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"PersistenceFailed", @"message": reserveError.localizedDescription ?: @"Failed to reserve handle"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:@"com.atproto.temp.checkHandleAvailability" handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *handle = [request queryParamForKey:@"handle"];
        NSError *handleError = nil;
        if (![ATProtoHandleValidator validateHandle:handle error:&handleError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": handleError.localizedDescription ?: @"Invalid handle"}];
            return;
        }
        NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];

        NSString *email = [request queryParamForKey:@"email"];
        if (email.length > 0 && !isLikelyEmail(email)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidEmail", @"message": @"Invalid email"}];
            return;
        }

        NSError *reservedError = nil;
        BOOL unavailable = ([serviceDatabases getAccountByHandle:normalizedHandle error:nil] != nil)
            || isReservedHandle(normalizedHandle, serviceDatabases, &reservedError);
        if (reservedError) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": reservedError.localizedDescription ?: @"Failed to check reserved handles"}];
            return;
        }

        NSDictionary *result = nil;
        if (unavailable) {
            NSArray<NSDictionary *> *suggestions = buildHandleAvailabilitySuggestions(normalizedHandle, serviceDatabases);
            result = @{@"suggestions": suggestions ?: @[]};
        } else {
            result = @{};
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"handle": normalizedHandle,
            @"result": result
        }];
    }];

    [dispatcher registerMethod:@"com.atproto.temp.checkSignupQueue" handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"activated": @YES}];
    }];

    [dispatcher registerMethod:@"com.atproto.temp.dereferenceScope" handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *scopeReference = [request queryParamForKey:@"scope"];
        if (![scopeReference isKindOfClass:[NSString class]] || scopeReference.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing scope"}];
            return;
        }
        if (![scopeReference hasPrefix:@"ref:"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidScopeReference", @"message": @"scope must start with ref:"}];
            return;
        }

        NSString *resolvedScope = [scopeReference substringFromIndex:4];
        if (resolvedScope.length == 0
            || [resolvedScope rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidScopeReference", @"message": @"Invalid scope reference"}];
            return;
        }

        NSString *mappedScope = scopeReferenceMap()[resolvedScope];
        if (![mappedScope isKindOfClass:[NSString class]] || mappedScope.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidScopeReference", @"message": @"Unknown scope reference"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"scope": mappedScope}];
    }];

    [dispatcher registerMethod:@"com.atproto.temp.fetchLabels" handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSInteger limit = 50;
        NSString *limitParam = [request queryParamForKey:@"limit"];
        if (limitParam.length > 0 && (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 250)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 250"}];
            return;
        }

        NSInteger sinceSeconds = 0;
        BOOL hasSince = NO;
        NSString *sinceParam = [request queryParamForKey:@"since"];
        if (sinceParam.length > 0) {
            hasSince = YES;
            if (!parseStrictIntegerString(sinceParam, &sinceSeconds) || sinceSeconds < 0) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"since must be a non-negative integer"}];
                return;
            }
        }

        NSError *queryError = nil;
        NSArray<NSDictionary *> *labels = loadFetchedLabels(serviceDatabases, hasSince, sinceSeconds, limit, &queryError);
        if (!labels) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": queryError.localizedDescription ?: @"Failed to fetch labels"}];
            return;
        }

        [response setHeader:@"true" forKey:@"Deprecation"];
        [response setHeader:kTempFetchLabelsSunsetDate forKey:@"Sunset"];
        [response setHeader:kTempFetchLabelsSuccessorLink forKey:@"Link"];
        [response setHeader:kTempFetchLabelsDeprecationWarning forKey:@"Warning"];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"labels": labels ?: @[]}];
    }];

    [dispatcher registerMethod:@"com.atproto.temp.requestPhoneVerification" handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *phoneNumber = body[@"phoneNumber"];
        if (!isLikelyPhoneNumber(phoneNumber)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid phoneNumber"}];
            return;
        }

        NSError *providerError = nil;
        NSString *providerName = [PDSConfiguration sharedConfiguration].phoneVerificationProvider ?: @"none";
        id<PDSPhoneVerificationProvider> provider = [PDSPhoneVerificationProviderFactory providerWithName:providerName
                                                                                                     error:&providerError];
        if (!provider) {
            if ([providerError.domain isEqualToString:PDSPhoneVerificationProviderErrorDomain]
                && providerError.code == PDSPhoneVerificationProviderErrorNotConfigured) {
                response.statusCode = HttpStatusNotImplemented;
                [response setJsonBody:@{
                    @"error": @"PhoneVerificationNotConfigured",
                    @"message": providerError.localizedDescription ?: @"Phone verification provider is not configured"
                }];
                return;
            }
            if ([providerError.domain isEqualToString:PDSPhoneVerificationProviderErrorDomain]
                && providerError.code == PDSPhoneVerificationProviderErrorUnsupportedProvider) {
                response.statusCode = HttpStatusNotImplemented;
                [response setJsonBody:@{
                    @"error": @"UnsupportedPhoneVerificationProvider",
                    @"message": providerError.localizedDescription ?: @"Unsupported phone verification provider"
                }];
                return;
            }

            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{
                @"error": @"PhoneVerificationProviderError",
                @"message": providerError.localizedDescription ?: @"Failed to initialize phone verification provider"
            }];
            return;
        }

        NSError *requestError = nil;
        if (![provider requestVerificationForPhoneNumber:phoneNumber error:&requestError]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{
                @"error": @"PhoneVerificationRequestFailed",
                @"message": requestError.localizedDescription ?: @"Failed to request phone verification"
            }];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

static void registerTempRevokeAccountCredentialsMethod(XrpcDispatcher *dispatcher,
                                                       PDSServiceDatabases *serviceDatabases,
                                                       JWTMinter *jwtMinter,
                                                       id<PDSAdminController> adminController) {
    [dispatcher registerComAtprotoTempRevokeAccountCredentials:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *accountIdentifier = body[@"account"];
        NSString *targetDid = nil;
        NSError *resolveError = nil;
        if (!resolveAccountIdentifierToDid(serviceDatabases, accountIdentifier, &targetDid, &resolveError)) {
            if (resolveError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": resolveError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": resolveError.localizedDescription ?: @"Invalid account identifier"}];
            }
            return;
        }

        if (![targetDid isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot revoke credentials for other accounts"}];
            return;
        }

        NSError *deleteError = nil;
        if (![serviceDatabases deleteRefreshTokensForAccount:targetDid error:&deleteError]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"CredentialRevocationFailed", @"message": deleteError.localizedDescription ?: @"Failed to revoke sessions"}];
            return;
        }

        NSError *listError = nil;
        NSArray<NSDictionary *> *appPasswords = [serviceDatabases listAppPasswordsForAccount:targetDid error:&listError];
        if (listError) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"CredentialRevocationFailed", @"message": listError.localizedDescription ?: @"Failed to list app passwords"}];
            return;
        }

        for (NSDictionary *entry in appPasswords) {
            NSString *name = entry[@"name"];
            if (name.length == 0) {
                continue;
            }

            NSError *revokeError = nil;
            BOOL revoked = [serviceDatabases revokeAppPasswordForAccount:targetDid name:name error:&revokeError];
            if (!revoked && revokeError) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"CredentialRevocationFailed", @"message": revokeError.localizedDescription ?: @"Failed to revoke app passwords"}];
                return;
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

static void registerAdminAccountMaintenanceMethods(XrpcDispatcher *dispatcher,
                                                   PDSServiceDatabases *serviceDatabases,
                                                   JWTMinter *jwtMinter,
                                                   id<PDSAdminController> adminController) {
    [dispatcher registerComAtprotoAdminSearchAccounts:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSInteger limit = 50;
        NSString *limitParam = [request queryParamForKey:@"limit"];
        if (limitParam.length > 0 && (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 100)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 100"}];
            return;
        }

        NSInteger offset = 0;
        NSString *cursorParam = [request queryParamForKey:@"cursor"];
        if (cursorParam.length > 0 && (!parseStrictIntegerString(cursorParam, &offset) || offset < 0)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"cursor must be a non-negative integer"}];
            return;
        }

        NSString *emailQuery = [[request queryParamForKey:@"email"] lowercaseString];
        NSError *queryError = nil;
        NSArray<PDSDatabaseAccount *> *allAccounts = [serviceDatabases getAllAccountsWithError:&queryError];
        if (!allAccounts) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": queryError.localizedDescription ?: @"Failed to query accounts"}];
            return;
        }

        NSMutableArray<PDSDatabaseAccount *> *filteredAccounts = [NSMutableArray arrayWithCapacity:allAccounts.count];
        for (PDSDatabaseAccount *account in allAccounts) {
            if (emailQuery.length > 0) {
                NSString *accountEmail = [account.email lowercaseString];
                if (accountEmail.length == 0 || [accountEmail rangeOfString:emailQuery].location == NSNotFound) {
                    continue;
                }
            }
            [filteredAccounts addObject:account];
        }

        NSUInteger startIndex = (NSUInteger)MIN(offset, (NSInteger)filteredAccounts.count);
        NSUInteger endIndex = MIN(startIndex + (NSUInteger)limit, filteredAccounts.count);
        NSMutableArray<NSDictionary *> *views = [NSMutableArray arrayWithCapacity:endIndex - startIndex];
        for (NSUInteger index = startIndex; index < endIndex; index += 1) {
            [views addObject:adminAccountViewFromAccount(filteredAccounts[index])];
        }

        NSMutableDictionary *result = [@{@"accounts": views} mutableCopy];
        if (endIndex < filteredAccounts.count) {
            result[@"cursor"] = [NSString stringWithFormat:@"%lu", (unsigned long)endIndex];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoAdminSendEmail:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *recipientDid = body[@"recipientDid"];
        NSString *senderDid = body[@"senderDid"];
        NSString *content = body[@"content"];
        NSString *subject = body[@"subject"];

        NSError *didError = nil;
        if (![recipientDid isKindOfClass:[NSString class]]
            || ![senderDid isKindOfClass:[NSString class]]
            || ![content isKindOfClass:[NSString class]]
            || content.length == 0
            || ![ATProtoValidator validateDID:recipientDid error:&didError]
            || ![ATProtoValidator validateDID:senderDid error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": didError.localizedDescription ?: @"Missing or invalid senderDid, recipientDid, or content"}];
            return;
        }

        if ([subject isKindOfClass:[NSString class]] && subject.length > 500) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"subject is too long"}];
            return;
        }

        NSError *lookupError = nil;
        PDSDatabaseAccount *recipientAccount = [serviceDatabases getAccountByDid:recipientDid error:&lookupError];
        if (!recipientAccount) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": lookupError.localizedDescription ?: @"Recipient account not found"}];
            return;
        }

        PDS_LOG_INFO(@"Admin sendEmail recipient=%@ sender=%@ subject=%@", recipientDid, senderDid, subject ?: @"");
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"sent": @YES}];
    }];

    [dispatcher registerComAtprotoAdminUpdateAccountEmail:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *accountIdentifier = body[@"account"];
        NSString *email = body[@"email"];
        if (email.length == 0 || !isLikelyEmail(email)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid email"}];
            return;
        }

        NSString *did = nil;
        NSError *resolveError = nil;
        if (!resolveAccountIdentifierToDid(serviceDatabases, accountIdentifier, &did, &resolveError)) {
            if (resolveError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": resolveError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": resolveError.localizedDescription ?: @"Invalid account identifier"}];
            }
            return;
        }

        NSError *existingError = nil;
        PDSDatabaseAccount *existingAccount = [serviceDatabases getAccountByEmail:email error:&existingError];
        if (existingAccount && ![existingAccount.did isEqualToString:did]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"EmailAlreadyInUse", @"message": @"Email is already used by another account"}];
            return;
        }

        NSError *updateError = nil;
        if (!updateAccountEmail(serviceDatabases, did, email, &updateError)) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"EmailUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to update email"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoAdminUpdateAccountHandle:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
        NSString *handle = body[@"handle"];

        NSError *didError = nil;
        if (![did isKindOfClass:[NSString class]] || ![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *handleError = nil;
        if (![ATProtoHandleValidator validateHandle:handle error:&handleError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidHandle", @"message": handleError.localizedDescription ?: @"Invalid handle"}];
            return;
        }
        NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];

        NSError *existingError = nil;
        PDSDatabaseAccount *existingAccount = [serviceDatabases getAccountByHandle:normalizedHandle error:&existingError];
        if (existingAccount && ![existingAccount.did isEqualToString:did]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"HandleAlreadyInUse", @"message": @"Handle is already used by another account"}];
            return;
        }

        NSError *updateError = nil;
        if (!updateAccountHandle(serviceDatabases, did, normalizedHandle, &updateError)) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"HandleUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to update handle"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoAdminUpdateAccountPassword:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
        NSString *password = body[@"password"];

        NSError *didError = nil;
        if (![did isKindOfClass:[NSString class]] || ![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }
        if (![password isKindOfClass:[NSString class]] || password.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing password"}];
            return;
        }

        NSError *updateError = nil;
        if (!updateAccountPassword(serviceDatabases, did, password, &updateError)) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"PasswordUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to update password"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoAdminUpdateAccountSigningKey:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
        NSString *signingKey = body[@"signingKey"];

        NSError *didError = nil;
        if (![did isKindOfClass:[NSString class]] || ![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        if (![signingKey isKindOfClass:[NSString class]]
            || ![signingKey hasPrefix:@"did:key:"]
            || signingKey.length <= @"did:key:".length) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"signingKey must be a did:key identifier"}];
            return;
        }

        NSError *updateError = nil;
        if (!updateAccountSigningKey(serviceDatabases, did, signingKey, &updateError)) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"SigningKeyUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to update signing key"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

static void registerAdminAccountAndInviteMethods(XrpcDispatcher *dispatcher,
                                                 PDSServiceDatabases *serviceDatabases,
                                                 JWTMinter *jwtMinter,
                                                 id<PDSAdminController> adminController) {
    [dispatcher registerComAtprotoAdminGetAccountInfo:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *did = [request queryParamForKey:@"did"];
        if (did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did parameter"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *error = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&error];
        if (!account) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": error.localizedDescription ?: @"Account not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:adminAccountViewFromAccount(account)];
    }];

    [dispatcher registerComAtprotoAdminGetAccountInfos:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSArray<NSString *> *dids = queryArrayValues(request, @"dids");
        if (dids.count == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing dids parameter"}];
            return;
        }

        NSMutableArray<NSDictionary *> *infos = [NSMutableArray arrayWithCapacity:dids.count];
        for (NSString *did in dids) {
            NSError *didError = nil;
            if (![ATProtoValidator validateDID:did error:&didError]) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
                return;
            }

            PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:nil];
            if (account) {
                [infos addObject:adminAccountViewFromAccount(account)];
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"infos": infos}];
    }];

    [dispatcher registerComAtprotoAdminGetInviteCodes:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *sort = [request queryParamForKey:@"sort"] ?: @"recent";
        if (![sort isEqualToString:@"recent"] && ![sort isEqualToString:@"usage"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"sort must be one of: recent, usage"}];
            return;
        }

        NSInteger limit = 100;
        NSString *limitParam = [request queryParamForKey:@"limit"];
        if (limitParam.length > 0 && (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 500)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 500"}];
            return;
        }

        NSInteger offset = 0;
        NSString *cursorParam = [request queryParamForKey:@"cursor"];
        if (cursorParam.length > 0 && (!parseStrictIntegerString(cursorParam, &offset) || offset < 0)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"cursor must be a non-negative integer"}];
            return;
        }

        NSError *error = nil;
        NSArray<NSDictionary *> *codes = loadAdminInviteCodeViews(serviceDatabases, sort, limit, offset, &error);
        if (!codes) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": error.localizedDescription ?: @"Failed to query invite codes"}];
            return;
        }

        NSMutableDictionary *result = [@{@"codes": codes} mutableCopy];
        if (codes.count == (NSUInteger)limit) {
            result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)(offset + (NSInteger)codes.count)];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoAdminDeleteAccount:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
        if (![did isKindOfClass:[NSString class]] || did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *deleteError = nil;
        if (!deleteAccountAsAdmin(serviceDatabases, did, &deleteError)) {
            if (deleteError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": deleteError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"AccountDeletionFailed", @"message": deleteError.localizedDescription ?: @"Failed to delete account"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoAdminDisableAccountInvites:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *accountDid = body[@"account"];
        if (![accountDid isKindOfClass:[NSString class]] || accountDid.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing account"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:accountDid error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *updateError = nil;
        if (!setInviteEnabledForAccount(serviceDatabases, accountDid, NO, &updateError)) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InviteUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to disable account invites"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoAdminEnableAccountInvites:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *accountDid = body[@"account"];
        if (![accountDid isKindOfClass:[NSString class]] || accountDid.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing account"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:accountDid error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *updateError = nil;
        if (!setInviteEnabledForAccount(serviceDatabases, accountDid, YES, &updateError)) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InviteUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to enable account invites"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoAdminDisableInviteCodes:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSError *validationError = nil;
        NSArray<NSString *> *codes = validatedUniqueStringArrayFromJSONValue(body[@"codes"], @"codes", &validationError);
        if (!codes) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": validationError.localizedDescription ?: @"Invalid codes"}];
            return;
        }
        NSArray<NSString *> *accounts = validatedUniqueStringArrayFromJSONValue(body[@"accounts"], @"accounts", &validationError);
        if (!accounts) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": validationError.localizedDescription ?: @"Invalid accounts"}];
            return;
        }

        NSError *disableError = nil;
        if (![adminController disableInviteCodesWithCodes:codes accounts:accounts error:&disableError]) {
            if (disableError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": disableError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InviteUpdateFailed", @"message": disableError.localizedDescription ?: @"Failed to disable invite codes"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

static NSDictionary *labelLookupParamsFromRequest(HttpRequest *request, NSString **errorMessage) {
    NSInteger limit = 50;
    NSString *limitParam = [request queryParamForKey:@"limit"];
    if (limitParam.length > 0 && (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 250)) {
        if (errorMessage) {
            *errorMessage = @"limit must be an integer between 1 and 250";
        }
        return nil;
    }

    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObject:@(limit) forKey:@"limit"];

    NSArray<NSString *> *uriPatterns = queryArrayValues(request, @"uriPatterns");
    if (uriPatterns.count > 0) {
        params[@"uriPatterns"] = uriPatterns;
    }

    NSArray<NSString *> *sources = queryArrayValues(request, @"sources");
    if (sources.count > 0) {
        params[@"sources"] = sources;
    }

    NSString *cursor = [request queryParamForKey:@"cursor"];
    if (cursor.length > 0) {
        params[@"cursor"] = cursor;
    }

    NSString *collection = [request queryParamForKey:@"collection"];
    if (collection.length > 0) {
        params[@"collection"] = collection;
    }

    NSString *since = [request queryParamForKey:@"since"];
    if (since.length > 0) {
        params[@"since"] = since;
    }

    return params;
}

static void registerAdminModerationAndLabelMethods(XrpcDispatcher *dispatcher,
                                                   PDSServiceDatabases *serviceDatabases,
                                                   JWTMinter *jwtMinter,
                                                   id<PDSAdminController> adminController,
                                                   BOOL enforceMethodChecks) {
    [dispatcher registerMethod:@"com.atproto.admin.takeDownAccount" handler:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (enforceMethodChecks && request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
        NSString *reason = body[@"reason"];
        if (![did isKindOfClass:[NSString class]] || did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [adminController takeDownAccount:did reason:[reason isKindOfClass:[NSString class]] ? reason : @"User deactivation" error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"TakedownFailed", @"message": error.localizedDescription ?: @"Failed to take down account"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoAdminModerateAccount:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (enforceMethodChecks && request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = [request.jsonBody isKindOfClass:[NSDictionary class]] ? request.jsonBody : nil;
        if (enforceMethodChecks && !body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }
        if (!body) {
            body = @{};
        }

        NSError *error = nil;
        NSDictionary *result = [adminController moderateAccount:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ModerationFailed", @"message": error.localizedDescription ?: @"Moderation failed"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoAdminModerateRecord:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (enforceMethodChecks && request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = [request.jsonBody isKindOfClass:[NSDictionary class]] ? request.jsonBody : nil;
        if (enforceMethodChecks && !body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }
        if (!body) {
            body = @{};
        }

        NSError *error = nil;
        NSDictionary *result = [adminController moderateRecord:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ModerationFailed", @"message": error.localizedDescription ?: @"Moderation failed"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoLabelCreateLabel:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (enforceMethodChecks && request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = [request.jsonBody isKindOfClass:[NSDictionary class]] ? request.jsonBody : nil;
        if (enforceMethodChecks && !body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }
        if (!body) {
            body = @{};
        }

        NSError *error = nil;
        NSDictionary *result = [adminController createLabel:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"LabelCreationFailed", @"message": error.localizedDescription ?: @"Failed to create label"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoLabelGetLabels:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (enforceMethodChecks && request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSDictionary *params = [request.jsonBody isKindOfClass:[NSDictionary class]] ? request.jsonBody : nil;
        if (!params || params.count == 0) {
            NSString *paramError = nil;
            params = labelLookupParamsFromRequest(request, &paramError);
            if (!params) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": paramError ?: @"Invalid query parameters"}];
                return;
            }
        }

        NSError *error = nil;
        NSDictionary *result = [adminController getLabels:params error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": error.localizedDescription ?: @"Failed to fetch labels"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoLabelSubscribeLabels:^(HttpRequest *request, HttpResponse *response) {
        setSubscribeLabelsUpgradeRequired(request, response);
    }];
}

static NSDictionary *resolveIdentityInfoForIdentifier(NSString *identifier,
                                                       PDSServiceDatabases *serviceDatabases,
                                                       NSString **errorName,
                                                       NSError **error) {
    if ([identifier hasPrefix:@"did:"]) {
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:identifier error:nil];
        if (account) {
            NSString *handle = account.handle.length > 0 ? [account.handle lowercaseString] : @"handle.invalid";
            NSDictionary *didDoc = @{
                @"id": account.did ?: identifier,
                @"alsoKnownAs": handle.length > 0 ? @[[NSString stringWithFormat:@"at://%@", handle]] : @[]
            };
            return @{
                @"did": account.did ?: identifier,
                @"handle": handle,
                @"didDoc": didDoc
            };
        }
    } else {
        PDSDatabaseAccount *account = [serviceDatabases getAccountByHandle:identifier error:nil];
        if (account) {
            NSString *handle = account.handle.length > 0 ? [account.handle lowercaseString] : @"handle.invalid";
            NSDictionary *didDoc = @{
                @"id": account.did ?: @"",
                @"alsoKnownAs": handle.length > 0 ? @[[NSString stringWithFormat:@"at://%@", handle]] : @[]
            };
            return @{
                @"did": account.did ?: @"",
                @"handle": handle,
                @"didDoc": didDoc
            };
        }
    }

    DIDResolver *didResolver = [[DIDResolver alloc] init];
    didResolver.plcURL = [PDSConfiguration sharedConfiguration].plcURL;

    if ([identifier hasPrefix:@"did:"]) {
        DIDDocument *doc = [didResolver resolveDIDSync:identifier error:error];
        if (!doc) {
            if (errorName) *errorName = @"DidNotFound";
            return nil;
        }
        NSString *handle = normalizedAtHandleFromAlsoKnownAs(doc.alsoKnownAs) ?: @"handle.invalid";
        return @{
            @"did": identifier,
            @"handle": handle,
            @"didDoc": doc.jsonDictionary ?: @{}
        };
    }

    HandleResolver *handleResolver = [[HandleResolver alloc] init];
    __block NSString *did = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [handleResolver resolveHandle:identifier completion:^(NSString * _Nullable resolvedDid, NSError * _Nullable resolveError) {
        did = resolvedDid;
        if (!did && resolveError && error && !*error) {
            *error = resolveError;
        }
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    if (did.length == 0) {
        if (errorName) *errorName = @"HandleNotFound";
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.identity"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Handle resolution failed"}];
        }
        return nil;
    }

    DIDDocument *doc = [didResolver resolveDIDSync:did error:error];
    if (!doc) {
        if (errorName) *errorName = @"DidNotFound";
        return nil;
    }

    NSString *resolvedHandle = didDocumentContainsHandle(doc, identifier) ? [identifier lowercaseString] : @"handle.invalid";
    return @{
        @"did": did,
        @"handle": resolvedHandle,
        @"didDoc": doc.jsonDictionary ?: @{}
    };
}

static void registerPhase1IdentityAndAccountMethods(XrpcDispatcher *dispatcher,
                                                     JWTMinter *jwtMinter,
                                                     id<PDSAdminController> adminController,
                                                     PDSServiceDatabases *serviceDatabases,
                                                     PDSDatabasePool *userDatabasePool,
                                                     PDSConfiguration *config,
                                                     id<PDSEmailProvider> emailProvider) {
    [dispatcher registerComAtprotoIdentityRefreshIdentity:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *identifier = body[@"identifier"] ?: [request queryParamForKey:@"identifier"];
        if (identifier.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing identifier"}];
            return;
        }

        NSError *error = nil;
        NSString *errorName = nil;
        NSDictionary *result = resolveIdentityInfoForIdentifier(identifier, serviceDatabases, &errorName, &error);
        if (!result) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": errorName ?: @"ResolutionFailed",
                @"message": error.localizedDescription ?: @"Failed to refresh identity"
            }];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoIdentityResolveHandle:^(HttpRequest *request, HttpResponse *response) {
        NSString *handle = [request queryParamForKey:@"handle"];
        if (handle.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing handle parameter"}];
            return;
        }

        PDSDatabaseAccount *account = [serviceDatabases getAccountByHandle:handle error:nil];
        if (account) {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"did": account.did}];
            return;
        }

        HandleResolver *handleResolver = [[HandleResolver alloc] init];
        __block NSString *resolvedDid = nil;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [handleResolver resolveHandle:handle completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            resolvedDid = did;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

        if (resolvedDid.length > 0) {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"did": resolvedDid}];
        } else {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Handle not found"}];
        }
    }];

    [dispatcher registerComAtprotoIdentityResolveIdentity:^(HttpRequest *request, HttpResponse *response) {
        NSString *identifier = [request queryParamForKey:@"identifier"];
        if (identifier.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing identifier parameter"}];
            return;
        }

        NSError *error = nil;
        NSString *errorName = nil;
        NSDictionary *result = resolveIdentityInfoForIdentifier(identifier, serviceDatabases, &errorName, &error);
        if (!result) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{
                @"error": errorName ?: @"NotFound",
                @"message": error.localizedDescription ?: @"Identity not found"
            }];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoIdentityGetRecommendedDidCredentials:^(HttpRequest *request, HttpResponse *response) {
        PDSConfiguration *configuration = config;
        NSString *issuer = [configuration canonicalIssuerWithPortHint:0];
        
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"rotationKeys"] = @[];
        result[@"alsoKnownAs"] = @[];
        result[@"verificationMethods"] = @{};
        result[@"services"] = @{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": issuer.length > 0 ? issuer : @""
            }
        };

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoIdentityRequestPlcOperationSignature:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:nil];
        if (!account) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": @"Account not found"}];
            return;
        }

        NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        NSMutableString *token = [NSMutableString stringWithCapacity:8];
        for (int i = 0; i < 8; i++) {
            [token appendFormat:@"%C", [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)]];
        }
        [XrpcMethodRegistry storePlcOperationToken:token forDid:did];
        PDS_LOG_INFO(@"Generated PLC operation token for DID %@", did);

        if (emailProvider && account.email.length > 0) {
            NSString *subject = @"PLC Operation Confirmation Code";
            NSString *body = [NSString stringWithFormat:@"Your confirmation code for updating your PLC identity is: %@\n\nIf you did not request this change, you can safely ignore this email.", token];
            
            NSError *emailError = nil;
            if (![emailProvider sendEmailTo:account.email subject:subject body:body error:&emailError]) {
                PDS_LOG_ERROR(@"Failed to send PLC operation email to %@: %@", account.email, emailError);
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"EmailFailed", @"message": @"Failed to send confirmation email"}];
                return;
            }
            
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{}];
        } else {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"token": token}];
        }
    }];

    [dispatcher registerComAtprotoIdentitySignPlcOperation:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *token = body[@"token"];
        if (![token isKindOfClass:[NSString class]] || token.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing token"}];
            return;
        }
        if (![XrpcMethodRegistry validatePlcOperationToken:token forDid:did]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid or expired token"}];
            return;
        }

        id rotationKeysValue = body[@"rotationKeys"];
        id alsoKnownAsValue = body[@"alsoKnownAs"];
        id verificationMethodsValue = body[@"verificationMethods"];
        id servicesValue = body[@"services"];

        NSError *storeError = nil;
        PDSActorStore *store = [userDatabasePool storeForDid:did error:&storeError];
        
        NSString *signingDidKey = nil;
        if (store) {
            NSError *keyError = nil;
            signingDidKey = [store didKeyStringWithError:&keyError];
        }

        if (!signingDidKey) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"KeyUnavailable", @"message": @"Unable to determine signing key for PLC operation"}];
            return;
        }

        PLCRotationKeyManager *keyManager = [PLCRotationKeyManager sharedManager];
        NSError *keyLoadError = nil;
        if (![keyManager loadOrGenerateKeyWithError:&keyLoadError]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"KeyUnavailable", @"message": keyLoadError.localizedDescription ?: @"Failed to load PLC rotation key"}];
            return;
        }
        NSString *serverRotationKey = keyManager.rotationKeyDidKey;

        NSArray *rotationKeys = [rotationKeysValue isKindOfClass:[NSArray class]] ? rotationKeysValue : nil;
        if (rotationKeys.count == 0) {
            rotationKeys = @[serverRotationKey];
        }

        NSDictionary *verificationMethods = [verificationMethodsValue isKindOfClass:[NSDictionary class]] ? verificationMethodsValue : nil;
        if (verificationMethods.count == 0) {
            verificationMethods = @{@"atproto": signingDidKey};
        }

        NSArray *alsoKnownAs = [alsoKnownAsValue isKindOfClass:[NSArray class]] ? alsoKnownAsValue : nil;
        if (alsoKnownAs.count == 0) {
            PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:nil];
            if (account.handle.length > 0) {
                alsoKnownAs = @[[NSString stringWithFormat:@"at://%@", account.handle]];
            } else {
                alsoKnownAs = @[];
            }
        }

        NSDictionary *services = [servicesValue isKindOfClass:[NSDictionary class]] ? servicesValue : nil;
        if (services.count == 0) {
            services = defaultPdsServiceForConfig(config);
        }
        if (!services) {
            services = @{};
        }

        id prev = [NSNull null];
        NSString *plcUrl = config.plcURL;
        if ([plcUrl isEqualToString:@"mock"] || plcUrl.length == 0) {
            plcUrl = @"http://127.0.0.1:2582";
        }
        
        DIDPLCResolver *plcResolver = [[DIDPLCResolver alloc] initWithPlcUrl:plcUrl];
        NSError *auditError = nil;
        NSArray *auditLog = [plcResolver resolveAuditLogForDID:did error:&auditError];
        
        if (auditLog && auditLog.count > 0) {
            NSMutableArray *ops = [NSMutableArray array];
            for (id opDict in auditLog) {
                if ([opDict isKindOfClass:[NSDictionary class]]) {
                    PLCOperation *op = [PLCOperation operationFromDictionary:opDict error:nil];
                    if (op) [ops addObject:op];
                }
            }
            
            if (ops.count > 0) {
                NSError *replayError = nil;
                PLCDIDState *state = [PLCStateReplayer replayHistory:ops error:&replayError];
                if (state && state.tombstoned) {
                    response.statusCode = HttpStatusBadRequest;
                    [response setJsonBody:@{@"error": @"AccountTombstoned", @"message": @"Cannot update tombstoned DID"}];
                    return;
                }
                
                PLCOperation *lastOp = ops.lastObject;
                if (lastOp) {
                    NSString *lastCid = [PLCOperation calculateCIDForOperation:[lastOp toDictionary] error:nil];
                    if (lastCid) {
                        prev = lastCid;
                    }
                }
            }
        }

        NSDictionary *operationData = @{
            @"type": @"plc_operation",
            @"rotationKeys": rotationKeys,
            @"verificationMethods": verificationMethods,
            @"alsoKnownAs": alsoKnownAs,
            @"services": services,
            @"prev": prev
        };

        NSError *cborError = nil;
        NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:operationData error:&cborError];
        if (!cborData) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": cborError.localizedDescription ?: @"Invalid PLC operation payload"}];
            return;
        }

        NSData *hash = [CID rawSha256:cborData];
        NSError *signError = nil;
        NSData *sig = nil;
        
        if (![keyManager signHash:hash result:&sig error:&signError]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"SigningFailed", @"message": signError.localizedDescription ?: @"Failed to sign PLC operation"}];
            return;
        }

        NSMutableDictionary *operation = [operationData mutableCopy];
        operation[@"did"] = did;
        operation[@"sig"] = [CryptoUtils base64URLEncode:sig];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"operation": operation}];
    }];

    [dispatcher registerComAtprotoIdentitySubmitPlcOperation:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSDictionary *operation = body[@"operation"];
        if (![operation isKindOfClass:[NSDictionary class]]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing operation"}];
            return;
        }

        NSString *operationDid = operation[@"did"];
        if (operationDid.length > 0 && ![operationDid isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Operation DID does not match authenticated account"}];
            return;
        }

        NSDictionary *opData = operation[@"data"] ?: operation;
        NSString *opType = opData[@"type"];
        if (![opType isEqualToString:@"plc_operation"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Operation must be type plc_operation"}];
            return;
        }

        PLCRotationKeyManager *keyManager = [PLCRotationKeyManager sharedManager];
        NSError *keyLoadError = nil;
        if (![keyManager loadOrGenerateKeyWithError:&keyLoadError]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"KeyUnavailable", @"message": @"Server rotation key not available"}];
            return;
        }
        NSString *serverRotationKey = keyManager.rotationKeyDidKey;

        NSArray *rotationKeys = opData[@"rotationKeys"];
        if (![rotationKeys isKindOfClass:[NSArray class]] || rotationKeys.count == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Operation must include rotationKeys"}];
            return;
        }
        if (![rotationKeys containsObject:serverRotationKey]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Server rotation key must be included in rotationKeys"}];
            return;
        }

        NSDictionary *services = opData[@"services"];
        if ([services isKindOfClass:[NSDictionary class]]) {
            NSDictionary *atprotoPds = services[@"atproto_pds"];
            if ([atprotoPds isKindOfClass:[NSDictionary class]]) {
                NSString *endpoint = atprotoPds[@"endpoint"];
                NSString *serviceType = atprotoPds[@"type"];
                if (![serviceType isEqualToString:@"AtprotoPersonalDataServer"]) {
                    response.statusCode = HttpStatusBadRequest;
                    [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"services.atproto_pds.type must be AtprotoPersonalDataServer"}];
                    return;
                }
                NSString *expectedEndpoint = config.canonicalIssuer;
                if (endpoint && ![endpoint isEqualToString:expectedEndpoint]) {
                    response.statusCode = HttpStatusBadRequest;
                    [response setJsonBody:@{@"error": @"InvalidRequest", @"message": [NSString stringWithFormat:@"services.atproto_pds.endpoint must match server URL %@", expectedEndpoint]}];
                    return;
                }
            }
        }

        NSArray *alsoKnownAs = opData[@"alsoKnownAs"];
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:nil];
        if (account.handle.length > 0) {
            NSString *expectedAka = [NSString stringWithFormat:@"at://%@", account.handle];
            if (![alsoKnownAs isKindOfClass:[NSArray class]] || ![alsoKnownAs containsObject:expectedAka]) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": [NSString stringWithFormat:@"alsoKnownAs must include %@", expectedAka]}];
                return;
            }
        }

        NSString *plcUrl = config.plcURL;
        if ([plcUrl isEqualToString:@"mock"] || plcUrl.length == 0) {
            plcUrl = @"http://127.0.0.1:2582";
        }

        DIDPLCResolver *plcResolver = [[DIDPLCResolver alloc] initWithPlcUrl:plcUrl];
        NSError *auditError = nil;
        NSArray *auditLog = [plcResolver resolveAuditLogForDID:did error:&auditError];

        if (auditLog && auditLog.count > 0) {
            NSMutableArray *ops = [NSMutableArray array];
            for (id opDict in auditLog) {
                if ([opDict isKindOfClass:[NSDictionary class]]) {
                    PLCOperation *op = [PLCOperation operationFromDictionary:opDict error:nil];
                    if (op) [ops addObject:op];
                }
            }
            if (ops.count > 0) {
                PLCOperation *lastOp = ops.lastObject;
                NSString *expectedPrev = [PLCOperation calculateCIDForOperation:[lastOp toDictionary] error:nil];
                id submittedPrev = opData[@"prev"];
                if (expectedPrev && submittedPrev != [NSNull null] && ![submittedPrev isEqualToString:expectedPrev]) {
                    response.statusCode = HttpStatusBadRequest;
                    [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"prev does not match last operation CID"}];
                    return;
                }
            }
        }

        NSMutableDictionary *opToSubmit = [operation mutableCopy];
        if (opToSubmit[@"did"]) {
            [opToSubmit removeObjectForKey:@"did"];
        }
        opToSubmit[@"did"] = did;

        if (config.debugSkipPlcOperations || [config.plcURL isEqualToString:@"mock"]) {
            PDS_LOG_INFO(@"Skipping PLC submission (mock mode) for DID %@", did);
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{}];
            return;
        }

        NSData *postData = [NSJSONSerialization dataWithJSONObject:opToSubmit options:0 error:&auditError];
        if (!postData) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": @"Failed to serialize operation"}];
            return;
        }

        NSURL *submitUrl = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", plcUrl, did]];
        NSMutableURLRequest *submitRequest = [NSMutableURLRequest requestWithURL:submitUrl];
        submitRequest.HTTPMethod = @"POST";
        [submitRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        submitRequest.HTTPBody = postData;

        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block NSInteger statusCode = 0;
        __block NSData *responseData = nil;
        __block NSError *submitError = nil;

        [[[NSURLSession sharedSession] dataTaskWithRequest:submitRequest completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;
            statusCode = httpResp.statusCode;
            responseData = data;
            submitError = err;
            dispatch_semaphore_signal(sema);
        }] resume];

        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

        if (submitError) {
            response.statusCode = HttpStatusServiceUnavailable;
            [response setJsonBody:@{@"error": @"UpstreamError", @"message": submitError.localizedDescription}];
            return;
        }

        if (statusCode != 200 && statusCode != 202) {
            NSString *bodyStr = responseData ? [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] : @"";
            response.statusCode = HttpStatusServiceUnavailable;
            [response setJsonBody:@{@"error": @"UpstreamError", @"message": [NSString stringWithFormat:@"PLC directory returned %ld: %@", (long)statusCode, bodyStr]}];
            return;
        }

        PDS_LOG_INFO(@"Submitted PLC operation for DID %@", did);

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoIdentityUpdateHandle:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *handle = body[@"handle"];
        if (handle.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing handle"}];
            return;
        }

        NSError *validateError = nil;
        if (![ATProtoHandleValidator validateHandle:handle error:&validateError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidHandle", @"message": validateError.localizedDescription ?: @"Invalid handle"}];
            return;
        }
        NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];

        NSError *error = nil;
        if (!updateAccountHandle(serviceDatabases, did, normalizedHandle, &error)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"HandleUpdateFailed", @"message": error.localizedDescription ?: @"Failed to update handle"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoServerGetAccountInviteCodes:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSError *error = nil;
        NSString *code = [serviceDatabases getInviteCodeForAccount:did error:&error];
        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InviteCodeLookupFailed", @"message": error.localizedDescription ?: @"Failed to load invite codes"}];
            return;
        }

        NSMutableArray<NSDictionary *> *codes = [NSMutableArray array];
        if (code.length > 0) {
            [codes addObject:@{
                @"code": code,
                @"available": @1,
                @"disabled": @NO,
                @"forAccount": did,
                @"createdBy": did,
                @"createdAt": currentISO8601String(),
                @"uses": @[]
            }];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"codes": codes}];
    }];

    [dispatcher registerComAtprotoServerRequestEmailConfirmation:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoServerRequestEmailUpdate:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"tokenRequired": @NO}];
    }];

    [dispatcher registerComAtprotoServerConfirmEmail:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *email = body[@"email"];
        NSString *token = body[@"token"];
        if (email.length == 0 || token.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing email or token"}];
            return;
        }

        NSError *accountError = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&accountError];
        if (!account) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": accountError.localizedDescription ?: @"Account not found"}];
            return;
        }

        if (!isLikelyEmail(email) || (account.email.length > 0 && ![[account.email lowercaseString] isEqualToString:[email lowercaseString]])) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidEmail", @"message": @"Provided email does not match account"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoServerRequestAccountDelete:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoServerRequestPasswordReset:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *email = body[@"email"];
        if (email.length == 0 || !isLikelyEmail(email)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid email"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoServerReserveSigningKey:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
        Secp256k1KeyPair *keyPair = nil;
        NSString *signingKey = nil;
        NSError *error = nil;

        if (did.length > 0) {
            NSError *didError = nil;
            if (![ATProtoValidator validateDID:did error:&didError]) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": didError.localizedDescription ?: @"Invalid DID"}];
                return;
            }

            PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&error];
            if (!account) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": error.localizedDescription ?: @"Account not found"}];
                return;
            }

            NSError *storeError = nil;
            PDSActorStore *store = [userDatabasePool storeForDid:did error:&storeError];
            if (!store) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"StoreUnavailable", @"message": storeError.localizedDescription ?: @"Failed to open account store"}];
                return;
            }

            NSError *keyError = nil;
            NSString *storedKey = [store didKeyStringWithError:&keyError];
            if (!storedKey) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"SigningKeyUnavailable", @"message": keyError.localizedDescription ?: @"Signing key unavailable"}];
                return;
            }
            // Use a dummy keyPair or just set the output string directly
            // The original code set keyPair, then used keyPair.didKeyString.
            // We can just set a string variable.
            signingKey = storedKey;
        } else {
            keyPair = [[Secp256k1 shared] generateKeyPairWithError:&error];
            if (keyPair) {
                signingKey = keyPair.didKeyString;
            }
        }

        if (!signingKey) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"SigningKeyUnavailable", @"message": error.localizedDescription ?: @"Failed to reserve signing key"}];
            return;
        }

        if (signingKey.length == 0) {
            signingKey = @"did:key:placeholder"; // Should not happen if store works
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"signingKey": signingKey}];
    }];

    [dispatcher registerComAtprotoServerResetPassword:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *token = body[@"token"];
        NSString *password = body[@"password"];
        if (token.length == 0 || password.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing token or password"}];
            return;
        }
        if (password.length < 8) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Password must be at least 8 characters"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:token error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid reset token"}];
            return;
        }

        NSError *accountError = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:token error:&accountError];
        if (!account) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid reset token"}];
            return;
        }

        NSError *hashError = nil;
        NSData *newHash = pbkdf2HashPassword(password, account.passwordSalt, &hashError);
        if (!newHash) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"PasswordResetFailed", @"message": hashError.localizedDescription ?: @"Failed to reset password"}];
            return;
        }

        account.passwordHash = newHash;
        account.updatedAt = [[NSDate date] timeIntervalSince1970];
        NSError *updateError = nil;
        if (![serviceDatabases updateAccount:account error:&updateError]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"PasswordResetFailed", @"message": updateError.localizedDescription ?: @"Failed to persist new password"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    registerTempUtilityMethods(dispatcher, serviceDatabases, jwtMinter, adminController);
    registerTempRevokeAccountCredentialsMethod(dispatcher, serviceDatabases, jwtMinter, adminController);

    [dispatcher registerComAtprotoServerUpdateEmail:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *email = body[@"email"];
        if (email.length == 0 || !isLikelyEmail(email)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid email"}];
            return;
        }

        NSError *error = nil;
        if (!updateAccountEmail(serviceDatabases, did, email, &error)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"EmailUpdateFailed", @"message": error.localizedDescription ?: @"Failed to update email"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

@implementation XrpcMethodRegistry

static NSTimeInterval const kPlcOperationTokenTTLSeconds = 15.0 * 60.0;

static NSCache<NSString *, NSDictionary *> *plcOperationTokenCache(void) {
    static NSCache<NSString *, NSDictionary *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 1024;
    });
    return cache;
}

+ (void)storePlcOperationToken:(NSString *)token forDid:(NSString *)did {
    if (![token isKindOfClass:[NSString class]] || token.length == 0) {
        return;
    }
    if (![did isKindOfClass:[NSString class]] || did.length == 0) {
        return;
    }

    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:kPlcOperationTokenTTLSeconds];
    NSDictionary *entry = @{@"token": token, @"expiresAt": expiresAt};
    [plcOperationTokenCache() setObject:entry forKey:did];
}

+ (BOOL)validatePlcOperationToken:(NSString *)token forDid:(NSString *)did {
    if (![token isKindOfClass:[NSString class]] || token.length == 0) {
        return NO;
    }
    if (![did isKindOfClass:[NSString class]] || did.length == 0) {
        return NO;
    }

    NSCache<NSString *, NSDictionary *> *cache = plcOperationTokenCache();
    NSDictionary *entry = [cache objectForKey:did];
    if (![entry isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSString *expected = entry[@"token"];
    NSDate *expiresAt = entry[@"expiresAt"];
    if (![expected isKindOfClass:[NSString class]] || ![expiresAt isKindOfClass:[NSDate class]]) {
        [cache removeObjectForKey:did];
        return NO;
    }
    if ([expiresAt timeIntervalSinceNow] <= 0) {
        [cache removeObjectForKey:did];
        return NO;
    }
    if (![expected isEqualToString:token]) {
        return NO;
    }

    [cache removeObjectForKey:did];
    return YES;
}

/**
 @brief Decode a DID publicKeyMultibase value into raw key bytes.
 */
+ (nullable NSData *)publicKeyBytesFromMultibase:(NSString *)multibase error:(NSError **)error {
    if (multibase.length < 2) {
        if (error) {
            *error = [NSError errorWithDomain:DIDErrorDomain
                                         code:DIDErrorInvalidDocument
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid publicKeyMultibase value"}];
        }
        return nil;
    }

    unichar prefix = [multibase characterAtIndex:0];
    NSString *payload = [multibase substringFromIndex:1];
    NSData *data = nil;
    switch (prefix) {
        case 'z':
        case 'Z':
            data = [CID base58btcDecode:payload];
            break;
        case 'b':
            data = [CID base32Decode:payload];
            break;
        case 'u':
            data = [JWT base64URLDecode:payload error:error];
            break;
        default:
            if (error) {
                *error = [NSError errorWithDomain:DIDErrorDomain
                                             code:DIDErrorInvalidDocument
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unsupported multibase encoding for signing key"}];
            }
            return nil;
    }

    if (!data) {
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    if (data.length > 2 && bytes[0] == 0xE7 && bytes[1] == 0x01) {
        return [data subdataWithRange:NSMakeRange(2, data.length - 2)];
    }
    return data;
}

static BOOL validateDidWebServiceAuthForAccountCreation(HttpRequest *request,
                                                        HttpResponse *response,
                                                        NSString *did,
                                                        PDSConfiguration *config) {
    PDSConfiguration *effectiveConfig = config ?: [PDSConfiguration sharedConfiguration];

    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader || ![authHeader hasPrefix:@"Bearer "]) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Missing service auth token"}];
        return NO;
    }

    NSString *token = [authHeader substringFromIndex:7];
    NSError *parseError = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&parseError];
    if (!jwt || parseError) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Unable to parse service auth token"}];
        return NO;
    }

    NSError *payloadError = nil;
    NSDictionary *payloadDict = payloadDictionaryFromJWT(jwt, &payloadError);
    if (!payloadDict) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Unable to decode service auth payload"}];
        return NO;
    }

    NSString *lxm = payloadDict[@"lxm"];
    if (!lxm || ![lxm isEqualToString:kServiceAuthLxmCreateAccount]) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Service auth token has invalid lxm"}];
        return NO;
    }

    NSError *resolveError = nil;
    DIDResolver *resolver = [[DIDResolver alloc] init];
    resolver.plcURL = effectiveConfig.plcURL;
    NSDictionary *atprotoData = [resolver resolveAtprotoDataForDID:did error:&resolveError];
    NSString *signingKey = atprotoData[@"signingKey"];
    if (!signingKey) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"DID document missing signing key"}];
        return NO;
    }

    NSError *decodeError = nil;
    NSData *signingKeyBytes = [XrpcMethodRegistry publicKeyBytesFromMultibase:signingKey error:&decodeError];
    if (!signingKeyBytes) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Unable to decode signing key"}];
        return NO;
    }

    NSError *keyError = nil;
    NSData *publicKey = [[Secp256k1 shared] normalizedPublicKey:signingKeyBytes error:&keyError];
    if (!publicKey) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Unable to normalize signing key"}];
        return NO;
    }

    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.publicKey = publicKey;
    verifier.allowedAlgorithms = @[@"ES256K"];
    verifier.expectedIssuer = did;
    verifier.allowMissingSubject = YES;

    NSError *verifyError = nil;
    BOOL verified = [verifier verifyJWT:jwt error:&verifyError];
    if (!verified) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Service auth verification failed"}];
        return NO;
    }

    NSString *iss = jwt.payload.iss;
    if (!iss || ![iss isEqualToString:did]) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Service auth token has invalid issuer"}];
        return NO;
    }

    NSString *aud = jwt.payload.aud;
    NSArray<NSString *> *expectedAudiences = serviceAuthExpectedAudiences(effectiveConfig);
    NSString *audBase = aud;
    NSRange audHash = [aud rangeOfString:@"#"];
    if (audHash.location != NSNotFound) {
        audBase = [aud substringToIndex:audHash.location];
    }
    if (!aud || ![expectedAudiences containsObject:audBase]) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Service auth token has invalid audience"}];
        return NO;
    }

    return YES;
}

static void registerServerAccountAndSessionMethods(XrpcDispatcher *dispatcher,
                                                    JWTMinter *jwtMinter,
                                                    id<PDSAdminController> adminController,
                                                    id<PDSAccountService> accountService,
                                                    PDSRepositoryService *repositoryService,
                                                    PDSServiceDatabases *serviceDatabases,
                                                    PDSDatabasePool *userDatabasePool,
                                                    PDSConfiguration *config,
                                                    BOOL enforceDidWebServiceAuth) {
    [dispatcher registerComAtprotoServerCreateAccount:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *email = body[@"email"];
        NSString *handle = body[@"handle"];
        NSString *password = body[@"password"];
        NSString *did = body[@"did"];

        if (!email || !password || !handle) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing email, handle, or password"}];
            return;
        }

        // Security: Reject arbitrary DID parameter
        if (did.length > 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Cannot specify DID during account creation. Import is not supported via this endpoint."}];
            return;
        }

        // Security: Enforce invite code if required
        if (config.inviteCodeRequired) {
            NSString *inviteCode = body[@"inviteCode"];
            if (!inviteCode || inviteCode.length == 0) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidInviteCode", @"message": @"Invite code required"}];
                return;
            }
            
            NSError *inviteError = nil;
            // Assuming serviceDatabases provides a way to check codes, or we need to access the store directly.
            // Based on previous research, ServiceDatabases has useInviteCode:error:
            if (![serviceDatabases useInviteCode:inviteCode error:&inviteError]) {
                 response.statusCode = HttpStatusBadRequest;
                 [response setJsonBody:@{@"error": @"InvalidInviteCode", @"message": inviteError.localizedDescription ?: @"Invalid or expired invite code"}];
                 return;
            }
        }

        if (enforceDidWebServiceAuth && did.length > 0 && [did hasPrefix:@"did:web:"]) {
            if (!validateDidWebServiceAuthForAccountCreation(request, response, did, config)) {
                return;
            }
        }

        NSError *error = nil;
        NSDictionary *result = [accountService createAccountForEmail:email
                                                             password:password
                                                               handle:handle
                                                                  did:nil // Force nil DID to trigger generation
                                                                error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"AccountCreationFailed", @"message": error.localizedDescription}];
            return;
        }

        NSString *createdDid = result[@"did"];
        if (createdDid && repositoryService) {
            NSError *initError = nil;
            if (![repositoryService initializeRepoForDid:createdDid error:&initError]) {
                PDS_LOG_ERROR(@"Failed to initialize repo for DID %@: %@", createdDid, initError);
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoServerCreateSession:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *identifier = body[@"identifier"];
        NSString *password = body[@"password"];

        if (!identifier || !password) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing identifier or password"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *session = [accountService loginWithIdentifier:identifier
                                                            password:password
                                                               error:&error];

        if (error) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthenticationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:session];
    }];

    [dispatcher registerComAtprotoServerGetSession:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSError *error = nil;
        NSDictionary *account = [accountService getAccountForDid:did error:&error];
        if (error || !account) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": @"Account not found for session"}];
            return;
        }

        NSMutableDictionary *result = [account mutableCopy];
        result[@"did"] = did;
        result[@"emailConfirmed"] = @YES;
        if (!result[@"handle"]) {
            result[@"handle"] = @"unknown.handle";
        }
        
        BOOL isAdmin = [[PDSAdminAuth sharedAuth] isAdminDid:did];
        result[@"isAdmin"] = @(isAdmin);

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoServerRefreshSession:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *refreshToken = nil;
        
        if ([authHeader hasPrefix:@"Bearer "]) {
            refreshToken = [authHeader substringFromIndex:7];
        }

        if (!refreshToken) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing refresh token in Authorization header"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *session = [accountService refreshAccessToken:refreshToken error:&error];

        if (error) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthenticationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:session];
    }];

    [dispatcher registerComAtprotoServerDeleteSession:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSError *error = nil;
        BOOL success = [serviceDatabases deleteRefreshTokensForAccount:did error:&error];
        if (!success) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"SessionDeletionFailed", @"message": error.localizedDescription ?: @"Failed to delete session"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoServerCreateInviteCode:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSNumber *useCountNumber = body[@"useCount"];
        NSInteger useCount = useCountNumber.integerValue;
        NSString *forAccount = body[@"forAccount"];
        NSString *targetDid = forAccount.length > 0 ? forAccount : did;

        if (![targetDid isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot create invite codes for other accounts"}];
            return;
        }

        NSError *error = nil;
        NSString *code = nil;
        if (!createInviteCodeInDatabase(serviceDatabases, targetDid, useCount, &code, &error)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InviteCodeCreateFailed", @"message": error.localizedDescription ?: @"Failed to create invite code"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"code": code ?: @""}];
    }];

    [dispatcher registerComAtprotoServerCreateInviteCodes:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSNumber *codeCountNumber = body[@"codeCount"] ?: @1;
        NSNumber *useCountNumber = body[@"useCount"];
        NSInteger codeCount = codeCountNumber.integerValue;
        NSInteger useCount = useCountNumber.integerValue;
        NSArray<NSString *> *forAccounts = body[@"forAccounts"];
        if (![forAccounts isKindOfClass:[NSArray class]] || forAccounts.count == 0) {
            forAccounts = @[did];
        }

        if (codeCount <= 0 || codeCount > 100) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"codeCount must be between 1 and 100"}];
            return;
        }

        for (NSString *accountDid in forAccounts) {
            if (![accountDid isKindOfClass:[NSString class]] || ![accountDid isEqualToString:did]) {
                response.statusCode = HttpStatusForbidden;
                [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot create invite codes for other accounts"}];
                return;
            }
        }

        NSMutableArray *codesByAccount = [NSMutableArray array];
        for (NSString *accountDid in forAccounts) {
            NSMutableArray<NSString *> *codes = [NSMutableArray arrayWithCapacity:(NSUInteger)codeCount];
            for (NSInteger i = 0; i < codeCount; i++) {
                NSError *error = nil;
                NSString *code = nil;
                if (!createInviteCodeInDatabase(serviceDatabases, accountDid, useCount, &code, &error)) {
                    response.statusCode = HttpStatusBadRequest;
                    [response setJsonBody:@{@"error": @"InviteCodeCreateFailed", @"message": error.localizedDescription ?: @"Failed to create invite code"}];
                    return;
                }
                if (code.length > 0) {
                    [codes addObject:code];
                }
            }
            [codesByAccount addObject:@{@"account": accountDid, @"codes": codes}];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"codes": codesByAccount}];
    }];

    [dispatcher registerComAtprotoServerCreateAppPassword:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *name = body[@"name"];
        NSNumber *privilegedNumber = body[@"privileged"];
        BOOL privileged = privilegedNumber.boolValue;

        if (name.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing name"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [serviceDatabases createAppPasswordForAccount:did
                                                                         name:name
                                                                   privileged:privileged
                                                                        error:&error];
        if (!result) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"AppPasswordCreateFailed", @"message": error.localizedDescription ?: @"Failed to create app password"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoServerListAppPasswords:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSError *error = nil;
        NSArray<NSDictionary *> *passwords = [serviceDatabases listAppPasswordsForAccount:did error:&error];
        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"AppPasswordListFailed", @"message": error.localizedDescription ?: @"Failed to list app passwords"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"passwords": passwords ?: @[]}];
    }];

    [dispatcher registerComAtprotoServerRevokeAppPassword:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *name = body[@"name"];
        if (name.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing name"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [serviceDatabases revokeAppPasswordForAccount:did name:name error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"AppPasswordRevokeFailed", @"message": error.localizedDescription ?: @"Failed to revoke app password"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoServerGetServiceAuth:^(HttpRequest *request, HttpResponse *response) {
        NSString *aud = [request queryParamForKey:@"aud"];
        if (!aud) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing aud parameter"}];
            return;
        }

        NSString *lxm = [request queryParamForKey:@"lxm"];
        if (lxm.length > 0) {
            NSError *lxmError = nil;
            if (![ATProtoValidator validateNSID:lxm error:&lxmError]) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": lxmError.localizedDescription ?: @"Invalid lxm parameter"}];
                return;
            }
        }

        NSString *expParam = [request queryParamForKey:@"exp"];
        long long requestedExp = 0;
        BOOL hasRequestedExp = expParam.length > 0;
        if (hasRequestedExp) {
            NSScanner *scanner = [NSScanner scannerWithString:expParam];
            if (![scanner scanLongLong:&requestedExp] || !scanner.isAtEnd) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"BadExpiration", @"message": @"Invalid exp parameter"}];
                return;
            }
        }

        NSString *audDid = aud;
        NSRange hashRange = [aud rangeOfString:@"#"];
        if (hashRange.location != NSNotFound) {
            audDid = [aud substringToIndex:hashRange.location];
        }

        NSError *audError = nil;
        if (![ATProtoValidator validateDID:audDid error:&audError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": audError.localizedDescription ?: @"Invalid aud DID"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Missing or invalid authorization token"}];
            }
            return;
        }

        NSError *accountError = nil;
        if (![serviceDatabases getAccountByDid:did error:&accountError]) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": @"Account not found for token"}];
            return;
        }

        NSError *storeError = nil;
        PDSActorStore *store = [userDatabasePool storeForDid:did error:&storeError];
        if (!store) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"StoreUnavailable", @"message": storeError.localizedDescription ?: @"Failed to load signing key"}];
            return;
        }

        long long nowSeconds = (long long)[[NSDate date] timeIntervalSince1970];
        if (hasRequestedExp && requestedExp <= nowSeconds) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BadExpiration", @"message": @"exp must be in the future"}];
            return;
        }

        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        payload[@"iss"] = did;
        payload[@"sub"] = did;
        payload[@"did"] = did;
        payload[@"aud"] = aud;
        payload[@"iat"] = @((long long)nowSeconds);
        payload[@"exp"] = @(hasRequestedExp ? requestedExp : (long long)(nowSeconds + 60));
        payload[@"jti"] = [[NSUUID UUID] UUIDString];
        if (lxm.length > 0) {
            payload[@"lxm"] = lxm;
        }

        JWTMinter *minter = [[JWTMinter alloc] init];
        minter.issuer = did;
        minter.signingAlgorithm = @"ES256K";
        // minter.privateKey = privateKey; // REMOVED

        NSError *mintError = nil;
        NSString *token = [minter signPayload:payload actorKeyManager:store.keyManager error:&mintError];
        if (!token) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"TokenMintFailed", @"message": mintError.localizedDescription ?: @"Failed to mint service auth token"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"token": token}];
    }];
    

}

static void registerRepoCoreMethods(XrpcDispatcher *dispatcher,
                                    JWTMinter *jwtMinter,
                                    id<PDSAdminController> adminController,
                                    id<PDSAccountService> accountService,
                                    PDSRecordService *recordService,
                                    PDSBlobService *blobService,
                                    PDSRepositoryService *repositoryService,
                                    PDSServiceDatabases *serviceDatabases) {
    [dispatcher registerComAtprotoRepoListRecords:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = [request queryParamForKey:@"repo"];
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];

        if (!repo) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo parameter"}];
            return;
        }

        if (!collection) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection parameter"}];
            return;
        }

        NSString *did = nil;
        if ([repo hasPrefix:@"did:"]) {
            did = repo;
        } else {
            PDSDatabaseAccount *account = [serviceDatabases getAccountByHandle:repo error:nil];
            if (account) {
                did = account.did;
            } else {
                HandleResolver *handleResolver = [[HandleResolver alloc] init];
                __block NSString *resolvedDid = nil;
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [handleResolver resolveHandle:repo completion:^(NSString * _Nullable resolved, NSError * _Nullable error) {
                    resolvedDid = resolved;
                    dispatch_semaphore_signal(semaphore);
                }];
                dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
                did = resolvedDid;
            }
        }

        if (!did) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": [NSString stringWithFormat:@"Could not find repo: %@", repo]}];
            return;
        }

        NSUInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit > 100) limit = 100;

        NSError *error = nil;
        NSArray *records = [recordService listRecords:collection forDid:did limit:limit cursor:cursor error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ListRecordsFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"records": records ?: @[]}];
    }];

    [dispatcher registerComAtprotoRepoGetRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = [request queryParamForKey:@"repo"];
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *rkey = [request queryParamForKey:@"rkey"];

        if (!repo) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo parameter"}];
            return;
        }

        if (!collection || !rkey) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection or rkey parameter"}];
            return;
        }

        NSString *did = nil;
        if ([repo hasPrefix:@"did:"]) {
            did = repo;
        } else {
            PDSDatabaseAccount *account = [serviceDatabases getAccountByHandle:repo error:nil];
            if (account) {
                did = account.did;
            } else {
                HandleResolver *handleResolver = [[HandleResolver alloc] init];
                __block NSString *resolvedDid = nil;
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [handleResolver resolveHandle:repo completion:^(NSString * _Nullable resolved, NSError * _Nullable error) {
                    resolvedDid = resolved;
                    dispatch_semaphore_signal(semaphore);
                }];
                dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
                did = resolvedDid;
            }
        }

        if (!did) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": [NSString stringWithFormat:@"Could not find repo: %@", repo]}];
            return;
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        NSError *error = nil;
        NSDictionary *record = [recordService getRecord:uri forDid:did error:&error];

        if (error || !record) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RecordNotFound", @"message": @"Record not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:record];
    }];

    [dispatcher registerComAtprotoRepoCreateRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *collection = body[@"collection"];
        NSDictionary *record = body[@"record"];
        NSString *rkey = body[@"rkey"];
        NSString *repo = body[@"repo"];
        BOOL validate = [body[@"validate"] boolValue];

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot create record for another user"}];
            return;
        }

        if (!collection || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection or record"}];
            return;
        }

        if (!rkey) {
            rkey = [[TID tid] stringValue];
        }

        PDSValidationMode mode = validate ? PDSValidationModeRequired : PDSValidationModeOff;
        NSError *error = nil;
        BOOL success = [recordService putRecord:collection rkey:rkey value:record forDid:did validationMode:mode error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"RecordCreationFailed", @"message": error.localizedDescription ?: @"Failed to create record"}];
            return;
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        NSDictionary *createdRecord = [recordService getRecord:uri forDid:did error:nil];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:createdRecord ?: @{@"uri": uri}];
    }];

    [dispatcher registerComAtprotoRepoDeleteRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *collection = body[@"collection"];
        NSString *rkey = body[@"rkey"];
        NSString *repo = body[@"repo"];

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot delete record for another user"}];
            return;
        }

        if (!collection || !rkey) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection or rkey"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [recordService deleteRecord:collection rkey:rkey forDid:did error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"RecordDeletionFailed", @"message": error.localizedDescription ?: @"Failed to delete record"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"uri": [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey]}];
    }];

    [dispatcher registerComAtprotoRepoUploadBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSData *blobData = request.body;
        if (!blobData || blobData.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing blob data"}];
            return;
        }

        if (blobData.length > 1 * 1024 * 1024) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BlobTooLarge", @"message": @"Blob too large"}];
            return;
        }

        NSString *contentType = [request headerForKey:@"Content-Type"];
        if (contentType && [contentType isEqualToString:@"application/x-msdownload"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidMimeType", @"message": @"Forbidden MIME type"}];
            return;
        }
        NSError *error = nil;
        NSDictionary *result = [blobService uploadBlob:blobData
                                                forDid:did
                                              mimeType:contentType ?: @"application/octet-stream"
                                                 error:&error];
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BlobUploadFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoDeleteBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *cid = body[@"blob"];
        if (!cid) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing blob CID"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [blobService deleteBlobWithCID:cid did:did error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BlobDeletionFailed", @"message": error.localizedDescription ?: @"Failed to delete blob"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];
    }];

    [dispatcher registerComAtprotoRepoListMissingBlobs:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSString *limitParam = [request queryParamForKey:@"limit"];
        NSInteger limit = 500;
        if (limitParam.length > 0) {
            if (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 1000) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 1000"}];
                return;
            }
        }

        NSMutableDictionary *result = [@{@"blobs": @[]} mutableCopy];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        if (cursor.length > 0) {
            result[@"cursor"] = cursor;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoImportRepo:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSString *contentType = [request headerForKey:@"Content-Type"] ?: @"";
        if (![contentType hasPrefix:@"application/vnd.ipld.car"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Expected application/vnd.ipld.car content type"}];
            return;
        }

        NSString *contentLengthHeader = [request headerForKey:@"Content-Length"];
        NSInteger contentLength = 0;
        if (contentLengthHeader.length == 0 || !parseStrictIntegerString(contentLengthHeader, &contentLength) || contentLength <= 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid Content-Length header"}];
            return;
        }

        NSData *body = request.body;
        if (body.length == 0 || body.length != (NSUInteger)contentLength) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Body length does not match Content-Length"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoRepoDescribeRepo:^(HttpRequest *request, HttpResponse *response) {
        // Per lexicon: does not require auth.
        NSString *identifier = [request queryParamForKey:@"repo"] ?: @"";
        if (identifier.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo"}];
            return;
        }

        NSString *did = nil;
        NSString *handle = nil;

        if ([identifier hasPrefix:@"did:"]) {
            did = identifier;
        } else {
            NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:identifier];
            PDSDatabaseAccount *account = [serviceDatabases getAccountByHandle:normalizedHandle error:nil];
            if (account.did.length > 0) {
                did = account.did;
                handle = account.handle.length > 0 ? [account.handle lowercaseString] : normalizedHandle;
            } else {
                // Fall back to external handle resolution.
                HandleResolver *handleResolver = [[HandleResolver alloc] init];
                __block NSString *resolvedDid = nil;
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [handleResolver resolveHandle:normalizedHandle completion:^(NSString * _Nullable handleDid, NSError * _Nullable resolveError) {
                    resolvedDid = handleDid;
                    (void)resolveError;
                    dispatch_semaphore_signal(semaphore);
                }];
                dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
                did = resolvedDid;
                handle = normalizedHandle;
            }
        }

        if (did.length == 0) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
            return;
        }

        NSDictionary *stats = [recordService getRepoStatsForDid:did error:nil];
        PDSDatabaseAccount *localAccount = [serviceDatabases getAccountByDid:did error:nil];
        if (!localAccount) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
            return;
        }

        // Resolve full DID document (required by lexicon).
        DIDResolver *didResolver = [[DIDResolver alloc] init];
        didResolver.plcURL = [PDSConfiguration sharedConfiguration].plcURL;
        DIDDocument *doc = [didResolver resolveDIDSync:did error:nil];
        NSDictionary *didDocJson = doc.jsonDictionary ?: @{};

        if (handle.length == 0) {
            // Prefer local account handle if present, otherwise infer from DID doc.
            if (localAccount.handle.length > 0) {
                handle = [localAccount.handle lowercaseString];
            } else {
                handle = normalizedAtHandleFromAlsoKnownAs(doc.alsoKnownAs);
            }
        }
        if (handle.length == 0) {
            handle = @"handle.invalid";
        }

        NSMutableArray *collections = [NSMutableArray array];
        if ([stats[@"collections"] isKindOfClass:[NSArray class]]) {
            for (NSDictionary *col in stats[@"collections"]) {
                if ([col isKindOfClass:[NSDictionary class]] && [col[@"collection"] isKindOfClass:[NSString class]]) {
                    [collections addObject:col[@"collection"]];
                }
            }
        }

        BOOL handleIsCorrect = NO;
        if (doc && ![handle isEqualToString:@"handle.invalid"]) {
            BOOL didDocMatches = didDocumentContainsHandle(doc, handle);
            if (didDocMatches) {
                // Try to confirm handle -> DID resolution without failing the request on timeout.
                HandleResolver *handleResolver = [[HandleResolver alloc] init];
                __block NSString *resolvedDid = nil;
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [handleResolver resolveHandle:handle completion:^(NSString * _Nullable handleDid, NSError * _Nullable resolveError) {
                    resolvedDid = handleDid;
                    (void)resolveError;
                    dispatch_semaphore_signal(semaphore);
                }];
                dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC);
                long waited = dispatch_semaphore_wait(semaphore, timeout);
                handleIsCorrect = (waited != 0) ? YES : (resolvedDid.length > 0 && [resolvedDid isEqualToString:did]);
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"handle": handle,
            @"did": did,
            @"didDoc": didDocJson,
            @"collections": collections,
            @"handleIsCorrect": @(handleIsCorrect)
        }];
    }];

    [dispatcher registerComAtprotoRepoPutRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *collection = body[@"collection"];
        NSString *rkey = body[@"rkey"];
        NSDictionary *record = body[@"record"];
        NSString *repo = body[@"repo"];
        BOOL validate = [body[@"validate"] boolValue];

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot update record for another user"}];
            return;
        }

        if (!collection || !rkey || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection, rkey, or record"}];
            return;
        }

        PDSValidationMode mode = validate ? PDSValidationModeRequired : PDSValidationModeOff;
        NSError *error = nil;
        BOOL success = [recordService putRecord:collection rkey:rkey value:record forDid:did validationMode:mode error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"RecordUpdateFailed", @"message": error.localizedDescription ?: @"Failed to update record"}];
            return;
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"uri": uri}];
    }];

    [dispatcher registerComAtprotoRepoApplyWrites:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        if (!body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSArray *writes = body[@"writes"];
        NSString *repo = body[@"repo"];
        BOOL validate = [body[@"validate"] boolValue];
        NSString *swapCommit = body[@"swapCommit"];

        if (repo && ![repo isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot apply writes for another user"}];
            return;
        }

        if (!writes || ![writes isKindOfClass:[NSArray class]]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid writes array"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [recordService applyWrites:writes
                                                   forDid:did
                                                 validate:validate
                                               swapCommit:swapCommit
                                                    error:&error];
        if (!result) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"WriteFailed", @"message": error.localizedDescription ?: @"Failed to apply writes"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
}

static void registerSyncCoreMethods(XrpcDispatcher *dispatcher,
                                    JWTMinter *jwtMinter,
                                    id<PDSAdminController> adminController,
                                    PDSServiceDatabases *serviceDatabases,
                                    PDSDatabasePool *userDatabasePool,
                                    PDSRecordService *recordService,
                                    PDSBlobService *blobService,
                                    PDSRepositoryService *repositoryService,
                                    PDSConfiguration *config) {
    [dispatcher registerComAtprotoSyncGetRepo:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        NSString *sinceRev = [request queryParamForKey:@"since"];
        if (did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *exportError = nil;
        PDSRepoChunkProducer producer = [repositoryService repoContentsChunkProducer:did
                                                                               since:sinceRev
                                                                               error:&exportError];
        if (!producer) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound",
                                    @"message": exportError.localizedDescription ?: @"Repository not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = @"application/vnd.ipld.car";
        [response setBodyChunkProducer:producer chunkedTransferEncoding:YES];
    }];

    [dispatcher registerComAtprotoSyncGetCheckout:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        if (did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *error = nil;
        NSData *repoData = [repositoryService getRepoContents:did since:nil error:&error];
        if (!repoData || error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": error.localizedDescription ?: @"Repository not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = @"application/vnd.ipld.car";
        [response setBodyData:repoData];
    }];

    [dispatcher registerComAtprotoSyncGetHead:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSError *error = nil;
        NSData *root = [repositoryService getRepoRoot:did error:&error];
        if (error || !root) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"root": [CID base32Encode:root]}];
    }];

    [dispatcher registerComAtprotoSyncGetHostStatus:^(HttpRequest *request, HttpResponse *response) {
        NSString *hostnameParam = [request queryParamForKey:@"hostname"];
        if (hostnameParam.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing hostname"}];
            return;
        }

        NSDictionary *hostEntry = localSyncHostEntry(serviceDatabases, config);
        NSString *requested = normalizedHostnameString(hostnameParam);
        NSString *local = hostEntry[@"hostname"];
        if (![requested isEqualToString:local]) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"HostNotFound", @"message": @"Host not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:hostEntry];
    }];

    [dispatcher registerComAtprotoSyncListHosts:^(HttpRequest *request, HttpResponse *response) {
        NSString *limitParam = [request queryParamForKey:@"limit"];
        NSInteger limit = 200;
        if (limitParam.length > 0) {
            if (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 1000) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 1000"}];
                return;
            }
        }

        NSString *cursorParam = [request queryParamForKey:@"cursor"];
        NSInteger startIndex = 0;
        if (cursorParam.length > 0) {
            if (!parseStrictIntegerString(cursorParam, &startIndex) || startIndex < 0) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"cursor must be a non-negative integer"}];
                return;
            }
        }

        NSDictionary *hostEntry = localSyncHostEntry(serviceDatabases, config);
        NSMutableArray<NSDictionary *> *hosts = [NSMutableArray array];
        NSInteger totalHosts = 1;
        NSInteger scanIndex = MIN(startIndex, totalHosts);
        while (scanIndex < totalHosts && hosts.count < (NSUInteger)limit) {
            [hosts addObject:hostEntry];
            scanIndex += 1;
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:hosts forKey:@"hosts"];
        if (scanIndex < totalHosts) {
            result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)scanIndex];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoSyncListRepos:^(HttpRequest *request, HttpResponse *response) {
        NSString *limitParam = [request queryParamForKey:@"limit"];
        NSInteger limit = 500;
        if (limitParam.length > 0) {
            if (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 1000) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 1000"}];
                return;
            }
        }

        NSString *cursorParam = [request queryParamForKey:@"cursor"];
        NSInteger startIndex = 0;
        if (cursorParam.length > 0) {
            if (!parseStrictIntegerString(cursorParam, &startIndex) || startIndex < 0) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"cursor must be a non-negative integer"}];
                return;
            }
        }

        NSError *accountsError = nil;
        NSArray<PDSDatabaseAccount *> *accounts = [serviceDatabases getAllAccountsWithError:&accountsError];
        NSLog(@"[listRepos] Loaded %lu accounts", (unsigned long)accounts.count);
        if (!accounts) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"DatabaseUnavailable", @"message": accountsError.localizedDescription ?: @"Failed to load accounts"}];
            return;
        }

        NSMutableArray<NSDictionary *> *repos = [NSMutableArray array];
        NSInteger scanIndex = MIN(startIndex, (NSInteger)accounts.count);
        while (scanIndex < (NSInteger)accounts.count && repos.count < (NSUInteger)limit) {
            PDSDatabaseAccount *account = accounts[(NSUInteger)scanIndex];
            NSLog(@"[listRepos] Scanning account: %@", account.did);
            if (account.did.length > 0) {
                NSError *rootError = nil;
                NSData *root = [repositoryService getRepoRoot:account.did error:&rootError];
                NSLog(@"[listRepos] Root data for %@: %@", account.did, root ? [NSString stringWithFormat:@"%lu bytes", (unsigned long)root.length] : @"NIL");
                NSString *head = root ? [CID base32Encode:root] : nil;

                if (head.length > 0) {
                    NSString *rev = [[TID tid] stringValue];
                    [repos addObject:@{
                        @"did": account.did,
                        @"head": head,
                        @"rev": rev ?: @"",
                        @"active": @YES
                    }];
                }
            }
            scanIndex += 1;
        }

        NSLog(@"[listRepos] Found %lu repos", (unsigned long)repos.count);
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:repos forKey:@"repos"];
        if (scanIndex < (NSInteger)accounts.count) {
            result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)scanIndex];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoSyncGetRepoStatus:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        if (did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *validateError = nil;
        if (![ATProtoValidator validateDID:did error:&validateError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": validateError.localizedDescription ?: @"Invalid did"}];
            return;
        }

        NSError *accountError = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&accountError];
        if (!account) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": accountError.localizedDescription ?: @"Repository not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"did": did, @"active": @YES}];
    }];

    [dispatcher registerComAtprotoSyncListReposByCollection:^(HttpRequest *request, HttpResponse *response) {
        NSString *collection = [request queryParamForKey:@"collection"];
        if (collection.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection"}];
            return;
        }

        NSError *nsidError = nil;
        if (![ATProtoValidator validateNSID:collection error:&nsidError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": nsidError.localizedDescription ?: @"Invalid collection"}];
            return;
        }

        NSString *limitParam = [request queryParamForKey:@"limit"];
        NSInteger limit = 500;
        if (limitParam.length > 0) {
            if (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 2000) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 2000"}];
                return;
            }
        }

        NSString *cursorParam = [request queryParamForKey:@"cursor"];
        NSInteger startIndex = 0;
        if (cursorParam.length > 0) {
            if (!parseStrictIntegerString(cursorParam, &startIndex) || startIndex < 0) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"cursor must be a non-negative integer"}];
                return;
            }
        }

        NSError *accountsError = nil;
        NSArray<PDSDatabaseAccount *> *accounts = [serviceDatabases getAllAccountsWithError:&accountsError];
        if (!accounts) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"DatabaseUnavailable", @"message": accountsError.localizedDescription ?: @"Failed to load accounts"}];
            return;
        }

        NSMutableArray<NSDictionary *> *repos = [NSMutableArray array];
        NSInteger scanIndex = MIN(startIndex, (NSInteger)accounts.count);
        while (scanIndex < (NSInteger)accounts.count && repos.count < (NSUInteger)limit) {
            PDSDatabaseAccount *account = accounts[(NSUInteger)scanIndex];
            if (account.did.length > 0) {
                NSError *storeError = nil;
                PDSActorStore *store = [userDatabasePool storeForDid:account.did error:&storeError];
                if (store) {
                    NSArray<PDSDatabaseRecord *> *records = [store listRecordsForDid:account.did
                                                                           collection:collection
                                                                                limit:1
                                                                               offset:0
                                                                                error:nil];
                    if (records.count > 0) {
                        [repos addObject:@{@"did": account.did}];
                    }
                }
            }
            scanIndex += 1;
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:repos forKey:@"repos"];
        if (scanIndex < (NSInteger)accounts.count) {
            result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)scanIndex];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoSyncListBlobs:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSUInteger limit = limitStr ? [limitStr integerValue] : 500;
        if (limit > 1000) {
            limit = 1000;
        }

        NSError *error = nil;
        NSArray *blobs = [blobService listBlobsForDID:did limit:limit cursor:cursor error:&error];
        if (error) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"ListBlobsFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"blobs": blobs ?: @[]}];
    }];

    [dispatcher registerComAtprotoSyncGetBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        NSString *cid = [request queryParamForKey:@"cid"];
        if (did.length == 0 || cid.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did or cid"}];
            return;
        }

        NSError *blobError = nil;
        NSDictionary *result = [blobService getBlobStreamWithCID:cid did:did error:&blobError];
        if (!result && !blobError) {
            result = [blobService getBlobWithCID:cid did:did error:&blobError];
        }
        if (!result) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"BlobRetrievalFailed",
                                    @"message": blobError.localizedDescription ?: @"Blob not found"}];
            return;
        }

        NSString *mimeType = result[@"mimeType"] ?: @"application/octet-stream";
        NSString *filePath = result[@"filePath"];
        NSData *blobData = result[@"blob"];
        unsigned long long totalLength = [result[@"size"] unsignedLongLongValue];

        if (totalLength == 0 && [filePath isKindOfClass:[NSString class]] && filePath.length > 0) {
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            totalLength = [attributes[NSFileSize] unsignedLongLongValue];
        }
        if (totalLength == 0 && [blobData isKindOfClass:[NSData class]]) {
            totalLength = blobData.length;
        }

        response.contentType = mimeType;
        [response setHeader:@"bytes" forKey:@"Accept-Ranges"];

        BOOL hasRange = NO;
        BOOL satisfiable = YES;
        unsigned long long start = 0;
        unsigned long long end = totalLength > 0 ? (totalLength - 1) : 0;
        NSString *rangeFailureReason = nil;
        BOOL validRange = parseByteRangeHeader([request headerForKey:@"Range"],
                                               totalLength,
                                               &hasRange,
                                               &satisfiable,
                                               &start,
                                               &end,
                                               &rangeFailureReason);
        if (!validRange) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRange",
                                    @"message": rangeFailureReason ?: @"Range header is invalid"}];
            return;
        }

        if (hasRange && !satisfiable) {
            response.statusCode = 416;
            response.statusMessage = @"Range Not Satisfiable";
            [response setHeader:[NSString stringWithFormat:@"bytes */%llu", totalLength] forKey:@"Content-Range"];
            return;
        }

        if (hasRange) {
            response.statusCode = 206;
            response.statusMessage = @"Partial Content";
            [response setHeader:[NSString stringWithFormat:@"bytes %llu-%llu/%llu", start, end, totalLength]
                         forKey:@"Content-Range"];
        } else {
            response.statusCode = HttpStatusOK;
        }

        if ([filePath isKindOfClass:[NSString class]] && filePath.length > 0) {
            NSError *streamError = nil;
            HttpResponseBodyChunkProducer producer = blobFileChunkProducer(filePath, start, end, &streamError);
            if (!producer) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"BlobReadFailed",
                                        @"message": streamError.localizedDescription ?: @"Failed to stream blob"}];
                return;
            }
            [response setBodyChunkProducer:producer chunkedTransferEncoding:YES];
            return;
        }

        if (![blobData isKindOfClass:[NSData class]]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"BlobReadFailed", @"message": @"Blob payload unavailable"}];
            return;
        }

        if (hasRange) {
            NSUInteger offset = (NSUInteger)start;
            NSUInteger length = (NSUInteger)(end - start + 1);
            [response setBodyData:[blobData subdataWithRange:NSMakeRange(offset, length)]];
            return;
        }

        [response setBodyData:blobData];
    }];

    [dispatcher registerComAtprotoSyncSubscribeRepos:^(HttpRequest *request, HttpResponse *response) {
        setSubscribeReposUpgradeRequired(request, response);
    }];

    [dispatcher registerComAtprotoSyncGetRecord:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *did = [request queryParamForKey:@"did"];
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *rkey = [request queryParamForKey:@"rkey"];
        if (did.length == 0 || collection.length == 0 || rkey.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did, collection, or rkey"}];
            return;
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        NSError *recordError = nil;
        NSDictionary *record = [recordService getRecord:uri forDid:did error:&recordError];
        if (!record) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RecordNotFound",
                                    @"message": recordError.localizedDescription ?: @"Record not found"}];
            return;
        }

        NSError *repoError = nil;
        NSData *carData = [repositoryService getRepoContents:did since:nil error:&repoError];
        if (!carData || repoError) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound",
                                    @"message": repoError.localizedDescription ?: @"Repository not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = @"application/vnd.ipld.car";
        [response setBodyData:carData];
    }];

    [dispatcher registerComAtprotoSyncRequestCrawl:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *hostname = body[@"hostname"];
        if (![hostname isKindOfClass:[NSString class]] || [[hostname stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing hostname"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoSyncNotifyOfUpdate:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *hostname = body[@"hostname"];
        if (![hostname isKindOfClass:[NSString class]] || [[hostname stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing hostname"}];
            return;
        }

        PDS_LOG_INFO(@"Received notifyOfUpdate for hostname: %@ (deprecated, use requestCrawl)", hostname);

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request {
    return [self extractDIDFromAuthHeader:authHeader
                               jwtMinter:jwtMinter
                         adminController:adminController
                                 request:request
                                response:nil];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request
                              response:(HttpResponse *)response {
    if (!authHeader) return nil;
    NSString *token = nil;
    BOOL isDPoP = NO;
    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:7];
    } else if ([authHeader hasPrefix:@"DPoP "]) {
        token = [authHeader substringFromIndex:5];
        isDPoP = YES;
    } else {
        return nil;
    }

    NSString *dpopThumbprint = nil;
    if (isDPoP) {
        NSString *dpopProof = [request headerForKey:@"DPoP"];
        if (dpopProof.length == 0) {
            PDS_LOG_AUTH_WARN(@"Missing DPoP header for DPoP authorization");
            return nil;
        }

        NSString *host = [request headerForKey:@"Host"] ?: @"";
        NSString *scheme = nil;
        NSString *forwardedProto = [request headerForKey:@"X-Forwarded-Proto"];
        if (forwardedProto.length > 0) {
            scheme = forwardedProto;
        } else {
            NSString *lowercaseHost = [host lowercaseString];
            if ([lowercaseHost containsString:@"localhost"] || [lowercaseHost hasPrefix:@"127.0.0.1"] || [lowercaseHost hasPrefix:@"::1"]) {
                scheme = @"http";
            } else {
                scheme = @"https";
            }
        }

        NSMutableString *urlString = [NSMutableString string];
        if (host.length > 0) {
            [urlString appendFormat:@"%@://%@%@", scheme, host, request.path ?: @"/"];
            if (request.queryString.length > 0) {
                [urlString appendFormat:@"?%@", request.queryString];
            }
        }

        NSURL *dpopURL = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
        if (!dpopURL) {
            PDS_LOG_AUTH_WARN(@"Unable to construct DPoP URL for request");
            return nil;
        }

        NSString *requestedNonce = [request headerForKey:@"DPoP-Nonce"];
        if (requestedNonce.length == 0) {
            requestedNonce = nil;
        }

        NSError *dpopError = nil;
        if (![OAuth2DPoPProof verifyProof:dpopProof
                                   method:request.methodString
                                      url:dpopURL
                                    nonce:requestedNonce
                             requireNonce:YES
                            outThumbprint:&dpopThumbprint
                                    error:&dpopError]) {
            if ([dpopError.userInfo[@"use_dpop_nonce"] boolValue]) {
                if (response) {
                    response.statusCode = HttpStatusUnauthorized;
                    NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
                    if (nonce.length > 0) {
                        [response setHeader:nonce forKey:@"DPoP-Nonce"];
                    }
                    [response setHeader:@"DPoP error=\"use_dpop_nonce\"" forKey:@"WWW-Authenticate"];
                    [response setJsonBody:@{
                        @"error": @"use_dpop_nonce",
                        @"message": dpopError.localizedDescription ?: @"DPoP nonce required"
                    }];
                }
                return nil;
            }
            PDS_LOG_AUTH_WARN(@"Invalid DPoP proof: %@", dpopError.localizedDescription ?: @"unknown error");
            return nil;
        }
    }

    // Parse the JWT token
    NSError *parseError = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&parseError];
    if (!jwt || parseError) {
        PDS_LOG_HTTP_WARN(@"Failed to parse JWT token from authorization header");
        return nil;
    }

    // Create verifier and set expected issuer
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    if (jwtMinter) {
        verifier.keyManager = jwtMinter.keyManager;
        verifier.publicKey = jwtMinter.publicKey;
    }

    // Use configurable issuer from PDSConfiguration, default to localhost
    PDSConfiguration *configuration = [PDSConfiguration sharedConfiguration];
    NSString *expectedIssuer = jwtMinter.issuer ?: [configuration canonicalIssuerWithPortHint:0];
    verifier.expectedIssuer = expectedIssuer;
    verifier.expectedAudience = expectedIssuer; // Ensure tokens are for this PDS instance
    verifier.allowedAlgorithms = jwtAllowedAlgorithmsForMinter(jwtMinter);

    // Verify the JWT
    NSError *verifyError = nil;
    BOOL isValid = [verifier verifyJWT:jwt error:&verifyError];
    if (!isValid || verifyError) {
        NSLog(@"[AuthRegistry] JWT verification failed: %@. Expected issuer: %@, JWT issuer: %@, subject: %@", verifyError.localizedDescription, expectedIssuer, jwt.payload.iss, jwt.payload.sub);
        PDS_LOG_AUTH_WARN(@"JWT verification failed for request from IP: %@", request.remoteAddress ?: @"unknown");
        return nil;
    }

    // Phase 4: Enforce DPoP binding
    NSString *tokenJkt = jwt.payload.cnf[@"jkt"];
    if (isDPoP) {
        if (!tokenJkt) {
            NSLog(@"[AuthRegistry] DPoP used but token not bound");
            PDS_LOG_AUTH_WARN(@"DPoP authorization used with non-DPoP-bound token");
            return nil;
        }
        if (![CryptoUtils constantTimeCompare:tokenJkt to:dpopThumbprint]) {
            NSLog(@"[AuthRegistry] DPoP thumbprint mismatch");
            PDS_LOG_AUTH_WARN(@"DPoP thumbprint mismatch");
            return nil;
        }
    } else if (tokenJkt) {
        NSLog(@"[AuthRegistry] DPoP-bound token sent as Bearer");
        PDS_LOG_AUTH_WARN(@"DPoP-bound token sent as Bearer token");
        return nil;
    }

    // Extract DID from subject claim
    NSString *did = jwt.payload.sub;
    NSLog(@"[AuthRegistry] Validated JWT for subject: %@", did);
    if (!did || ![did hasPrefix:@"did:"]) {
        NSLog(@"[AuthRegistry] Invalid DID in subject: %@", did);
        PDS_LOG_AUTH_WARN(@"Invalid DID in JWT subject claim: %@", did);
        return nil;
    }

    NSError *takedownError = nil;
    BOOL isTakedown = [adminController isAccountTakedownActive:did error:&takedownError];
    if (takedownError) {
        PDS_LOG_AUTH_WARN(@"Failed to check takedown status for %@: %@", did, takedownError.localizedDescription);
        return nil;
    }
    if (isTakedown) {
        PDS_LOG_AUTH_WARN(@"Rejected request for suspended account %@", did);
        return nil;
    }

    return did;
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader controller:(PDSController *)controller request:(HttpRequest *)request response:(HttpResponse *)response {
    return [self extractDIDFromAuthHeader:authHeader
                               jwtMinter:controller.jwtMinter
                         adminController:controller.adminController
                                 request:request
                                response:response];
}

static void registerMethodsWithDispatcherUsingServices(Class registryClass,
                                                        XrpcDispatcher *dispatcher,
                                                        id<PDSAccountService> accountService,
                                                        PDSRecordService *recordService,
                                                        PDSBlobService *blobService,
                                                        PDSRepositoryService *repositoryService,
                                                        id<PDSAdminController> adminController,
                                                        PDSServiceDatabases *serviceDatabases,
                                                        PDSDatabasePool *userDatabasePool,
                                                        JWTMinter *jwtMinter,
                                                        PDSConfiguration *config,
                                                        id<PDSEmailProvider> emailProvider) {

    installXrpcProxyInterceptor(dispatcher, config);

    registerServerDescribeAndResolveLexiconMethods(dispatcher, config);
    registerServerAccountAndSessionMethods(dispatcher,
                                           jwtMinter,
                                           adminController,
                                           accountService,
                                           repositoryService,
                                           serviceDatabases,
                                           userDatabasePool,
                                           config,
                                           NO);
    
    [dispatcher registerComAtprotoIdentityResolveDid:^(HttpRequest *request, HttpResponse *response) {
        fprintf(stderr, "[resolveDid] Handler invoked\n");
        NSString *did = [request queryParamForKey:@"did"];
        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did parameter"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *doc = resolveDid(did, serviceDatabases, config, &error);
        if (error) {
             response.statusCode = HttpStatusNotFound;
             [response setJsonBody:@{@"error": @"NotFound", @"message": error.localizedDescription ?: @"DID not found"}];
             return;
        }
        if (!doc) {
             response.statusCode = HttpStatusNotFound;
             [response setJsonBody:@{@"error": @"NotFound", @"message": @"DID not found"}];
             return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:doc];
    }];

    registerTempUtilityMethods(dispatcher, serviceDatabases, jwtMinter, adminController);
    registerTempRevokeAccountCredentialsMethod(dispatcher, serviceDatabases, jwtMinter, adminController);

    [dispatcher registerComAtprotoServerGetAccount:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [registryClass extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *account = [accountService getAccountForDid:did error:&error];

        if (error || !account) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": @"Account not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:account];
    }];

    [dispatcher registerComAtprotoServerDeleteAccount:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *did = body[@"did"];
        NSString *password = body[@"password"];

        if (!did || !password) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did or password"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [accountService deleteAccount:did password:password error:&error];

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"AccountDeletionFailed", @"message": error.localizedDescription ?: @"Failed to delete account"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];
    }];

    [dispatcher registerComAtprotoServerCheckAccountStatus:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [registryClass extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *account = [accountService getAccountForDid:did error:&error];

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"valid"] = @(account != nil && !error);

        if (account[@"takedown"]) {
            result[@"takedown"] = account[@"takedown"];
        }

        if (error) {
            result[@"error"] = error.localizedDescription;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoServerActivateAccount:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [registryClass extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [adminController reinstateAccount:did error:&error];

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"ActivationFailed", @"message": error.localizedDescription ?: @"Failed to activate account"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];
    }];

    [dispatcher registerComAtprotoServerDeactivateAccount:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [registryClass extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSDictionary *body = request.jsonBody;
        NSString *reason = body[@"reason"];

        NSError *error = nil;
        BOOL success = [adminController takeDownAccount:did reason:reason ?: @"User deactivation" error:&error];

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"DeactivationFailed", @"message": error.localizedDescription ?: @"Failed to deactivate account"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];
    }];

    registerPhase1IdentityAndAccountMethods(dispatcher,
                                            jwtMinter,
                                            adminController,
                                            serviceDatabases,
                                            userDatabasePool,
                                            config,
                                            emailProvider);
    registerRepoCoreMethods(dispatcher,
                            jwtMinter,
                            adminController,
                            accountService,
                            recordService,
                            blobService,
                            repositoryService,
                            serviceDatabases);

    [dispatcher registerComAtprotoRepoUpdateRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [registryClass extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSDictionary *body = request.jsonBody;
        NSString *collection = body[@"collection"];
        NSString *rkey = body[@"rkey"];
        NSDictionary *record = body[@"record"];
        BOOL validate = [body[@"validate"] boolValue];

        if (!collection || !rkey || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing collection, rkey, or record"}];
            return;
        }

        PDSValidationMode mode = validate ? PDSValidationModeRequired : PDSValidationModeOff;
        NSError *error = nil;
        BOOL success = [recordService putRecord:collection rkey:rkey value:record forDid:did validationMode:mode error:&error];

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"RecordUpdateFailed", @"message": error.localizedDescription ?: @"Failed to update record"}];
            return;
        }

        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        NSDictionary *updatedRecord = [recordService getRecord:uri forDid:did error:nil];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:updatedRecord ?: @{@"uri": uri}];
    }];

    [dispatcher registerComAtprotoRepoGetBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [registryClass extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSString *cid = [request queryParamForKey:@"cid"];
        if (!cid) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing cid parameter"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *blobResult = [blobService getBlobWithCID:cid did:did error:&error];

        if (error || !blobResult) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"BlobNotFound", @"message": @"Blob not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:blobResult];
    }];

    registerSyncCoreMethods(dispatcher,
                            jwtMinter,
                            adminController,
                            serviceDatabases,
                            userDatabasePool,
                            recordService,
                            blobService,
                            repositoryService,
                            config);

    NSError *appViewDbError = nil;
    PDSDatabase *appViewDatabase = [serviceDatabases serviceDatabaseWithError:&appViewDbError];
    if (!appViewDatabase && appViewDbError) {
        PDS_LOG_WARN(@"Failed to open service database for app.bsky handlers: %@",
                     appViewDbError.localizedDescription ?: @"unknown error");
    }
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
    [dispatcher registerAppBskyActorGetProfile:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *profile = [actorService getProfileForActor:actor error:&error];
        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"ProfileNotFound", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:profile];
    }];

    [dispatcher registerComAtprotoSyncGetBlocks:^(HttpRequest *request, HttpResponse *response) {
        fprintf(stderr, "[getBlocks] Handler invoked\n");
        NSString *did = [request queryParamForKey:@"did"];
        NSString *cidsStr = [request queryParamForKey:@"cids"];
        if (!did || !cidsStr) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did or cids"}];
            return;
        }
        
        // Split cids string (assuming multiple cids are passed as repeating param or comma separated?)
        // Spec says array of strings. HttpRequest parser usually returns array if repeated?
        // Our XrpcDispatcher/HttpRequest might support `queryParamsForKey:`?
        // Or if it's "cids[]=..."
        // Or simply repeated "cids=...&cids=..."
        // HttpRequest `queryParamForKey` usually returns first or joined?
        // Let's assume it returns one if single, or we need to handle array.
        // If HttpRequest doesn't support array, we might fail conformant tests if multiple are passed.
        // But for now, let's assume one CID or check if we can get all values.
        // Assuming we parse comma separated?
        
        NSArray *cids = [request.queryParams[cidsStr] isKindOfClass:[NSArray class]] 
            ? (NSArray *)request.queryParams[@"cids"] 
            : @[cidsStr];
            
        // Wait, typical XRPC arrays are repeated params: `?cids=...&cids=...`
        // Inspect `HttpRequest.h`.
        // If `queryParamForKey` returns string, maybe `queryParams` dict contains array?
        // If we can't be sure, assume we handle single for now, or check implementation.
        // Let's assume request.queryParams (NSDictionary) holds arrays for duplicate keys if the parser supports it.
        // If not, we rely on "," separator as fallback.
        
        if (![cids isKindOfClass:[NSArray class]]) {
             // Maybe it's in the dict as a single object?
             id val = request.queryParams[@"cids"];
             if ([val isKindOfClass:[NSArray class]]) {
                 cids = val;
             } else if (val) {
                 cids = @[val];
             }
        }
        
        NSError *error = nil;
        NSData *carData = [repositoryService getBlocksForDid:did cids:cids error:&error];
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"GetBlocksFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        response.contentType = @"application/vnd.ipld.car";
        response.body = carData;
    }];

    [dispatcher registerComAtprotoSyncGetLatestCommit:^(HttpRequest *request, HttpResponse *response) {
        fprintf(stderr, "[getLatestCommit] Handler invoked\n");
        NSString *did = [request queryParamForKey:@"did"];
        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *result = [repositoryService getLatestCommitForDid:did error:&error];
        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RepoNotFound", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];


    [dispatcher registerComAtprotoModerationCreateReport:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        if (!body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [adminController moderateAccount:body error:&error];

        if (error) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"ModerationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoAdminUpdateSubjectStatus:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody;
        if (!body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }

        NSString *did = body[@"subject"][@"did"];
        NSString *reason = body[@"reason"];

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing subject DID"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [adminController takeDownAccount:did reason:reason error:&error];

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"UpdateFailed", @"message": error.localizedDescription ?: @"Failed to update status"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];
    }];

    [dispatcher registerComAtprotoAdminGetSubjectStatus:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *did = [request queryParamForKey:@"did"];
        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did parameter"}];
            return;
        }

        NSError *error = nil;
        BOOL isTakedown = [adminController isAccountTakedownActive:did error:&error];

        if (error) {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"subject": @{@"did": did},
            @"takedown": @(isTakedown)
        }];
    }];

    [dispatcher registerComAtprotoAdminGetAccountTakedown:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
        if (![did isKindOfClass:[NSString class]] || did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did parameter"}];
            return;
        }

        NSError *error = nil;
        BOOL isTakedown = [adminController isAccountTakedownActive:did error:&error];

        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"did": did,
            @"applied": @(isTakedown)
        }];
    }];

    registerAdminAccountMaintenanceMethods(dispatcher,
                                           serviceDatabases,
                                           jwtMinter,
                                           adminController);
    registerAdminAccountAndInviteMethods(dispatcher,
                                         serviceDatabases,
                                         jwtMinter,
                                         adminController);
    registerAdminModerationAndLabelMethods(dispatcher,
                                           serviceDatabases,
                                           jwtMinter,
                                           adminController,
                                           YES);

    [dispatcher registerComAtprotoAdminGetModerationReports:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSMutableDictionary *filters = [NSMutableDictionary dictionary];
        NSString *status = [request queryParamForKey:@"status"];
        NSString *reasonType = [request queryParamForKey:@"reasonType"];
        NSString *subjectDid = [request queryParamForKey:@"subjectDid"];
        NSString *reportedBy = [request queryParamForKey:@"reportedBy"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *limitStr = [request queryParamForKey:@"limit"];

        if (status) filters[@"status"] = status;
        if (reasonType) filters[@"reason_type"] = reasonType;
        if (subjectDid) filters[@"subject_did"] = subjectDid;
        if (reportedBy) filters[@"reported_by_did"] = reportedBy;

        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit > 100) limit = 100;

        NSError *error = nil;
        NSDictionary *result = [adminController queryReports:filters limit:limit cursor:cursor error:&error];

        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoAdminResolveReport:^(HttpRequest *request, HttpResponse *response) {
        if (!authorizeAdminRequest(request, response, serviceDatabases, jwtMinter, adminController)) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody;
        if (!body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }

        NSString *reportId = body[@"id"];
        NSString *status = body[@"status"];
        NSString *notes = body[@"notes"];
        NSString *adminDid = body[@"createdBy"];

        if (!reportId || !status) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing id or status"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [adminController resolveReport:reportId status:status resolvedBy:adminDid notes:notes error:&error];

        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ResolveFailed", @"message": error.localizedDescription ?: @"Failed to resolve report"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];
    }];

    [dispatcher registerComAtprotoLabelQueryLabels:^(HttpRequest *request, HttpResponse *response) {
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *since = [request queryParamForKey:@"since"];

        NSUInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit > 100) limit = 100;

        NSError *error = nil;
        NSDictionary *result = [adminController getLabels:@{
            @"collection": collection ?: @"",
            @"cursor": cursor ?: @"",
            @"limit": @(limit),
            @"since": since ?: @""
        } error:&error];

        if (error) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
}

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                            controller:(PDSController *)controller {
    if (!dispatcher || !controller) {
        return;
    }
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    registerMethodsWithDispatcherUsingServices(self,
                                                dispatcher,
                                                controller.accountService,
                                                controller.recordService,
                                                controller.blobService,
                                                controller.repositoryService,
                                                controller.adminController,
                                                controller.serviceDatabases,
                                                controller.userDatabasePool,
                                                controller.jwtMinter,
                                                config,
                                                nil);
}

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           application:(PDSApplication *)application {
    if (!dispatcher || !application) {
        return;
    }
    registerMethodsWithDispatcherUsingServices(self,
                                                dispatcher,
                                                application.accountService,
                                                application.recordService,
                                                application.blobService,
                                                application.repositoryService,
                                                application.adminController,
                                                application.serviceDatabases,
                                                application.userDatabasePool,
                                                application.jwtMinter,
                                                application.configuration,
                                                application.emailProvider);
}

@end
