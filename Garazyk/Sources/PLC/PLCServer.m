#import "PLC/PLCServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCMetrics.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"
#import "Core/NSDateFormatter+ATProto.h"

static const NSUInteger kPLCMaxOperationBytes = 4000;
static const NSUInteger kPLCMaxAlsoKnownAsEntries = 10;
static const NSUInteger kPLCMaxAlsoKnownAsLength = 258;
static const NSUInteger kPLCMaxRotationKeyEntries = 10;
static const NSUInteger kPLCMaxServiceEntries = 10;
static const NSUInteger kPLCMaxServiceTypeLength = 256;
static const NSUInteger kPLCMaxServiceEndpointLength = 512;
static const NSUInteger kPLCMaxVerificationMethodEntries = 10;
static const NSUInteger kPLCMaxIdentifierLength = 32;
static const NSUInteger kPLCMaxDidKeyLength = 256;

static BOOL PLCValidateDidKey(NSString *key, NSError **error) {
    if (![key isKindOfClass:[NSString class]] || ![key hasPrefix:@"did:key:"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid did:key format"}];
        }
        return NO;
    }
    if (key.length > kPLCMaxDidKeyLength) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"did:key too long"}];
        }
        return NO;
    }
    NSString *multibase = [key substringFromIndex:@"did:key:".length];
    if (multibase.length < 2 || [multibase characterAtIndex:0] != 'z') {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported did:key multibase (expected base58btc 'z')"}];
        }
        return NO;
    }
    NSString *base58 = [multibase substringFromIndex:1];
    NSData *decoded = [CID base58btcDecode:base58];
    if (!decoded || decoded.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid base58btc in did:key"}];
        }
        return NO;
    }
    return YES;
}

