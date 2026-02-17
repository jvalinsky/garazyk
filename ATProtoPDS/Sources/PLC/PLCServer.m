#import "PLC/PLCServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCMetrics.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"

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

    NSDictionary *services = op[@"services"];
    if (![services isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:15
                                     userInfo:@{NSLocalizedDescriptionKey: @"services must be object"}];
        }
        return NO;
    }
    if (services.count > kPLCMaxServiceEntries) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:16
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many service entries"}];
        }
        return NO;
    }
    for (NSString *serviceId in services) {
        if (serviceId.length > kPLCMaxIdentifierLength) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:17
                                         userInfo:@{NSLocalizedDescriptionKey: @"Service id too long"}];
            }
            return NO;
        }
        NSDictionary *service = services[serviceId];
        if (![service isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:18
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid service entry"}];
            }
            return NO;
        }
        NSString *serviceType = service[@"type"];
        NSString *endpoint = service[@"endpoint"];
        if (![serviceType isKindOfClass:[NSString class]] || serviceType.length > kPLCMaxServiceTypeLength ||
            ![endpoint isKindOfClass:[NSString class]] || endpoint.length > kPLCMaxServiceEndpointLength) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:19
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid service entry"}];
            }
            return NO;
        }
    }

    NSDictionary *verificationMethods = op[@"verificationMethods"];
    if (![verificationMethods isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:20
                                     userInfo:@{NSLocalizedDescriptionKey: @"verificationMethods must be object"}];
        }
        return NO;
    }
    if (verificationMethods.count > kPLCMaxVerificationMethodEntries) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:21
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many verificationMethods entries"}];
        }
        return NO;
    }
    for (NSString *methodId in verificationMethods) {
        if (methodId.length > kPLCMaxIdentifierLength) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:22
                                         userInfo:@{NSLocalizedDescriptionKey: @"Verification method id too long"}];
            }
            return NO;
        }
        NSString *key = verificationMethods[methodId];
        if (![key isKindOfClass:[NSString class]] || key.length > kPLCMaxDidKeyLength) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                             code:23
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid verification method key"}];
            }
            return NO;
        }
        if (!PLCValidateDidKey(key, error)) {
            return NO;
        }
    }

    id prevValue = op[@"prev"];
    if (!(prevValue == [NSNull null] || [prevValue isKindOfClass:[NSString class]])) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:24
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid prev value"}];
        }
        return NO;
    }

    return YES;
}

@interface PLCServer ()
@property (nonatomic, strong) id<PLCStore> store;
@property (nonatomic, strong) PLCAuditor *auditor;
@property (nonatomic, strong) HttpServer *httpServer;

- (void)serveStaticFile:(NSString *)path response:(HttpResponse *)resp;
- (NSString *)assetsPath;
@end

@implementation PLCServer

- (instancetype)initWithStore:(id<PLCStore>)store auditor:(PLCAuditor *)auditor port:(NSUInteger)port {
    self = [super init];
    if (self) {
        _store = store;
        _auditor = auditor;
        _httpServer = [HttpServer serverWithHost:@"127.0.0.1" port:port];
        [self setupRoutes];
    }
    return self;
}

- (void)setupRoutes {
    __weak typeof(self) weakSelf = self;
    
    [self.httpServer addRoute:@"GET" path:@"/_health" handler:^(HttpRequest *req, HttpResponse *resp) {
        [[PLCMetrics sharedMetrics] recordRequest];
        resp.statusCode = HttpStatusOK;
        [resp setJsonBody:@{@"status": @"ok"}];
    }];
    
    [self.httpServer addRoute:@"GET" path:@"/_list" handler:^(HttpRequest *req, HttpResponse *resp) {
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
        [[PLCMetrics sharedMetrics] recordRequest];
        NSString *metrics = [[PLCMetrics sharedMetrics] renderMetrics];
        resp.statusCode = HttpStatusOK;
        resp.contentType = @"text/plain; charset=utf-8";
        [resp setBodyString:metrics];
    }];

    [self.httpServer addRoute:@"GET" path:@"/" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf serveStaticFile:@"index.html" response:resp];
    }];

    [self.httpServer addRoute:@"GET" path:@"/css/:file" handler:^(HttpRequest *req, HttpResponse *resp) {
        NSString *file = req.pathParameters[@"file"];
        [weakSelf serveStaticFile:[NSString stringWithFormat:@"css/%@", file] response:resp];
    }];

    [self.httpServer addRoute:@"GET" path:@"/js/:file" handler:^(HttpRequest *req, HttpResponse *resp) {
        NSString *file = req.pathParameters[@"file"];
        [weakSelf serveStaticFile:[NSString stringWithFormat:@"js/%@", file] response:resp];
    }];
    
    [self.httpServer addRoute:@"GET" path:@"/:did" handler:^(HttpRequest *req, HttpResponse *resp) {
        [[PLCMetrics sharedMetrics] recordRequest];
        NSString *did = req.pathParameters[@"did"];
        if ([did hasPrefix:@"did:plc:"]) {
            [weakSelf handleGetDID:req response:resp];
        } else {
            // Fallback to static files if it doesn't look like a DID
            [weakSelf serveStaticFile:did response:resp];
        }
    }];
    
    [self.httpServer addRoute:@"GET" path:@"/:did/log" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleGetLog:req response:resp includeNullified:NO includeMetadata:NO];
    }];
    
    [self.httpServer addRoute:@"GET" path:@"/:did/log/audit" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleGetLog:req response:resp includeNullified:YES includeMetadata:YES];
    }];
    
    [self.httpServer addRoute:@"GET" path:@"/export" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleExport:req response:resp];
    }];

    [self.httpServer addRoute:@"GET" path:@"/:did/log/last" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleGetLatestLog:req response:resp];
    }];

    [self.httpServer addRoute:@"GET" path:@"/:did/data" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleGetData:req response:resp];
    }];

    [self.httpServer addRoute:@"POST" path:@"/:did" handler:^(HttpRequest *req, HttpResponse *resp) {
        [[PLCMetrics sharedMetrics] recordRequest];
        [weakSelf handlePostDID:req response:resp];
    }];
}

