//
//  XrpcServerMethods.m
//  ATProtoPDS
//
//  Domain module for com.atproto.server.* XRPC endpoints.
//

#import "Network/XrpcServerMethods.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcMethodRegistry.h"
#import "App/PDSConfiguration.h"
#import "App/Services/PDSAccountService.h"
#import "App/Services/PDSRepositoryService.h"
#import "Admin/PDSAdminController.h"
#import "Admin/PDSAdminAuth.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"
#import "Core/ATProtoValidator.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/DID.h"
#import "Debug/PDSLogger.h"
#import "Core/NSDateFormatter+ATProto.h"
#import <CommonCrypto/CommonKeyDerivation.h>

static NSString *const kServiceAuthLxmCreateAccount = @"com.atproto.server.createAccount";

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

// Forward declarations for helper functions
static NSString *didWebIdentifierFromIssuer(NSString *issuer, NSString *fallbackHost);
static NSArray<NSString *> *serviceAuthExpectedAudiences(PDSConfiguration *config);
static BOOL validateDidWebServiceAuthForAccountCreation(HttpRequest *request,
                                                        HttpResponse *response,
                                                        NSString *did,
                                                        PDSConfiguration *config);
static BOOL createInviteCodeInDatabase(PDSServiceDatabases *serviceDatabases,
                                       NSString *accountDid,
                                       NSInteger maxUses,
                                       NSString **outCode,
                                       NSError **error);
static BOOL isLikelyEmail(NSString *email);
static BOOL updateAccountEmail(PDSServiceDatabases *serviceDatabases,
                               NSString *did,
                               NSString *email,
                               NSError **error);
static BOOL updateAccountHandle(PDSServiceDatabases *serviceDatabases,
                                NSString *did,
                                NSString *handle,
                                NSError **error);
static NSData *pbkdf2HashPassword(NSString *password, NSData *salt, NSError **error);
static NSDictionary *payloadDictionaryFromJWT(JWT *jwt, NSError **error);

@interface JWT (Base64URL)
+ (nullable NSData *)base64URLDecode:(NSString *)string error:(NSError **)error;
@end

#pragma mark - Helper Functions

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

static NSDictionary *payloadDictionaryFromJWT(JWT *jwt, NSError **error) {
    NSData *payloadData = [JWT base64URLDecode:jwt.rawPayload error:error];
    if (!payloadData) return nil;
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:error];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT"
                                         code:1 // JWTErrorDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWT payload JSON"}];
        }
        return nil;
    }
    return payload;
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
    NSDictionary *atprotoData = [[DIDResolver sharedResolver] resolveAtprotoDataForDID:did error:&resolveError];
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

#pragma mark - XrpcServerMethods Implementation

@implementation XrpcServerMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
                accountService:(id<PDSAccountService>)accountService
             repositoryService:(PDSRepositoryService *)repositoryService
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
              userDatabasePool:(PDSDatabasePool *)userDatabasePool
                 configuration:(PDSConfiguration *)config
    enforceDidWebServiceAuth:(BOOL)enforceDidWebServiceAuth {
    
    // Register com.atproto.server.describeServer
    [self registerDescribeServerWithDispatcher:dispatcher configuration:config];
    
    // Register account and session methods
    [self registerAccountAndSessionMethodsWithDispatcher:dispatcher
                                               jwtMinter:jwtMinter
                                         adminController:adminController
                                          accountService:accountService
                                       repositoryService:repositoryService
                                        serviceDatabases:serviceDatabases
                                        userDatabasePool:userDatabasePool
                                           configuration:config
                              enforceDidWebServiceAuth:enforceDidWebServiceAuth];
}

#pragma mark - Endpoint Registration Methods

+ (void)registerDescribeServerWithDispatcher:(XrpcDispatcher *)dispatcher
                               configuration:(PDSConfiguration *)config {
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
}