static BOOL PLCValidateIncomingOperation(NSDictionary *op, NSError **error) {
    NSError *cborError = nil;
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:op error:&cborError];
    if (!cbor) {
        if (error) *error = cborError;
        return NO;
    }
    if (cbor.length > kPLCMaxOperationBytes) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Operation too large"}];
        }
        return NO;
    }

    NSString *type = op[@"type"];
    if (![type isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Operation missing type"}];
        }
        return NO;
    }

    NSString *sig = op[@"sig"];
    if (![sig isKindOfClass:[NSString class]] || [sig hasSuffix:@"="]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature encoding"}];
        }
        return NO;
    }

    if ([type isEqualToString:@"plc_tombstone"]) {
        NSSet<NSString *> *allowedKeys = [NSSet setWithArray:@[@"type", @"prev", @"sig"]];
        for (NSString *key in op) {
            if (![allowedKeys containsObject:key]) {
                if (error) {
                    *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                                 code:7
                                             userInfo:@{NSLocalizedDescriptionKey: @"Unexpected field in tombstone operation"}];
                }
                return NO;
            }
        }
        id prev = op[@"prev"];
        if (![prev isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:7
                                         userInfo:@{NSLocalizedDescriptionKey: @"Tombstone requires prev"}];
            }
            return NO;
        }
        return YES;
    }

    if (![type isEqualToString:@"plc_operation"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:8
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported operation type"}];
        }
        return NO;
    }

    NSSet<NSString *> *allowedKeys = [NSSet setWithArray:@[
        @"type", @"rotationKeys", @"verificationMethods", @"alsoKnownAs", @"services", @"prev", @"sig"
    ]];
    for (NSString *key in op) {
        if (![allowedKeys containsObject:key]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:9
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unexpected field in plc_operation"}];
            }
            return NO;
        }
    }

    NSArray *alsoKnownAs = op[@"alsoKnownAs"];
    if (![alsoKnownAs isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:9
                                     userInfo:@{NSLocalizedDescriptionKey: @"alsoKnownAs must be array"}];
        }
        return NO;
    }
    if (alsoKnownAs.count > kPLCMaxAlsoKnownAsEntries) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many alsoKnownAs entries"}];
        }
        return NO;
    }
    for (id aka in alsoKnownAs) {
        if (![aka isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:11
                                         userInfo:@{NSLocalizedDescriptionKey: @"alsoKnownAs entries must be strings"}];
            }
            return NO;
        }
        if (![aka hasPrefix:@"at://"]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:25
                                         userInfo:@{NSLocalizedDescriptionKey: @"alsoKnownAs entry must start with at://"}];
            }
            return NO;
        }
        if ([(NSString *)aka length] > kPLCMaxAlsoKnownAsLength) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:12
                                         userInfo:@{NSLocalizedDescriptionKey: @"alsoKnownAs entry too long"}];
            }
            return NO;
        }
    }

    NSDictionary *services = op[@"services"];
    if (services && ![services isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:13
                                     userInfo:@{NSLocalizedDescriptionKey: @"services must be dictionary"}];
        }
        return NO;
    }
    if (services.count > kPLCMaxServiceEntries) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:14
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many services entries"}];
        }
        return NO;
    }
    for (NSString *key in services) {
        NSDictionary *service = services[key];
        if (![service isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:15
                                         userInfo:@{NSLocalizedDescriptionKey: @"service entries must be dictionaries"}];
            }
            return NO;
        }
        NSString *endpoint = service[@"endpoint"];
        if (![endpoint isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:16
                                         userInfo:@{NSLocalizedDescriptionKey: @"service endpoint must be string"}];
            }
            return NO;
        }
        // Reject non-HTTPS endpoints (allow localhost for testing)
        if (![endpoint hasPrefix:@"https://"] && ![endpoint hasPrefix:@"http://localhost:"] && ![endpoint hasPrefix:@"http://127.0.0.1:"]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:26
                                         userInfo:@{NSLocalizedDescriptionKey: @"service endpoint must be HTTPS (except localhost)"}];
            }
            return NO;
        }
    }

    if (alsoKnownAs.count > kPLCMaxAlsoKnownAsEntries) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many alsoKnownAs entries"}];
        }
        return NO;
    }
    NSMutableSet<NSString *> *akaSet = [NSMutableSet set];
    for (id aka in alsoKnownAs) {
        if (![aka isKindOfClass:[NSString class]] || [aka length] > kPLCMaxAlsoKnownAsLength) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:11
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid alsoKnownAs entry"}];
            }
            return NO;
        }
        if ([akaSet containsObject:aka]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:12
                                         userInfo:@{NSLocalizedDescriptionKey: @"Duplicate alsoKnownAs entry"}];
            }
            return NO;
        }
        [akaSet addObject:aka];
    }

    NSArray *rotationKeys = op[@"rotationKeys"];
    if (![rotationKeys isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:13
                                     userInfo:@{NSLocalizedDescriptionKey: @"rotationKeys must be array"}];
        }
        return NO;
    }
    if (rotationKeys.count < 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:13
                                     userInfo:@{NSLocalizedDescriptionKey: @"rotationKeys must contain at least 1 key"}];
        }
        return NO;
    }
    if (rotationKeys.count > kPLCMaxRotationKeyEntries) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:14
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many rotationKeys entries"}];
        }
        return NO;
    }
    for (NSString *key in rotationKeys) {
        if (!PLCValidateDidKey(key, error)) {
            return NO;
        }
    }
    NSSet *uniqueRotationKeys = [NSSet setWithArray:rotationKeys];
    if (uniqueRotationKeys.count != rotationKeys.count) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:15
                                     userInfo:@{NSLocalizedDescriptionKey: @"rotationKeys must not contain duplicates"}];
        }
        return NO;
    }

    // services already validated above

    NSDictionary *verificationMethods = op[@"verificationMethods"];
    if (![verificationMethods isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:21
                                     userInfo:@{NSLocalizedDescriptionKey: @"verificationMethods must be object"}];
        }
        return NO;
    }
    if (verificationMethods.count > kPLCMaxVerificationMethodEntries) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:22
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many verificationMethods entries"}];
        }
        return NO;
    }
    for (NSString *methodId in verificationMethods) {
        if (methodId.length > kPLCMaxIdentifierLength) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:23
                                         userInfo:@{NSLocalizedDescriptionKey: @"verificationMethod id too long"}];
            }
            return NO;
        }
        NSString *key = verificationMethods[methodId];
        if (![key isKindOfClass:[NSString class]] || key.length > kPLCMaxDidKeyLength) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:24
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid verificationMethod key"}];
            }
            return NO;
        }
    }

    return YES;
}