- (void)handleGetDID:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *did = req.pathParameters[@"did"];
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
        resp.statusCode = 410; // Gone
        [resp setJsonBody:@{@"message": [NSString stringWithFormat:@"DID not available: %@", did]}];
        return;
    }
    
    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:[state toDIDDocument]];
}

- (void)handleGetLog:(HttpRequest *)req
           response:(HttpResponse *)resp
  includeNullified:(BOOL)includeNullified
    includeMetadata:(BOOL)includeMetadata {
    NSString *did = req.pathParameters[@"did"];
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
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
                formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
                entry[@"createdAt"] = [formatter stringFromDate:op.createdAt];
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
    NSString *did = req.pathParameters[@"did"];
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
        NSString *expectedDid = [PLCOperation calculateDIDForData:op.data];
        if (expectedDid.length > 0 && ![expectedDid isEqualToString:did]) {
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
    NSString *did = req.pathParameters[@"did"];
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
    // Spec says "basically just an op". Reusing getLatestLog logic.
    [self handleGetLatestLog:req response:resp];
}

- (void)handleExport:(HttpRequest *)req response:(HttpResponse *)resp {
    [[PLCMetrics sharedMetrics] recordRequest];
    
    NSString *countStr = req.queryParams[@"count"];
    NSInteger count = 10;
    if (countStr) {
        count = [countStr integerValue];
        if (count < 1) count = 10;
        if (count > 1000) count = 1000;
    }
    
    NSString *afterStr = req.queryParams[@"after"];
    NSDate *afterDate = nil;
    if (afterStr) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"; // Try ms precision first
        afterDate = [formatter dateFromString:afterStr];
        if (!afterDate) {
            formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'"; // Try seconds precision
            afterDate = [formatter dateFromString:afterStr];
        }
    }
    
    NSError *error = nil;
    NSArray<PLCOperation *> *ops = [self.store exportOperationsAfter:afterDate count:count error:&error];
    if (error) {
        [[PLCMetrics sharedMetrics] recordError];
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": error.localizedDescription}];
        return;
    }
    
    NSMutableString *jsonLines = [NSMutableString string];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    
    for (PLCOperation *op in ops) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"did"] = op.did;
        entry[@"operation"] = [op toDictionary];
        entry[@"cid"] = op.cid;
        entry[@"nullified"] = @(op.nullified);
        entry[@"createdAt"] = [formatter stringFromDate:op.createdAt ?: [NSDate date]];
        
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
        if (jsonData) {
            NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            [jsonLines appendString:jsonStr];
            [jsonLines appendString:@"\n"];
        }
    }
    
    resp.statusCode = HttpStatusOK;
    resp.contentType = @"application/jsonlines; charset=utf-8";
    [resp setBodyString:jsonLines];
}

- (BOOL)startWithError:(NSError **)error {
    return [self.httpServer startWithError:error];
}

- (void)stop {
    [self.httpServer stop];
}

#pragma mark - Static Files

- (void)serveStaticFile:(NSString *)path response:(HttpResponse *)resp {
    NSString *assets = [self assetsPath];
    if (!assets) {
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"Assets not found"}];
        return;
    }

    if (path.length == 0 || [path hasPrefix:@"/"] || [path containsString:@".."]) {
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"File not found"}];
        return;
    }

    NSString *fullPath = [[assets stringByAppendingPathComponent:path] stringByStandardizingPath];
    NSString *basePath = [assets stringByStandardizingPath];
    if (![fullPath hasPrefix:[basePath stringByAppendingString:@"/"]]) {
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"File not found"}];
        return;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"File not found", @"path": path}];
        return;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:fullPath];
    if (!data) {
        resp.statusCode = HttpStatusInternalServerError;
        return;
    }
    
    NSString *extension = [path pathExtension].lowercaseString;
    NSString *contentType = @"text/plain";
    if ([extension isEqualToString:@"html"]) contentType = @"text/html; charset=utf-8";
    else if ([extension isEqualToString:@"css"]) contentType = @"text/css; charset=utf-8";
    else if ([extension isEqualToString:@"js"]) contentType = @"application/javascript; charset=utf-8";
    else if ([extension isEqualToString:@"json"]) contentType = @"application/json; charset=utf-8";
    
    // Explicitly set the header to ensure it overrides any defaults
    [resp setHeader:contentType forKey:@"Content-Type"];
    resp.contentType = contentType;
    resp.statusCode = HttpStatusOK;
    [resp setBody:data];
    
    // Debug logging
    PDS_LOG_CORE_DEBUG(@"PLCServer serving %@ (Content-Type: %@)", path ?: @"", contentType ?: @"");
}

- (NSString *)assetsPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cwd = [fm currentDirectoryPath];
    
    NSArray *candidates = @[
        [cwd stringByAppendingPathComponent:@"ATProtoPDS/Sources/PLC/Assets"],
        [cwd stringByAppendingPathComponent:@"Sources/PLC/Assets"],
        [cwd stringByAppendingPathComponent:@"Assets"],
        [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Assets"]
    ];
    
    for (NSString *path in candidates) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            return path;
        }
    }
    
    return nil;
}

@end