+ (void)registerAccountAndSessionMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                              jwtMinter:(JWTMinter *)jwtMinter
                                        adminController:(id<PDSAdminController>)adminController
                                         accountService:(id<PDSAccountService>)accountService
                                      repositoryService:(PDSRepositoryService *)repositoryService
                                       serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                       userDatabasePool:(PDSDatabasePool *)userDatabasePool
                                          configuration:(PDSConfiguration *)config
                             enforceDidWebServiceAuth:(BOOL)enforceDidWebServiceAuth {
    // This method will be implemented in multiple parts due to size constraints
    // Part 1: createAccount, createSession, getSession, refreshSession, deleteSession
    [self registerAccountCreationAndSessionEndpoints:dispatcher
                                           jwtMinter:jwtMinter
                                     adminController:adminController
                                      accountService:accountService
                                   repositoryService:repositoryService
                                    serviceDatabases:serviceDatabases
                                       configuration:config
                          enforceDidWebServiceAuth:enforceDidWebServiceAuth];
    
    // Part 2: Invite codes
    [self registerInviteCodeEndpoints:dispatcher
                            jwtMinter:jwtMinter
                      adminController:adminController
                     serviceDatabases:serviceDatabases];
    
    // Part 3: App passwords
    [self registerAppPasswordEndpoints:dispatcher
                             jwtMinter:jwtMinter
                       adminController:adminController
                      serviceDatabases:serviceDatabases];
    
    // Part 4: Email and account management
    [self registerEmailAndAccountEndpoints:dispatcher
                                 jwtMinter:jwtMinter
                           adminController:adminController
                            accountService:accountService
                          serviceDatabases:serviceDatabases
                          userDatabasePool:userDatabasePool];
    
    // Part 5: Account lifecycle (getAccount, deleteAccount, checkAccountStatus, activate, deactivate)
    [self registerAccountLifecycleEndpoints:dispatcher
                                  jwtMinter:jwtMinter
                            adminController:adminController
                             accountService:accountService];
}

#pragma mark - Helper Registration Methods

+ (void)registerAccountCreationAndSessionEndpoints:(XrpcDispatcher *)dispatcher
                                          jwtMinter:(JWTMinter *)jwtMinter
                                    adminController:(id<PDSAdminController>)adminController
                                     accountService:(id<PDSAccountService>)accountService
                                  repositoryService:(PDSRepositoryService *)repositoryService
                                   serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                      configuration:(PDSConfiguration *)config
                         enforceDidWebServiceAuth:(BOOL)enforceDidWebServiceAuth {
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

        if (did.length > 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Cannot specify DID during account creation. Import is not supported via this endpoint."}];
            return;
        }

        if (config.inviteCodeRequired) {
            NSString *inviteCode = body[@"inviteCode"];
            if (!inviteCode || inviteCode.length == 0) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidInviteCode", @"message": @"Invite code required"}];
                return;
            }
            
            NSError *inviteError = nil;
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
                                                                  did:nil
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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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
}

+ (void)registerInviteCodeEndpoints:(XrpcDispatcher *)dispatcher
                           jwtMinter:(JWTMinter *)jwtMinter
                     adminController:(id<PDSAdminController>)adminController
                    serviceDatabases:(PDSServiceDatabases *)serviceDatabases {
    [dispatcher registerComAtprotoServerCreateInviteCode:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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

    [dispatcher registerComAtprotoServerGetAccountInviteCodes:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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
                @"createdAt": [XrpcIdentityHelper currentISO8601String],
                @"uses": @[]
            }];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"codes": codes}];
    }];
}

+ (void)registerAppPasswordEndpoints:(XrpcDispatcher *)dispatcher
                            jwtMinter:(JWTMinter *)jwtMinter
                      adminController:(id<PDSAdminController>)adminController
                     serviceDatabases:(PDSServiceDatabases *)serviceDatabases {
    [dispatcher registerComAtprotoServerCreateAppPassword:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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
}

+ (void)registerEmailAndAccountEndpoints:(XrpcDispatcher *)dispatcher
                                jwtMinter:(JWTMinter *)jwtMinter
                          adminController:(id<PDSAdminController>)adminController
                           accountService:(id<PDSAccountService>)accountService
                         serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                         userDatabasePool:(PDSDatabasePool *)userDatabasePool {
    [dispatcher registerComAtprotoServerRequestEmailConfirmation:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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

    [dispatcher registerComAtprotoServerUpdateEmail:^(HttpRequest *request, HttpResponse *response) {
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

    [dispatcher registerComAtprotoServerRequestAccountDelete:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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

    [dispatcher registerComAtprotoServerReserveSigningKey:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
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
            signingKey = storedKey;
        } else {
            Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:&error];
            if (keyPair) {
                signingKey = keyPair.didKeyString;
            }
        }

        if (!signingKey) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"SigningKeyUnavailable", @"message": error.localizedDescription ?: @"Failed to reserve signing key"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"signingKey": signingKey}];
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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
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

+ (void)registerAccountLifecycleEndpoints:(XrpcDispatcher *)dispatcher
                                 jwtMinter:(JWTMinter *)jwtMinter
                           adminController:(id<PDSAdminController>)adminController
                            accountService:(id<PDSAccountService>)accountService {
    [dispatcher registerComAtprotoServerGetAccount:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

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
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];

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
}


@end