@interface PLCServer ()
@property (nonatomic, strong) id<PLCStore> store;
@property (nonatomic, strong) PLCAuditor *auditor;
@property (nonatomic, strong) HttpServer *httpServer;
@property (nonatomic, copy, nullable) NSString *adminSecret;
@end

@implementation PLCServer

- (instancetype)initWithStore:(id<PLCStore>)store auditor:(PLCAuditor *)auditor port:(NSUInteger)port {
    return [self initWithStore:store auditor:auditor host:@"127.0.0.1" port:port];
}

- (instancetype)initWithStore:(id<PLCStore>)store auditor:(PLCAuditor *)auditor adminSecret:(NSString *)adminSecret port:(NSUInteger)port {
    return [self initWithStore:store auditor:auditor adminSecret:adminSecret host:@"127.0.0.1" port:port];
}

- (instancetype)initWithStore:(id<PLCStore>)store auditor:(PLCAuditor *)auditor host:(NSString *)host port:(NSUInteger)port {
    return [self initWithStore:store auditor:auditor adminSecret:nil host:host port:port];
}

- (instancetype)initWithStore:(id<PLCStore>)store auditor:(PLCAuditor *)auditor adminSecret:(NSString *)adminSecret host:(NSString *)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        _store = store;
        _auditor = auditor;
        _adminSecret = [adminSecret copy];
        _httpServer = [HttpServer serverWithHost:host port:port];
        [HttpResponse setDefaultServerHeader:@"campagnola/1.0.0 (garazyk)"];
        [self setupRoutes];
    }
    return self;
}

