// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcServerPack.m
//  ATProtoPDS
//
//  Domain module for com.atproto.server.* XRPC endpoints.
//

#import "Network/XrpcServerPack.h"

#import "Network/XrpcServerPack_Internal.h"
#import "Network/XrpcServerPack+Describe.h"
#import "Network/XrpcServerPack+Session.h"
#import "Network/XrpcServerPack+InviteCodes.h"
#import "Network/XrpcServerPack+AppPasswords.h"
#import "Network/XrpcServerPack+AccountManagement.h"
#import "Network/XrpcServerPack+AccountLifecycle.h"
#import "Network/XrpcServerPack+Health.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcServiceAuthHelper.h"
#import "Network/XrpcRoutePackServices.h"
#import "Registration/PDSRegistrationGate.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Admin/PDSAdminController.h"
#import "Admin/PDSAdminAuth.h"
#import "Auth/JWT.h"
#import "Auth/PDSSecondFactorService.h"
#import "Auth/Secp256k1.h"
#import "Core/ATProtoValidator.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Database/Monitoring/PDSHealthCheck.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/DID.h"
#import "Core/PDSAccountEvents.h"
#import "Debug/GZLogger.h"
#import "Core/NSDateFormatter+ATProto.h"
#import <CommonCrypto/CommonKeyDerivation.h>
#import "Network/Generated/GZXrpcNSID.h"

static NSString *const kServiceAuthLxmCreateAccount = @"com.atproto.server.createAccount";

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

// Forward declarations for helper functions
BOOL validateDidWebServiceAuthForAccountCreation(HttpRequest *request,
                                                        HttpResponse *response,
                                                        NSString *did,
                                                        ATProtoServiceConfiguration *config);
BOOL createInviteCodeInDatabase(PDSServiceDatabases *serviceDatabases,
                                       NSString *accountDid,
                                       NSInteger maxUses,
                                       NSString **outCode,
                                       NSError **error);
BOOL isLikelyEmail(NSString *email);
BOOL updateAccountEmail(PDSServiceDatabases *serviceDatabases,
                               NSString *did,
                               NSString *email,
                               NSError **error);
BOOL updateAccountHandle(PDSServiceDatabases *serviceDatabases,
                                NSString *did,
                                NSString *handle,
                                NSError **error);
NSData *pbkdf2HashPassword(NSString *password, NSData *salt, NSError **error);
NSDictionary *payloadDictionaryFromJWT(JWT *jwt, NSError **error);



#pragma mark - Helper Functions

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

BOOL createInviteCodeInDatabase(PDSServiceDatabases *serviceDatabases,
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

BOOL isLikelyEmail(NSString *email) {
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

NSData *pbkdf2HashPassword(NSString *password, NSData *salt, NSError **error) {
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

BOOL updateAccountEmail(PDSServiceDatabases *serviceDatabases,
                               NSString *did,
                               NSString *email,
                               NSError **error) {
    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        return NO;
    }
    NSString *oldEmail = account.email;
    account.email = email;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL success = [serviceDatabases updateAccount:account error:error];
    if (success) {
        NSDictionary *details = @{
            @"old_email": oldEmail ?: @"",
            @"new_email": email ?: @""
        };
        [serviceDatabases logHostingEvent:did type:@"email_updated" details:details createdBy:did error:nil];
    }
    return success;
}

BOOL updateAccountHandle(PDSServiceDatabases *serviceDatabases,
                                NSString *did,
                                NSString *handle,
                                NSError **error) {
    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        return NO;
    }
    NSString *oldHandle = account.handle;
    account.handle = handle;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL success = [serviceDatabases updateAccount:account error:error];
    if (success) {
        NSDictionary *details = @{
            @"old_handle": oldHandle ?: @"",
            @"new_handle": handle ?: @""
        };
        [serviceDatabases logHostingEvent:did type:@"handle_updated" details:details createdBy:did error:nil];
    }
    return success;
}

NSDictionary *payloadDictionaryFromJWT(JWT *jwt, NSError **error) {
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

BOOL validateDidWebServiceAuthForAccountCreation(HttpRequest *request,
                                                        HttpResponse *response,
                                                        NSString *did,
                                                        ATProtoServiceConfiguration *config) {
    ATProtoServiceConfiguration *effectiveConfig = config ?: [ATProtoServiceConfiguration sharedConfiguration];

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
    NSData *signingKeyBytes = [XrpcIdentityHelper publicKeyBytesFromMultibase:signingKey error:&decodeError];
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
    NSArray<NSString *> *expectedAudiences = XrpcServiceAuthExpectedAudiences(effectiveConfig);
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

#pragma mark - XrpcServerPack Implementation

@implementation XrpcServerPack

+ (NSString *)routePackIdentifier {
  return @"com.atproto.server";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
    
    ATProtoServiceConfiguration *config = services.configuration;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    
    // Create registration gate from configuration
    NSError *gateError = nil;
    id<PDSRegistrationGate> registrationGate =
        [PDSRegistrationGateFactory gateFromConfiguration:config
                                         serviceDatabases:serviceDatabases
                                                    error:&gateError];
    if (gateError) {
      GZ_LOG_ERROR(@"Failed to create registration gate: %@", gateError);
    }

    // Register com.atproto.server.describeServer
    [self registerDescribeServerWithDispatcher:dispatcher
                                   configuration:config
                                registrationGate:registrationGate];

    // Register _health endpoint for diagnostics
    [self registerHealthEndpointWithDispatcher:dispatcher];

    // Register account and session methods
    [self registerAccountAndSessionMethodsWithDispatcher:dispatcher
                                               services:services
                                       registrationGate:registrationGate];
}

#pragma mark - Endpoint Registration Methods


+ (void)registerAccountAndSessionMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                              services:(id<XrpcRoutePackServices>)services
                                     registrationGate:(nullable id<PDSRegistrationGate>)registrationGate {
    // This method will be implemented in multiple parts due to size constraints
    // Part 1: createAccount, createSession, getSession, refreshSession, deleteSession
    [self registerAccountCreationAndSessionEndpoints:dispatcher
                                           services:services
                                   registrationGate:registrationGate];
    
    // Part 2: Invite codes
    [self registerInviteCodeEndpoints:dispatcher
                            services:services];
    
    // Part 3: App passwords
    [self registerAppPasswordEndpoints:dispatcher
                             services:services];
    
    // Part 4: Email and account management
    [self registerEmailAndAccountEndpoints:dispatcher
                                 services:services];
    
    // Part 5: Account lifecycle (getAccount, deleteAccount, checkAccountStatus, activate, deactivate)
    [self registerAccountLifecycleEndpoints:dispatcher
                                  services:services];
}

#pragma mark - Helper Registration Methods






#pragma mark - Health Endpoint



@end
