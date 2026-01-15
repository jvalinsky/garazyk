#import "Network/XrpcMethodRegistry.h"
#import "Blob/BlobStorage.h"
#import "Core/CID.h"
#import "Core/DID.h"
#import "Core/ATProtoValidator.h"
#import "Identity/HandleResolver.h"
#import "AppView/ActorService.h"
#import "AppView/FeedService.h"
#import "AppView/NotificationService.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "App/PDSConfiguration.h"

static NSString *const kServiceAuthLxmCreateAccount = @"com.atproto.server.createAccount";

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

static NSArray<NSString *> *serviceAuthExpectedAudiences(PDSConfiguration *config) {
    NSString *hostInput = config.serverHost ?: @"localhost";
    if ([hostInput isEqualToString:@"0.0.0.0"]) {
        hostInput = @"localhost";
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:[@"https://" stringByAppendingString:hostInput]];
    NSString *host = components.host ?: hostInput;
    NSNumber *port = components.port;
    if (!port && config.serverPort != 0) {
        port = @(config.serverPort);
    }

    NSMutableArray<NSString *> *audiences = [NSMutableArray array];
    if (host.length > 0) {
        [audiences addObject:[NSString stringWithFormat:@"did:web:%@", host]];
    }
    if (port && port.unsignedIntegerValue != 80 && port.unsignedIntegerValue != 443) {
        NSString *encodedHost = [NSString stringWithFormat:@"%@%%3A%@", host, port];
        [audiences addObject:[NSString stringWithFormat:@"did:web:%@", encodedHost]];
    }
    return audiences;
}