- (void)setCorsHeaders:(HttpResponse *)response forRequest:(HttpRequest *)request {
    NSString *origin = [request headerForKey:@"Origin"];
    if (origin && ([origin hasPrefix:@"http://127.0.0.1"] || [origin hasPrefix:@"http://localhost"])) {
        [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"true" forKey:@"Access-Control-Allow-Credentials"];
    } else if (origin) {
        [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"true" forKey:@"Access-Control-Allow-Credentials"];
    } else {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    }

    [response setHeader:@"GET, POST, OPTIONS, HEAD" forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:@"DPoP, Authorization, Content-Type, *" forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:@"DPoP-Nonce, WWW-Authenticate" forKey:@"Access-Control-Expose-Headers"];
    [response setHeader:@"true" forKey:@"Access-Control-Allow-Private-Network"];
    [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
    [response setHeader:@"Origin" forKey:@"Vary"];
}

- (void)setupRoutes {
    __weak typeof(self) weakSelf = self;

    // OPTIONS preflight routes for CORS
    RequestHandler optionsHandler = ^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        resp.statusCode = HttpStatusOK;
    };
    [self.httpServer addRoute:@"OPTIONS" path:@"/" handler:optionsHandler];
    [self.httpServer addRoute:@"OPTIONS" path:@"/_health" handler:optionsHandler];
    [self.httpServer addRoute:@"OPTIONS" path:@"/_list" handler:optionsHandler];
    [self.httpServer addRoute:@"OPTIONS" path:@"/_metrics" handler:optionsHandler];
    [self.httpServer addRoute:@"OPTIONS" path:@"/export" handler:optionsHandler];
    [self.httpServer addRoute:@"OPTIONS" path:@"/:did" handler:optionsHandler];
    [self.httpServer addRoute:@"OPTIONS" path:@"/:did/log" handler:optionsHandler];
    [self.httpServer addRoute:@"OPTIONS" path:@"/:did/log/last" handler:optionsHandler];
    [self.httpServer addRoute:@"OPTIONS" path:@"/:did/data" handler:optionsHandler];

    [self.httpServer addRoute:@"GET" path:@"/_health" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        [[PLCMetrics sharedMetrics] recordRequest];
        resp.statusCode = HttpStatusOK;
        [resp setJsonBody:@{@"status": @"ok"}];
    }];

    [self.httpServer addRoute:@"GET" path:@"/_list" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        [[PLCMetrics sharedMetrics] recordRequest];
        NSError *error = nil;
        NSArray<NSString *> *dids = [weakSelf.store getAllDIDsWithError:&error];
        if (error) {
            [[PLCMetrics sharedMetrics] recordError];
            resp.statusCode = HttpStatusInternalServerError;
            [resp setJsonBody:@{@"error": error.localizedDescription}];
        } else {
            resp.statusCode = HttpStatusOK;
            [resp setJsonBody:dids];
        }
    }];

    [self.httpServer addRoute:@"GET" path:@"/_metrics" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        [[PLCMetrics sharedMetrics] recordRequest];
        NSString *metrics = [[PLCMetrics sharedMetrics] renderMetrics];
        resp.statusCode = HttpStatusOK;
        resp.contentType = @"text/plain; charset=utf-8";
        [resp setBodyString:metrics];
    }];

    [self.httpServer addRoute:@"GET" path:@"/favicon.ico" handler:^(HttpRequest *req, HttpResponse *resp) {
        resp.statusCode = HttpStatusNoContent;
        resp.contentType = @"image/x-icon";
        [resp setBodyData:[NSData data]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        resp.statusCode = HttpStatusOK;
        resp.contentType = @"text/plain; charset=utf-8";
        [resp setBodyString:@"___                                                _        \n  / (_)                                              | |       \n |      __,   _  _  _     _   __,   __,  _  _    __  | |  __,  \n |     /  |  / |/ |/ |  |/ \\_/  |  /  | / |/ |  /  \\_|/  /  |  \n  \\___/\\_/|_/  |  |  |_/|__/ \\_/|_/\\_/|/  |  |_/\\__/ |__/\\_/|_/\n                       /|            /|                        \n                       \\|            \\| \n"];
    }];

    [self.httpServer addRoute:@"GET" path:@"/export" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        [weakSelf handleExport:req response:resp];
    }];

    [self.httpServer addRoute:@"GET" path:@"/:did/log/last" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        [weakSelf handleGetLatestLog:req response:resp];
    }];

    [self.httpServer addRoute:@"GET" path:@"/:did/log" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        [weakSelf handleGetLog:req response:resp includeNullified:NO includeMetadata:NO];
    }];

    [self.httpServer addRoute:@"GET" path:@"/:did/data" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        [weakSelf handleGetData:req response:resp];
    }];

    [self.httpServer addRoute:@"POST" path:@"/:did" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        [[PLCMetrics sharedMetrics] recordRequest];
        [weakSelf handlePostDID:req response:resp];
    }];

    [self.httpServer addRoute:@"GET" path:@"/:did" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        NSString *did = [req.pathParameters[@"did"] stringByRemovingPercentEncoding];
        if ([did hasPrefix:@"did:plc:"]) {
            [[PLCMetrics sharedMetrics] recordRequest];
            [weakSelf handleGetDID:req response:resp];
        } else {
            // No fallback here, let other routes match or 404
            resp.statusCode = HttpStatusNotFound;
            resp.statusMessage = [HttpResponse defaultMessageForCode:HttpStatusNotFound];
        }
    }];
}

