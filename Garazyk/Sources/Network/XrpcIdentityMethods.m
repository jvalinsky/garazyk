//
//  XrpcIdentityMethods.m
//  ATProtoPDS
//
//  Domain module for com.atproto.identity.* XRPC endpoints.
//

#import "Network/XrpcIdentityMethods.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Email/PDSEmailProvider.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "App/PDSConfiguration.h"
#import "Identity/HandleResolver.h"
#import "Identity/ATProtoHandleValidator.h"
#import "PLC/PLCRotationKeyManager.h"
#import "PLC/PLCOperation.h"
#import "PLC/DIDPLCResolver.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Auth/CryptoUtils.h"
#import "Auth/Secp256k1.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Sync/SubscribeReposHandler.h"
#import "Network/RateLimiter.h"

// Forward declarations for XrpcMethodRegistry PLC token methods
@interface XrpcMethodRegistry (PLCTokens)
+ (void)storePlcOperationToken:(NSString *)token forDid:(NSString *)did;
+ (BOOL)validatePlcOperationToken:(NSString *)token forDid:(NSString *)did;
@end

@implementation XrpcIdentityMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
              userDatabasePool:(PDSDatabasePool *)userDatabasePool
                 configuration:(PDSConfiguration *)configuration
                 emailProvider:(nullable id<PDSEmailProvider>)emailProvider
         subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler {
    
    // com.atproto.identity.refreshIdentity
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
        NSDictionary *result = [XrpcIdentityHelper resolveIdentityInfoForIdentifier:identifier
                                                                   serviceDatabases:serviceDatabases
                                                                          errorName:&errorName
                                                                              error:&error];
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

    // com.atproto.identity.resolveHandle
    [dispatcher registerComAtprotoIdentityResolveHandle:^(HttpRequest *request, HttpResponse *response) {
        NSString *handle = [request queryParamForKey:@"handle"];
        if (handle.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing handle parameter"}];
            return;
        }

        NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];
        PDSDatabaseAccount *account = [serviceDatabases getAccountByHandle:normalizedHandle error:nil];
        if (account) {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"did": account.did}];
            return;
        }

        HandleResolver *handleResolver = [[HandleResolver alloc] init];
        __block NSString *resolvedDid = nil;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [handleResolver resolveHandle:normalizedHandle completion:^(NSString * _Nullable did, NSError * _Nullable error) {
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

    // com.atproto.identity.resolveIdentity
    [dispatcher registerComAtprotoIdentityResolveIdentity:^(HttpRequest *request, HttpResponse *response) {
        NSString *identifier = [request queryParamForKey:@"identifier"];
        if (identifier.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing identifier parameter"}];
            return;
        }

        NSError *error = nil;
        NSString *errorName = nil;
        NSDictionary *result = [XrpcIdentityHelper resolveIdentityInfoForIdentifier:identifier
                                                                   serviceDatabases:serviceDatabases
                                                                          errorName:&errorName
                                                                              error:&error];
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

    // com.atproto.identity.resolveDid
    [dispatcher registerComAtprotoIdentityResolveDid:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        if (did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did parameter"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *doc = [XrpcIdentityHelper resolveDid:did
                                          serviceDatabases:serviceDatabases
                                             configuration:configuration
                                                     error:&error];
        if (!doc) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{
                @"error": @"NotFound",
                @"message": error.localizedDescription ?: @"DID not found"
            }];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:doc];
    }];

    // com.atproto.identity.getRecommendedDidCredentials
    [dispatcher registerComAtprotoIdentityGetRecommendedDidCredentials:^(HttpRequest *request, HttpResponse *response) {
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

    // com.atproto.identity.requestPlcOperationSignature
    [dispatcher registerComAtprotoIdentityRequestPlcOperationSignature:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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

    // com.atproto.identity.signPlcOperation
    [dispatcher registerComAtprotoIdentitySignPlcOperation:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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

        // Load per-DID rotation key if it exists
        NSData *perDidRotationKey = nil;
        if (store) {
            perDidRotationKey = [store rotationKeyDecryptedWithError:nil];
        }

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
            services = [XrpcIdentityHelper defaultPdsServiceForConfig:configuration];
        }
        if (!services) {
            services = @{};
        }

        id prev = [NSNull null];
        NSString *plcUrl = configuration.plcURL;
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
        
        if (perDidRotationKey) {
            PDS_LOG_INFO(@"Signing PLC operation with per-DID rotation key for %@", did);
            sig = [[Secp256k1 shared] signHash:hash withPrivateKey:perDidRotationKey error:&signError];
        } else {
            PDS_LOG_INFO(@"Signing PLC operation with server rotation key for %@", did);
            [keyManager signHash:hash result:&sig error:&signError];
        }

        if (!sig) {
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

    // com.atproto.identity.submitPlcOperation
    [dispatcher registerComAtprotoIdentitySubmitPlcOperation:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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
                NSString *expectedEndpoint = configuration.canonicalIssuer;
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

        NSString *plcUrl = configuration.plcURL;
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

        if (configuration.debugSkipPlcOperations || [configuration.plcURL isEqualToString:@"mock"]) {
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

    // com.atproto.identity.updateHandle
    [dispatcher registerComAtprotoIdentityUpdateHandle:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        // Rate Limiting: 10 per 5 min, 50 per day per DID
        RateLimiter *limiter = [RateLimiter sharedLimiter];
        NSString *shortKey = [NSString stringWithFormat:@"identity.updateHandle:5m:%@", did];
        RateLimitResult *shortResult = [limiter checkRateLimitForKey:shortKey limit:10 windowSeconds:300];
        if (!shortResult.allowed) {
            response.statusCode = HttpStatusTooManyRequests;
            [response setJsonBody:@{@"error": @"RateLimitExceeded", @"message": @"Rate limit exceeded (10 per 5 min)"}];
            [limiter applyRateLimitHeadersToResponse:response forDid:nil ip:nil]; // Generic headers or custom
            [response setHeader:[NSString stringWithFormat:@"%.0f", shortResult.retryAfter] forKey:@"Retry-After"];
            return;
        }

        NSString *longKey = [NSString stringWithFormat:@"identity.updateHandle:1d:%@", did];
        RateLimitResult *longResult = [limiter checkRateLimitForKey:longKey limit:50 windowSeconds:86400];
        if (!longResult.allowed) {
            response.statusCode = HttpStatusTooManyRequests;
            [response setJsonBody:@{@"error": @"RateLimitExceeded", @"message": @"Rate limit exceeded (50 per day)"}];
            [response setHeader:[NSString stringWithFormat:@"%.0f", longResult.retryAfter] forKey:@"Retry-After"];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *handle = body[@"handle"];
        PDS_LOG_DEBUG(@"updateHandle: handle=%@", handle);
        if (handle.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing handle"}];
            return;
        }

        NSError *validateError = nil;
        if (![ATProtoHandleValidator validateHandle:handle error:&validateError]) {
            PDS_LOG_DEBUG(@"updateHandle: Validation failed: %@", validateError);
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidHandle", @"message": validateError.localizedDescription ?: @"Invalid handle"}];
            return;
        }
        NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];
        PDS_LOG_DEBUG(@"updateHandle: normalizedHandle=%@", normalizedHandle);

        // 1. Uniqueness Check
        PDS_LOG_DEBUG(@"updateHandle: Checking uniqueness");
        NSError *error = nil;
        PDSDatabaseAccount *existingAccount = [serviceDatabases getAccountByHandle:normalizedHandle error:&error];
        PDS_LOG_DEBUG(@"updateHandle: Uniqueness check done, existingAccount=%@", existingAccount);

        BOOL needsUpdate = YES;
        if (existingAccount && [existingAccount.did isEqualToString:did]) {
            // Already owns this handle in local DB - verify PLC also matches before skipping
            PDS_LOG_DEBUG(@"updateHandle: Local DB has handle %@ for did=%@", normalizedHandle, did);
            // Continue to PLC check below to ensure PLC is in sync
        } else if (existingAccount) {
            response.statusCode = HttpStatusConflict;
            [response setJsonBody:@{@"error": @"HandleAlreadyTaken", @"message": @"Handle already taken"}];
            return;
        }

        // Only skip if PLC is also in sync (checked below with needsUpdate flag)

        if (needsUpdate) {
            // 2. Handle Ownership Verification
            PDS_LOG_DEBUG(@"updateHandle: Verifying handle ownership for %@", normalizedHandle);
            
            BOOL isLocal = NO;
            NSString *hostname = [configuration canonicalHostname];
            if ([normalizedHandle hasSuffix:[NSString stringWithFormat:@".%@", hostname]] || [normalizedHandle isEqualToString:hostname]) {
                isLocal = YES;
            } else {
                for (NSString *domain in configuration.availableUserDomains) {
                    if ([normalizedHandle hasSuffix:[NSString stringWithFormat:@".%@", domain]] || [normalizedHandle isEqualToString:domain]) {
                        isLocal = YES;
                        break;
                    }
                }
            }

            if (!isLocal) {
                HandleResolver *handleResolver = [[HandleResolver alloc] init];
                __block NSString *resolvedDid = nil;
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [handleResolver resolveHandle:normalizedHandle completion:^(NSString * _Nullable rDid, NSError * _Nullable rError) {
                    resolvedDid = rDid;
                    dispatch_semaphore_signal(semaphore);
                }];
                dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

                if (![resolvedDid isEqualToString:did]) {
                    PDS_LOG_ERROR(@"Handle verification failed for %@: expected %@, got %@", normalizedHandle, did, resolvedDid);
                    response.statusCode = HttpStatusBadRequest;
                    [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Handle resolution does not match DID"}];
                    return;
                }
            }

            // 3. Identity Update / Validation
            PDS_LOG_DEBUG(@"updateHandle: Starting PLC/DID update for did=%@", did);
            if (configuration.debugSkipPlcOperations || [configuration.plcURL isEqualToString:@"mock"]) {
                PDS_LOG_DB_DEBUG(@"Skipping PLC handle update (mock mode) for DID %@", did);
            } else if ([did hasPrefix:@"did:plc:"]) {
                NSString *plcUrl = configuration.plcURL;
                if ([plcUrl isEqualToString:@"mock"] || plcUrl.length == 0) {
                    plcUrl = @"http://127.0.0.1:2582";
                }
                
                DIDPLCResolver *plcResolver = [[DIDPLCResolver alloc] initWithPlcUrl:plcUrl];
                PDS_LOG_DEBUG(@"updateHandle: Resolving PLC audit log for DID=%@", did);
                NSError *auditError = nil;
                NSArray *auditLog = [plcResolver resolveAuditLogForDID:did error:&auditError];
                PDS_LOG_DEBUG(@"updateHandle: PLC audit log resolved, count=%lu, error=%@", (unsigned long)auditLog.count, auditError);
                
                if (!auditLog || auditLog.count == 0) {
                    PDS_LOG_ERROR(@"PLC audit log empty or not found for DID %@: %@", did, auditError);
                    response.statusCode = HttpStatusBadRequest;
                    [response setJsonBody:@{@"error": @"NotFound", @"message": @"DID not found in PLC directory"}];
                    return;
                }

                PLCRotationKeyManager *keyManager = [PLCRotationKeyManager sharedManager];
                NSError *keyError = nil;
                if (![keyManager loadOrGenerateKeyWithError:&keyError]) {
                    PDS_LOG_ERROR(@"Failed to load rotation key for DID %@: %@", did, keyError);
                    response.statusCode = HttpStatusInternalServerError;
                    [response setJsonBody:@{@"error": @"InternalError", @"message": @"Failed to load rotation key"}];
                    return;
                }

                // Load per-DID rotation key if it exists
                NSError *storeError = nil;
                PDSActorStore *store = [userDatabasePool storeForDid:did error:&storeError];
                NSData *perDidRotationKey = nil;
                if (store) {
                    perDidRotationKey = [store rotationKeyDecryptedWithError:nil];
                }

                NSMutableArray<PLCOperation *> *ops = [NSMutableArray array];
                for (NSDictionary *dict in auditLog) {
                    NSError *parseError = nil;
                    PLCOperation *operation = [PLCOperation operationFromDictionary:dict error:&parseError];
                    if (operation) {
                        [ops addObject:operation];
                    } else {
                        PDS_LOG_ERROR(@"updateHandle: Failed to parse PLC operation from audit log: %@, error: %@", dict, parseError);
                    }
                }
                
                PLCDIDState *currentState = nil;
                @try {
                    PDS_LOG_DEBUG(@"updateHandle: Replaying PLC history");
                    currentState = [PLCStateReplayer replayHistory:ops error:&auditError];
                } @catch (NSException *exception) {
                    PDS_LOG_ERROR(@"updateHandle: Exception replaying PLC history: %@", exception);
                    response.statusCode = HttpStatusInternalServerError;
                    [response setJsonBody:@{@"error": @"InternalError", @"message": [NSString stringWithFormat:@"Exception replaying DID history: %@", exception.reason]}];
                    return;
                }

                if (!currentState) {
                    PDS_LOG_ERROR(@"Failed to replay PLC state for DID %@: %@", did, auditError);
                    response.statusCode = HttpStatusInternalServerError;
                    [response setJsonBody:@{@"error": @"InternalError", @"message": @"Failed to replay DID history"}];
                    return;
                }

                // Check if PLC already has this handle - if so, only DB update needed
                PDS_LOG_INFO(@"updateHandle: Checking PLC state, alsoKnownAs=%@, target=%@", currentState.alsoKnownAs, normalizedHandle);
                NSString *plcHandle = nil;
                for (NSString *aka in currentState.alsoKnownAs) {
                    if ([aka hasPrefix:@"at://"]) {
                        NSString *handle = [aka substringFromIndex:5]; // remove "at://"
                        PDS_LOG_DEBUG(@"updateHandle: Found handle in PLC: %@", handle);
                        if ([handle isEqualToString:normalizedHandle]) {
                            plcHandle = handle;
                            break;
                        }
                    }
                }
                
                PDS_LOG_INFO(@"updateHandle: After PLC check, plcHandle=%@", plcHandle);
                if (plcHandle) {
                    PDS_LOG_INFO(@"updateHandle: PLC already has handle %@, need DB update", normalizedHandle);
                } else {
                    PDS_LOG_INFO(@"updateHandle: Creating PLC operation for handle %@", normalizedHandle);
                    // Create update operation
                    NSMutableDictionary *op = [NSMutableDictionary dictionary];
                    op[@"type"] = @"plc_operation";
                    op[@"rotationKeys"] = currentState.rotationKeys;
                    op[@"verificationMethods"] = currentState.verificationMethods;
                    
                    // Preserve alsoKnownAs entries that are not at:// handles
                    NSMutableArray *newAlsoKnownAs = [NSMutableArray array];
                    NSString *newAtHandle = [NSString stringWithFormat:@"at://%@", normalizedHandle];
                    for (NSString *aka in currentState.alsoKnownAs) {
                        if (![aka hasPrefix:@"at://"]) {
                            [newAlsoKnownAs addObject:aka];
                        }
                    }
                    [newAlsoKnownAs insertObject:newAtHandle atIndex:0];
                    op[@"alsoKnownAs"] = newAlsoKnownAs;

                    op[@"services"] = currentState.services;
                    NSDictionary *lastEntry = auditLog.lastObject;
                    NSDictionary *lastOp = lastEntry[@"operation"] ?: lastEntry;
                    NSString *prevCid = lastEntry[@"cid"];
                    if (!prevCid) {
                        prevCid = [PLCOperation calculateCIDForOperation:lastOp error:nil];
                    }
                    op[@"prev"] = prevCid;
                    
                    // Sign operation
                    NSError *signError = nil;
                    NSData *opData = [ATProtoCBORSerialization encodeDataWithJSONObject:op error:&signError];
                    NSData *hash = [CryptoUtils sha256:opData];
                    NSData *sigData = nil;
                    
                    if (perDidRotationKey) {
                        PDS_LOG_INFO(@"Signing handle update with per-DID rotation key for %@", did);
                        sigData = [[Secp256k1 shared] signHash:hash withPrivateKey:perDidRotationKey error:&signError];
                    } else {
                        PDS_LOG_INFO(@"Signing handle update with server rotation key for %@", did);
                        [keyManager signHash:hash result:&sigData error:&signError];
                    }

                    if (!sigData) {
                        PDS_LOG_ERROR(@"Failed to sign PLC operation for DID %@: %@", did, signError);
                        response.statusCode = HttpStatusInternalServerError;
                        [response setJsonBody:@{@"error": @"InternalError", @"message": @"Failed to sign operation"}];
                        return;
                    }
                    op[@"sig"] = [CryptoUtils base64URLEncode:sigData];

                    // Submit to PLC
                    PDS_LOG_DEBUG(@"updateHandle: Submitting PLC operation for DID=%@", did);
                    NSInteger statusCode = 0;
                    NSData *responseData = [plcResolver submitOperation:op did:did statusCode:&statusCode error:&auditError];
                    if (statusCode < 200 || statusCode >= 300) {
                        NSString *respString = responseData ? [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] : @"";
                        PDS_LOG_ERROR(@"PLC handle update failed: %ld %@", (long)statusCode, respString);
                        response.statusCode = HttpStatusServiceUnavailable;
                        [response setJsonBody:@{@"error": @"UpstreamError", @"message": @"Failed to submit operation to PLC directory"}];
                        return;
                    }
                }  // end else (plcHandle)
            } else {
                // Non-PLC DID (e.g. did:web). Verification already performed above in Step 2.
                PDS_LOG_DEBUG(@"updateHandle: Non-PLC DID %@ verification successful", did);
            }

            // 4. Database Update
            PDS_LOG_INFO(@"updateHandle: Doing DB update for did=%@, handle=%@", did, normalizedHandle);
            if (![XrpcIdentityHelper updateAccountHandle:serviceDatabases
                                                    did:did
                                                handle:normalizedHandle
                                                    error:&error]) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"HandleUpdateFailed", @"message": error.localizedDescription ?: @"Failed to update handle"}];
                return;
            }
        }

        // 5. Firehose / Sequencer Broadcast (Always run, even if handle was already owned)
        PDS_LOG_INFO(@"updateHandle: Broadcasting identity change for did=%@, handler exists=%d", did, subscribeReposHandler != nil);
        if (subscribeReposHandler) {
            [subscribeReposHandler broadcastIdentityChange:did handle:normalizedHandle];
        }

        // 6. Resolve DID for response
        error = nil;
        NSDictionary *doc = [XrpcIdentityHelper resolveDid:did
                                          serviceDatabases:serviceDatabases
                                             configuration:configuration
                                                     error:&error];
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
}

@end