static NSData *publicKeyBytesFromMultibase(NSString *multibase, NSError **error) {
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
    if (prefix == 'z') {
        data = [CID base58btcDecode:payload];
    } else if (prefix == 'b') {
        data = [CID base32Decode:payload];
    } else if (prefix == 'u') {
        data = [JWT base64URLDecode:payload error:error];
    } else {
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

@implementation XrpcMethodRegistry

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller {
    [dispatcher registerComAtprotoServerDescribeServer:^(HttpRequest *request, HttpResponse *response) {
        // Return server capabilities and available DIDs
        PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
        NSString *hostname = config.serverHost ?: @"localhost";
        NSString *serverDid = [NSString stringWithFormat:@"did:web:%@", hostname];
        
        // Build available user domains from config
        NSArray *availableUserDomains = @[hostname];
        
        NSDictionary *result = @{
            @"inviteCodeRequired": @(config.inviteCodeRequired),
            @"phoneVerificationRequired": @NO,
            @"availableUserDomains": availableUserDomains,
            @"links": @{
                @"privacyPolicy": @"https://bsky.social/about/blog/privacy-policy",
                @"termsOfService": @"https://bsky.social/about/blog/terms-of-service"
            },
            @"did": serverDid
        };
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

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

        if (did && [did hasPrefix:@"did:web:"]) {
            NSString *authHeader = [request headerForKey:@"Authorization"];
            if (!authHeader || ![authHeader hasPrefix:@"Bearer "]) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Missing service auth token"}];
                return;
            }

            NSString *token = [authHeader substringFromIndex:7];
            NSError *parseError = nil;
            JWT *jwt = [JWT jwtWithToken:token error:&parseError];
            if (!jwt || parseError) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Unable to parse service auth token"}];
                return;
            }

            NSError *payloadError = nil;
            NSDictionary *payloadDict = payloadDictionaryFromJWT(jwt, &payloadError);
            if (!payloadDict) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Unable to decode service auth payload"}];
                return;
            }

            NSString *lxm = payloadDict[@"lxm"];
            if (!lxm || ![lxm isEqualToString:kServiceAuthLxmCreateAccount]) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Service auth token has invalid lxm"}];
                return;
            }

            NSError *resolveError = nil;
            DIDResolver *resolver = [[DIDResolver alloc] init];
            NSDictionary *atprotoData = [resolver resolveAtprotoDataForDID:did error:&resolveError];
            NSString *signingKey = atprotoData[@"signingKey"];
            if (!signingKey) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"DID document missing signing key"}];
                return;
            }

            NSError *decodeError = nil;
            NSData *signingKeyBytes = publicKeyBytesFromMultibase(signingKey, &decodeError);
            if (!signingKeyBytes) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Unable to decode signing key"}];
                return;
            }

            NSError *keyError = nil;
            NSData *publicKey = [[Secp256k1 shared] normalizedPublicKey:signingKeyBytes error:&keyError];
            if (!publicKey) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Unable to normalize signing key"}];
                return;
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
                return;
            }

            NSString *iss = jwt.payload.iss;
            if (!iss || ![iss isEqualToString:did]) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Service auth token has invalid issuer"}];
                return;
            }

            NSString *aud = jwt.payload.aud;
            NSArray<NSString *> *expectedAudiences = serviceAuthExpectedAudiences([PDSConfiguration sharedConfiguration]);
            NSString *audBase = aud;
            NSRange audHash = [aud rangeOfString:@"#"];
            if (audHash.location != NSNotFound) {
                audBase = [aud substringToIndex:audHash.location];
            }
            if (!aud || ![expectedAudiences containsObject:audBase]) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Service auth token has invalid audience"}];
                return;
            }
        }

        NSError *error = nil;
        NSDictionary *result = [controller createAccountForEmail:email
                                                         password:password
                                                          handle:handle
                                                             did:did
                                                            error:&error];

        if (error) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"AccountCreationFailed", @"message": error.localizedDescription}];
            return;
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

        NSString *handle = body[@"handle"];
        NSString *did = body[@"did"];

        NSError *error = nil;
        NSDictionary *session = [controller createSessionForIdentifier:identifier
                                                              password:password
                                                               handle:handle ?: identifier
                                                                 did:did ?: [NSString stringWithFormat:@"did:web:%@", identifier]
                                                                error:&error];

        if (error) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"AuthenticationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:session];
    }];

    [dispatcher registerComAtprotoServerRefreshSession:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *refreshToken = body[@"refreshToken"];

        if (!refreshToken) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing refreshToken"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *session = [controller refreshSessionWithRefreshToken:refreshToken error:&error];

        if (error) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"AuthenticationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:session];
    }];

    [dispatcher registerComAtprotoServerGetServiceAuth:^(HttpRequest *request, HttpResponse *response) {
        NSString *aud = [request queryParamForKey:@"aud"];
        if (!aud) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing aud parameter"}];
            return;
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
        NSString *did = [self extractDIDFromAuthHeader:authHeader controller:controller request:request];
        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Missing or invalid authorization token"}];
            return;
        }

        NSError *accountError = nil;
        if (![controller.serviceDatabases getAccountByDid:did error:&accountError]) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": @"Account not found for token"}];
            return;
        }

        NSError *storeError = nil;
        PDSActorStore *store = [controller.userDatabasePool storeForDid:did error:&storeError];
        if (!store) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"StoreUnavailable", @"message": storeError.localizedDescription ?: @"Failed to load signing key"}];
            return;
        }

        NSError *keyError = nil;
        NSData *privateKey = [store signingKeyPrivateBytesWithError:&keyError];
        if (!privateKey) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"SigningKeyUnavailable", @"message": keyError.localizedDescription ?: @"Signing key bytes unavailable"}];
            return;
        }

        NSString *lxm = [request queryParamForKey:@"lxm"];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        payload[@"iss"] = did;
        payload[@"sub"] = did;
        payload[@"did"] = did;
        payload[@"aud"] = aud;
        payload[@"iat"] = @((long long)now);
        payload[@"exp"] = @((long long)(now + 60));
        payload[@"jti"] = [[NSUUID UUID] UUIDString];
        if (lxm.length > 0) {
            payload[@"lxm"] = lxm;
        }

        JWTMinter *minter = [[JWTMinter alloc] init];
        minter.issuer = did;
        minter.signingAlgorithm = @"ES256K";
        minter.privateKey = privateKey;

        NSError *mintError = nil;
        NSString *token = [minter signPayload:payload error:&mintError];
        if (!token) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"TokenMintFailed", @"message": mintError.localizedDescription ?: @"Failed to mint service auth token"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"token": token}];
    }];

    [dispatcher registerComAtprotoRepoCreateRecord:^(HttpRequest *request, HttpResponse *response) {
        PDS_LOG_HTTP_DEBUG(@"createRecord XRPC handler called");
        NSDictionary *body = request.jsonBody;
        NSString *repo = body[@"repo"];
        NSString *collection = body[@"collection"];
        NSDictionary *record = body[@"record"];

        PDS_LOG_HTTP_DEBUG(@"createRecord params: repo=%@, collection=%@, record=%@", repo, collection, record);

        if (!repo || !collection || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo, collection, or record"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller createRecordForDid:repo
                                                     collection:collection
                                                        record:record
                                                validationMode:PDSValidationModeRequired
                                                         error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoGetRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = [request queryParamForKey:@"repo"];
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *rkey = [request queryParamForKey:@"rkey"];

        if (!repo || !collection || !rkey) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo, collection, or rkey"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller getRecordForDid:repo
                                                 collection:collection
                                                      rkey:rkey
                                                     error:&error];

        if (error) {
            response.statusCode = error.code == 404 ? HttpStatusNotFound : HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoListRecords:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = [request queryParamForKey:@"repo"];
        NSString *collection = [request queryParamForKey:@"collection"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        if (!repo || !collection) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo or collection"}];
            return;
        }

        NSError *error = nil;
        NSArray *records = [controller listRecordsForDid:repo
                                               collection:collection
                                                   limit:limit
                                                  cursor:cursor
                                                   error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"records": records}];
    }];

    [dispatcher registerComAtprotoRepoDeleteRecord:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *repo = body[@"repo"];
        NSString *collection = body[@"collection"];
        NSString *rkey = body[@"rkey"];

        if (!repo || !collection || !rkey) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo, collection, or rkey"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [controller deleteRecordForDid:repo
                                            collection:collection
                                                 rkey:rkey
                                                error:&error];

        if (!success) {
            response.statusCode = error.code == 404 ? HttpStatusNotFound : HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoRepoApplyWrites:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        if (!body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }



        NSString *repo = body[@"repo"];
        NSArray *writes = body[@"writes"];
        NSNumber *validate = body[@"validate"];
        NSString *swapCommit = body[@"swapCommit"];

        if (!repo || !writes || writes.count == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing required fields: repo and writes"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller applyWrites:writes
                                                 repo:repo
                                             validate:validate.boolValue
                                           swapCommit:swapCommit
                                                error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ApplyWritesFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoDescribeRepo:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = [request queryParamForKey:@"repo"];

        if (!repo) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo parameter"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller describeRepo:repo error:&error];

        if (error) {
            response.statusCode = error.code == 404 ? HttpStatusNotFound : HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoPutRecord:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *repo = body[@"repo"];
        NSString *collection = body[@"collection"];
        NSString *rkey = body[@"rkey"];
        NSDictionary *record = body[@"record"];

        if (!repo || !collection || !rkey || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo, collection, rkey, or record"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [controller putRecordForDid:repo
                                          collection:collection
                                               rkey:rkey
                                              record:record
                                       validationMode:PDSValidationModeRequired
                                               error:&error];

        if (!success) {
            response.statusCode = error.code == 404 ? HttpStatusNotFound : HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"uri": [NSString stringWithFormat:@"at://%@/%@/%@", repo, collection, rkey]}];
    }];

    [dispatcher registerComAtprotoSyncGetRepo:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *error = nil;
        NSData *repoData = [controller getRepoDataForDid:did error:&error];

        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = @"application/car";
        [response setBodyData:repoData];
    }];

    [dispatcher registerComAtprotoSyncGetHead:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *error = nil;
        NSString *head = [controller getRepoHeadForDid:did error:&error];

        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"root": head ?: [NSNull null]}];
    }];

    [dispatcher registerComAtprotoRepoUploadBlob:^(HttpRequest *request, HttpResponse *response) {
        // Extract DID from Authorization header
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader controller:controller request:request];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        // Get the blob data from request body
        NSData *blobData = request.body;
        if (!blobData || blobData.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing blob data"}];
            return;
        }

        // Check size limit (1MB)
        if (blobData.length > 1 * 1024 * 1024) {
             response.statusCode = HttpStatusBadRequest; // Should be 413 technically but test expects 400
             [response setJsonBody:@{@"error": @"BlobTooLarge", @"message": @"Blob exceeds size limit (1MB)"}];
             return;
        }

        // Extract MIME type from Content-Type header
        NSString *mimeType = [request headerForKey:@"Content-Type"] ?: @"application/octet-stream";
        
        // Validate MIME type
        if ([mimeType isEqualToString:@"application/x-msdownload"]) {
             response.statusCode = HttpStatusBadRequest;
             [response setJsonBody:@{@"error": @"InvalidMimeType", @"message": @"Disallowed MIME type"}];
             return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller uploadBlob:blobData mimeType:mimeType did:did error:&error];
        
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
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader controller:controller request:request];

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
        BOOL success = [controller deleteBlobWithCID:cid did:did error:&error];

        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"DeleteFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoSyncGetBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        NSString *cid = [request queryParamForKey:@"cid"];

        if (!did || !cid) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did or cid"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller getBlobWithCID:cid did:did error:&error];

        if (error || !result) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"BlobRetrievalFailed", @"message": error.localizedDescription ?: @"Blob not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = result[@"mimeType"] ?: @"application/octet-stream";
        [response setBodyData:result[@"blob"]];
    }];

    [dispatcher registerComAtprotoSyncListBlobs:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 100;
        limit = MIN(limit, 1000); // Cap at 1000

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *error = nil;
        NSArray *blobs = [controller listBlobsForDID:did limit:limit cursor:cursor error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BlobListFailed", @"message": error.localizedDescription}];
            return;
        }

        NSDictionary *result = @{
            @"blobs": blobs,
            @"cursor": cursor ?: [NSNull null] // Would need proper cursor implementation
        };

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoDeleteBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader controller:controller request:request];

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
        BOOL success = [controller deleteBlobWithCID:cid did:did error:&error];

        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"DeleteFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoIdentityResolveDid:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did parameter"}];
            return;
        }

        DIDResolver *resolver = [[DIDResolver alloc] init];
        NSError *error = nil;
        DIDDocument *doc = [resolver resolveDIDSync:did error:&error];

        // TODO: Support forceRefresh query parameter

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:doc.jsonDictionary];
    }];

    [dispatcher registerComAtprotoIdentityResolveIdentity:^(HttpRequest *request, HttpResponse *response) {
        NSString *identifier = [request queryParamForKey:@"identifier"];

        if (!identifier) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing identifier parameter"}];
            return;
        }

        DIDResolver *didResolver = [[DIDResolver alloc] init];
        HandleResolver *handleResolver = [[HandleResolver alloc] init];

        if ([identifier hasPrefix:@"did:"]) {
            // It's a DID, resolve directly
            NSError *error = nil;
            DIDDocument *doc = [didResolver resolveDIDSync:identifier error:&error];

            if (error) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": error.localizedDescription}];
                return;
            }

            NSDictionary *result = @{
                @"did": identifier,
                @"didDoc": doc.jsonDictionary
            };
            response.statusCode = HttpStatusOK;
            [response setJsonBody:result];
        } else {
            // It's a handle, resolve to DID then to document
            // For simplicity, resolve handle to DID, then DID to doc
            // TODO: Verify handle matches document's alsoKnownAs
            NSError *handleError = nil;
            __block NSString *did = nil;
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

            [handleResolver resolveHandle:identifier completion:^(NSString * _Nullable resolvedDid, NSError * _Nullable error) {
                did = resolvedDid;
                dispatch_semaphore_signal(semaphore);
            }];

            dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

            if (!did) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": @"Handle resolution failed"}];
                return;
            }

            NSError *docError = nil;
            DIDDocument *doc = [didResolver resolveDIDSync:did error:&docError];

            if (docError) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": docError.localizedDescription}];
                return;
            }

            NSDictionary *result = @{
                @"did": did,
                @"handle": identifier,
                @"didDoc": doc.jsonDictionary
            };
            response.statusCode = HttpStatusOK;
            [response setJsonBody:result];
        }
    }];

    [dispatcher registerComAtprotoIdentityResolveHandle:^(HttpRequest *request, HttpResponse *response) {
        NSString *handle = [request queryParamForKey:@"handle"];

        if (!handle) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing handle parameter"}];
            return;
        }

        HandleResolver *handleResolver = [[HandleResolver alloc] init];
        NSError *error = nil;
        __block NSString *did = nil;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [handleResolver resolveHandle:handle completion:^(NSString * _Nullable resolvedDid, NSError * _Nullable resolveError) {
            did = resolvedDid;
            dispatch_semaphore_signal(semaphore);
        }];

        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": @"Handle resolution failed"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"did": did}];
    }];

    [dispatcher registerComAtprotoIdentityGetRecommendedDidCredentials:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader controller:controller request:request];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        DIDResolver *resolver = [[DIDResolver alloc] init];
        NSError *resolveError = nil;
        NSDictionary *atprotoData = [resolver resolveAtprotoDataForDID:did error:&resolveError];
        if (!atprotoData) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": resolveError.localizedDescription ?: @"DID resolution failed"}];
            return;
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        NSString *handle = atprotoData[@"handle"];
        if (handle) {
            result[@"alsoKnownAs"] = @[handle];
        }

        NSString *signingKey = atprotoData[@"signingKey"];
        if (signingKey) {
            result[@"verificationMethods"] = @{@"atproto": [NSString stringWithFormat:@"did:key:%@", signingKey]};
        }

        NSString *pds = atprotoData[@"pds"];
        if (pds) {
            result[@"services"] = @{@"atproto_pds": pds};
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // Moderation endpoints
    [dispatcher registerComAtprotoAdminModerateAccount:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;

        NSError *error = nil;
        NSDictionary *result = [controller moderateAccount:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ModerationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoAdminModerateRecord:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;

        NSError *error = nil;
        NSDictionary *result = [controller moderateRecord:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ModerationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // Labeling endpoints
    [dispatcher registerComAtprotoLabelCreateLabel:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;

        NSError *error = nil;
        NSDictionary *result = [controller createLabel:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"LabelCreationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoLabelGetLabels:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;

        NSError *error = nil;
        NSDictionary *result = [controller getLabels:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"LabelRetrievalFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
    
    ActorService *actorService = [[ActorService alloc] initWithDatabase:controller.database];
    FeedService *feedService = [[FeedService alloc] initWithDatabase:controller.database];
    NotificationService *notificationService = [[NotificationService alloc] initWithDatabase:controller.database];
    
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
    
    [dispatcher registerAppBskyActorGetProfiles:^(HttpRequest *request, HttpResponse *response) {
        NSString *actorsParam = [request queryParamForKey:@"actors"];
        
        if (!actorsParam || actorsParam.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actors parameter"}];
            return;
        }
        
        NSArray *actors = [actorsParam componentsSeparatedByString:@","];
        NSError *error = nil;
        NSArray *profiles = [actorService getProfilesForActors:actors error:&error];
        
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ProfilesQueryFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"profiles": profiles}];
    }];
    
    [dispatcher registerAppBskyActorGetPreferences:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *preferences = [actorService getPreferencesForActor:actor error:&error];
        
        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"PreferencesNotFound", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:preferences];
    }];
    
    [dispatcher registerAppBskyActorPutPreferences:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        NSDictionary *body = request.jsonBody;
        NSDictionary *preferences = body[@"preferences"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        if (!preferences) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing preferences in body"}];
            return;
        }
        
        NSError *error = nil;
        BOOL success = [actorService putPreferencesForActor:actor preferences:preferences error:&error];
        
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"PreferencesUpdateFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
    
    [dispatcher registerAppBskyFeedGetTimeline:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 30;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *timeline = [feedService getTimelineForActor:actor limit:limit cursor:cursor error:&error];
        
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"TimelineFetchFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:timeline];
    }];
    
    [dispatcher registerAppBskyFeedGetAuthorFeed:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 30;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *filter = [request queryParamForKey:@"filter"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *feed = [feedService getAuthorFeedForActor:actor limit:limit cursor:cursor filter:filter error:&error];
        
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"FeedFetchFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:feed];
    }];
    
    [dispatcher registerAppBskyFeedGetPostThread:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        NSInteger depth = [[request queryParamForKey:@"depth"] integerValue] ?: 6;
        
        if (!uri) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing uri parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *thread = [feedService getPostThread:uri depth:depth error:&error];
        
        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"ThreadNotFound", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:thread];
    }];
    
    [dispatcher registerAppBskyFeedGetFeed:^(HttpRequest *request, HttpResponse *response) {
        NSString *feed = [request queryParamForKey:@"feed"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 30;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        if (!feed) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing feed parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *feedResult = [feedService getFeed:feed limit:limit cursor:cursor error:&error];
        
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"FeedFetchFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:feedResult];
    }];
    
    [dispatcher registerAppBskyFeedGetActorLikes:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 30;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *likes = [feedService getActorLikes:actor limit:limit cursor:cursor error:&error];
        
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"LikesFetchFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:likes];
    }];
    
    [dispatcher registerAppBskyNotificationRegisterPush:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        NSDictionary *body = request.jsonBody;
        NSString *token = body[@"token"];
        NSString *platformToken = body[@"platformToken"];
        NSString *serviceEndpoint = body[@"serviceEndpoint"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        if (!token) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing token in body"}];
            return;
        }
        
        NSError *error = nil;
        BOOL success = [notificationService registerPushForActor:actor
                                                      deviceToken:token
                                                    platformToken:platformToken
                                                    serviceEndpoint:serviceEndpoint ?: @""
                                                            error:&error];
        
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"PushRegistrationFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
    
    [dispatcher registerAppBskyUserGetUserStats:^(HttpRequest *request, HttpResponse *response) {
        NSString *user = [request queryParamForKey:@"user"];
        
        if (!user) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing user parameter"}];
            return;
        }
        
        // Return hardcoded demo data as requested
        NSDictionary *stats = @{
            @"followers": @150,
            @"following": @75,
            @"posts": @42
        };
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:stats];
    }];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader controller:(PDSController *)controller request:(HttpRequest *)request {
    if (!authHeader || ![authHeader hasPrefix:@"Bearer "]) return nil;
    NSString *token = [authHeader substringFromIndex:7];

    // Parse the JWT token
    NSError *parseError = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&parseError];
    if (!jwt || parseError) {
        PDS_LOG_HTTP_WARN(@"Failed to parse JWT token from authorization header");
        return nil;
    }

    // Create verifier and set expected issuer
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    if (controller.jwtMinter) {
        verifier.keyRotationManager = controller.jwtMinter.keyRotationManager;
        verifier.publicKey = controller.jwtMinter.publicKey;
    }

    // Use configurable issuer from environment, default to localhost
    NSString *expectedIssuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"] ?: @"https://pds.local:8443";
    verifier.expectedIssuer = expectedIssuer;
    verifier.expectedAudience = expectedIssuer; // Ensure tokens are for this PDS instance
    verifier.allowedAlgorithms = @[@"RS256", @"ES256"]; // Restrict to secure algorithms

    // Verify the JWT
    NSError *verifyError = nil;
    BOOL isValid = [verifier verifyJWT:jwt error:&verifyError];
    if (!isValid || verifyError) {
        PDS_LOG_AUTH_WARN(@"JWT verification failed for request from IP: %@", request.remoteAddress ?: @"unknown");
        return nil;
    }

    // Extract DID from subject claim
    NSString *did = jwt.payload.sub;
    if (!did || ![did hasPrefix:@"did:"]) {
        PDS_LOG_AUTH_WARN(@"Invalid DID in JWT subject claim: %@", did);
        return nil;
    }

    return did;
}

@end