- (void)handleGetDID:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *did = [req.pathParameters[@"did"] stringByRemovingPercentEncoding];
    if (!did) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing DID"}];
        return;
    }
    
    NSError *error = nil;
    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:did includeNullified:NO error:&error];
    if (error) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": error.localizedDescription}];
        return;
    }
    
    if (!history || history.count == 0) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"DID not found"}];
        return;
    }
    
    PLCDIDState *state = [PLCStateReplayer replayHistory:history error:&error];
    if (!state) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": @"Failed to replay history"}];
        return;
    }
    
    if (state.tombstoned) {
        resp.statusCode = 410;
        [resp setJsonBody:@{@"message": [NSString stringWithFormat:@"DID not available: %@", did]}];
        return;
    }
    
    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:[state toDIDDocument]];
    resp.contentType = @"application/did+json; charset=utf-8";
}

- (void)handleGetLog:(HttpRequest *)req
           response:(HttpResponse *)resp
  includeNullified:(BOOL)includeNullified
    includeMetadata:(BOOL)includeMetadata {
    NSString *did = [req.pathParameters[@"did"] stringByRemovingPercentEncoding];
    if (!did) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing DID"}];
        return;
    }
    
    NSError *error = nil;
    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:did includeNullified:includeNullified error:&error];
    if (error) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": @"Internal server error"}];
        return;
    }
    
    if (!history) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"DID not found"}];
        return;
    }
    
    NSMutableArray *historyDicts = [NSMutableArray array];
    for (PLCOperation *op in history) {
        if (includeMetadata) {
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"did"] = did;
            entry[@"operation"] = [op toDictionary];
            if (op.cid) entry[@"cid"] = op.cid;
            entry[@"nullified"] = @(op.nullified);
            if (op.createdAt) {
                entry[@"createdAt"] = [NSDateFormatter atproto_stringFromDate:op.createdAt];
            }
            [historyDicts addObject:entry];
        } else {
            [historyDicts addObject:[op toDictionary]];
        }
    }
    
    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:historyDicts];
}

- (void)handlePostDID:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *did = [req.pathParameters[@"did"] stringByRemovingPercentEncoding];
    if (!did) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing DID"}];
        return;
    }
    
    NSDictionary *json = req.jsonBody;
    if (!json) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing JSON body"}];
        return;
    }

    NSError *validationError = nil;
    if (!PLCValidateIncomingOperation(json, &validationError)) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": validationError.localizedDescription ?: @"Invalid operation"}];
        return;
    }
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    if (!op) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": [NSString stringWithFormat:@"Invalid operation format: %@", error.localizedDescription]}];
        return;
    }

    // Enforce DID consistency with path if present in payload.
    NSString *payloadDid = op.data[@"did"];
    if (payloadDid && [payloadDid isKindOfClass:[NSString class]] && ![payloadDid isEqualToString:did]) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"DID in payload does not match path"}];
        return;
    }

    op.did = did;

    // Ensure create/genesis operations derive the path DID (official PLC behavior).
    NSError *historyError = nil;
    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:did includeNullified:NO error:&historyError];
    if (historyError) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": @"Failed to fetch operation history"}];
        return;
    }
    if (!history || history.count == 0) {
        if (op.prev != nil) {
            [[PLCMetrics sharedMetrics] recordError];
            resp.statusCode = HttpStatusBadRequest;
            [resp setJsonBody:@{@"error": @"Genesis operation must have null prev"}];
            return;
        }
        NSString *expectedDid = [PLCOperation calculateDIDForSignedOperation:[op toDictionary]];
        if (expectedDid.length > 0 && ![expectedDid isEqualToString:did]) {
            PDS_LOG_CORE_ERROR(@"PLC genesis DID mismatch for %@: expected %@", did, expectedDid);
            [[PLCMetrics sharedMetrics] recordError];
            resp.statusCode = HttpStatusBadRequest;
            [resp setJsonBody:@{@"error": @"Genesis operation does not match DID"}];
            return;
        }
    }
    
    // Validate using auditor
    NSArray<NSString *> *nullified = nil;
    if (![self.auditor verifyOperation:op proposedDate:[NSDate date] nullifiedCIDs:&nullified error:&error]) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": [NSString stringWithFormat:@"Audit failed: %@", error.localizedDescription]}];
        return;
    }
    
    // Append to store
    if (![self.store appendOperation:op nullifyCIDs:nullified ?: @[] error:&error]) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": [NSString stringWithFormat:@"Failed to append: %@", error.localizedDescription]}];
        return;
    }
    
    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:@{@"status": @"ok"}];
}

- (void)handleGetLatestLog:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *did = [req.pathParameters[@"did"] stringByRemovingPercentEncoding];
    if (!did) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing DID"}];
        return;
    }

    NSError *error = nil;
    PLCOperation *op = [self.store getLatestOperationForDID:did error:&error];
    if (error) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": error.localizedDescription}];
        return;
    }

    if (!op) {
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"DID not found"}];
        return;
    }

    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:[op toDictionary]];
}

- (void)handleGetData:(HttpRequest *)req response:(HttpResponse *)resp {
    // Per did-method-plc spec, /:did/data returns the current DID state data
    // (operation content without sig/prev/type), plus the did field.
    NSString *did = [req.pathParameters[@"did"] stringByRemovingPercentEncoding];
    if (!did) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing DID"}];
        return;
    }

    NSError *error = nil;
    PLCOperation *op = [self.store getLatestOperationForDID:did error:&error];
    if (error) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": error.localizedDescription}];
        return;
    }

    if (!op) {
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"DID not found"}];
        return;
    }

    // Return op.data (unsigned content) + did, excluding sig/prev/type
    // Per did-method-plc spec, /:did/data returns the current DID state:
    // {did, rotationKeys, verificationMethods, alsoKnownAs, services}
    NSMutableDictionary *data = [op.data mutableCopy];
    data[@"did"] = did;
    [data removeObjectForKey:@"prev"];
    [data removeObjectForKey:@"type"];
    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:[data copy]];
}

- (void)handleExport:(HttpRequest *)req response:(HttpResponse *)resp {
    [[PLCMetrics sharedMetrics] recordRequest];
    
    NSString *countStr = req.queryParams[@"count"];
    __block NSInteger remaining = 10;
    if (countStr) {
        remaining = [countStr integerValue];
        if (remaining < 1) remaining = 10;
        if (remaining > 1000) remaining = 1000;
    }
    
    NSString *afterStr = req.queryParams[@"after"];
    __block NSDate *cursorDate = nil;
    if (afterStr) {
        cursorDate = [NSDateFormatter atproto_dateFromString:afterStr];
    }
    
    resp.statusCode = HttpStatusOK;
    resp.contentType = @"application/jsonlines; charset=utf-8";
    
    __weak typeof(self) weakSelf = self;
    [resp setBodyChunkProducer:^NSData * _Nullable(NSError * _Nullable __autoreleasing * _Nullable error) {
        if (remaining <= 0) return [NSData data]; // Done
        
        NSInteger batchSize = MIN(remaining, 100);
        NSArray<PLCOperation *> *ops = [weakSelf.store exportOperationsAfter:cursorDate count:batchSize error:error];
        if (!ops || ops.count == 0) return [NSData data]; // Done or error
        
        NSMutableData *chunkData = [NSMutableData data];
        for (PLCOperation *op in ops) {
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"did"] = op.did;
            entry[@"operation"] = [op toDictionary];
            entry[@"cid"] = op.cid;
            entry[@"nullified"] = @(op.nullified);
            entry[@"createdAt"] = [NSDateFormatter atproto_stringFromDate:op.createdAt ?: [NSDate date]];
            
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
            if (jsonData) {
                [chunkData appendData:jsonData];
                [chunkData appendBytes:"\n" length:1];
            }
            cursorDate = op.createdAt;
        }
        
        remaining -= ops.count;
        return [chunkData copy];
    } chunkedTransferEncoding:YES];
}

- (BOOL)startWithError:(NSError **)error {
    return [self.httpServer startWithError:error];
}

- (void)stop {
    [self.httpServer stop];
}

@end
