#import "Network/XrpcMethodRegistry.h"
#import "Admin/PDSAdminAuth.h"
#import "Admin/PDSAdminController.h"
#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSBlobService.h"
#import "Services/PDS/PDSRecordService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/NotificationService.h"
#import "Auth/CryptoUtils.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/Secp256k1.h"
#import "Blob/BlobStorage.h"
#import "Compat/PDSTypes.h"
#import "Core/CID.h"
#import "Core/DID.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Core/TID.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Email/PDSEmailProvider.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Identity/HandleResolver.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Network/XrpcAdminMethods.h"
#import "Network/XrpcAppBskyMethods.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcIdentityMethods.h"
#import "Network/XrpcLabelMethods.h"
#import "Network/XrpcRepoMethods.h"
#import "Network/XrpcModerationMethods.h"
#import "Network/XrpcVendorMethods.h"
#import "Network/XrpcLexiconResolver.h"
#import "Network/XrpcProxyInterceptor.h"
#import "Network/XrpcServerMethods.h"
#import "Network/XrpcServiceAuthHelper.h"
#import "Network/XrpcSyncMethods.h"
#import "PLC/DIDPLCResolver.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCRotationKeyManager.h"
#import "Repository/CAR.h"
#import "Security/PDSAuthzManager.h"
#import "Services/Core/PDSPhoneVerificationProvider.h"
#import "Registration/PDSRegistrationGate.h"
#import <CommonCrypto/CommonKeyDerivation.h>

static NSString *const kTempFetchLabelsDeprecationWarning =
    @"299 - \"com.atproto.temp.fetchLabels is deprecated; use "
    @"com.atproto.label.queryLabels or com.atproto.label.subscribeLabels\"";
static NSString *const kTempFetchLabelsSunsetDate = @"2027-12-31T00:00:00Z";
static NSString *const kTempFetchLabelsSuccessorLink =
    @"</xrpc/com.atproto.label.queryLabels>; rel=\"successor-version\", "
    @"</xrpc/com.atproto.label.subscribeLabels>; rel=\"successor-version\"";

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

static NSString *inviteAlphabet(void) {
  return @"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
}

static NSString *generateInviteCode(NSUInteger groupCount,
                                    NSUInteger groupLength) {
  NSString *alphabet = inviteAlphabet();
  NSMutableString *code = [NSMutableString string];
  for (NSUInteger groupIndex = 0; groupIndex < groupCount; groupIndex++) {
    if (groupIndex > 0) {
      [code appendString:@"-"];
    }
    for (NSUInteger i = 0; i < groupLength; i++) {
      unichar c = [alphabet
          characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
      [code appendFormat:@"%C", c];
    }
  }
  return code;
}

static BOOL createInviteCodeInDatabase(PDSServiceDatabases *serviceDatabases,
                                       NSString *accountDid, NSInteger maxUses,
                                       NSString **outCode, NSError **error) {
  if (maxUses <= 0) {
    if (error) {
      *error =
          [NSError errorWithDomain:@"com.atproto.server"
                              code:400
                          userInfo:@{
                            NSLocalizedDescriptionKey : @"useCount must be > 0"
                          }];
    }
    return NO;
  }

  const NSUInteger kMaxAttempts = 10;
  NSError *lastError = nil;
  for (NSUInteger attempt = 0; attempt < kMaxAttempts; attempt++) {
    NSString *code = generateInviteCode(4, 5);
    NSError *createError = nil;
    if ([serviceDatabases createInviteCode:code
                                forAccount:accountDid
                                   maxUses:maxUses
                                     error:&createError]) {
      if (outCode) {
        *outCode = code;
      }
      return YES;
    }
    lastError = createError;
  }

  if (error) {
    *error = lastError
                 ?: [NSError errorWithDomain:@"com.atproto.server"
                                        code:500
                                    userInfo:@{
                                      NSLocalizedDescriptionKey :
                                          @"Failed to create invite code"
                                    }];
  }
  return NO;
}

static void setSubscribeReposUpgradeRequired(HttpRequest *request,
                                             HttpResponse *response) {
  if (request.method != HttpMethodGET) {
    response.statusCode = HttpStatusMethodNotAllowed;
    [response setHeader:@"GET" forKey:@"Allow"];
    [response setJsonBody:@{
      @"error" : @"MethodNotAllowed",
      @"message" : @"subscribeRepos only supports GET"
    }];
    return;
  }

  response.statusCode = 426;
  [response setHeader:@"websocket" forKey:@"Upgrade"];
  [response setHeader:@"Upgrade" forKey:@"Connection"];
  [response setJsonBody:@{
    @"error" : @"UpgradeRequired",
    @"message" : @"WebSocket upgrade required for subscribeRepos"
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
  if (atRange.location == NSNotFound || atRange.location == 0 ||
      atRange.location == email.length - 1) {
    return NO;
  }
  NSString *domain = [email substringFromIndex:atRange.location + 1];
  return [domain containsString:@"."];
}

static BOOL isLikelyPhoneNumber(NSString *phoneNumber) {
  if (![phoneNumber isKindOfClass:[NSString class]]) {
    return NO;
  }

  NSString *trimmed = [phoneNumber
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  if (trimmed.length < 7 || trimmed.length > 32) {
    return NO;
  }

  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"+0123456789 -()."];
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
      @"com.atproto.transition:generic" : @"atproto transition:generic",
      @"com.atproto.transition:email" : @"atproto transition:email",
      @"com.atproto.transition:chat.bsky" :
          @"atproto transition:generic transition:chat.bsky"
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

static NSArray<NSDictionary *> *
buildHandleAvailabilitySuggestions(NSString *normalizedHandle,
                                   PDSServiceDatabases *serviceDatabases) {
  NSArray<NSString *> *parts =
      [normalizedHandle componentsSeparatedByString:@"."];
  if (parts.count < 2) {
    return @[];
  }

  NSString *stem = parts.firstObject.length > 0 ? parts.firstObject : @"user";
  NSString *domain = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)]
      componentsJoinedByString:@"."];
  NSMutableArray<NSDictionary *> *suggestions = [NSMutableArray array];

  for (NSInteger suffix = 1; suffix <= 25 && suggestions.count < 3;
       suffix += 1) {
    NSString *candidate =
        [NSString stringWithFormat:@"%@%ld.%@", stem, (long)suffix, domain];
    NSError *handleError = nil;
    if (![ATProtoHandleValidator validateHandle:candidate error:&handleError]) {
      continue;
    }
    NSError *reservedError = nil;
    if (isReservedHandle(candidate, serviceDatabases, &reservedError) ||
        reservedError) {
      continue;
    }
    if ([serviceDatabases getAccountByHandle:candidate error:nil]) {
      continue;
    }
    [suggestions
        addObject:@{@"handle" : candidate, @"method" : @"numeric-suffix"}];
  }

  return suggestions;
}

static NSArray<NSDictionary *> *
loadFetchedLabels(PDSServiceDatabases *serviceDatabases, BOOL hasSince,
                  NSInteger sinceSeconds, NSInteger limit, NSError **error) {
  PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
  if (!db) {
    return nil;
  }

  NSArray<NSDictionary *> *rows = nil;
  if (hasSince) {
    rows = [db
        executeParameterizedQuery:
            @"SELECT src, uri, cid, val, neg, cts, exp FROM labels "
             "WHERE CAST(COALESCE(strftime('%s', cts), '0') AS INTEGER) >= ? "
             "ORDER BY id ASC LIMIT ?"
                           params:@[ @(sinceSeconds), @(limit) ]
                            error:error];
  } else {
    rows = [db executeParameterizedQuery:
                   @"SELECT src, uri, cid, val, neg, cts, exp FROM labels "
                    "ORDER BY id ASC LIMIT ?"
                                  params:@[ @(limit) ]
                                   error:error];
  }

  [db close];
  return rows;
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

  NSDate *expiresAt =
      [NSDate dateWithTimeIntervalSinceNow:kPlcOperationTokenTTLSeconds];
  NSDictionary *entry = @{@"token" : token, @"expiresAt" : expiresAt};
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
  if (![expected isKindOfClass:[NSString class]] ||
      ![expiresAt isKindOfClass:[NSDate class]]) {
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
+ (nullable NSData *)publicKeyBytesFromMultibase:(NSString *)multibase
                                           error:(NSError **)error {
  if (multibase.length < 2) {
    if (error) {
      *error = [NSError errorWithDomain:DIDErrorDomain
                                   code:DIDErrorInvalidDocument
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid publicKeyMultibase value"
                               }];
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
      *error = [NSError
          errorWithDomain:DIDErrorDomain
                     code:DIDErrorInvalidDocument
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Unsupported multibase encoding for signing key"
                 }];
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

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request {
  return [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                        jwtMinter:jwtMinter
                                  adminController:adminController
                                          request:request];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request
                              response:(HttpResponse *)response {
  return [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                        jwtMinter:jwtMinter
                                  adminController:adminController
                                          request:request
                                         response:response];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                            controller:(PDSController *)controller
                               request:(HttpRequest *)request
                              response:(HttpResponse *)response {
  return [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                       controller:controller
                                          request:request
                                         response:response];
}

static void registerMethodsWithDispatcherUsingServices(
    Class registryClass, XrpcDispatcher *dispatcher,
    id<PDSAccountService> accountService, PDSRecordService *recordService,
    PDSBlobService *blobService, PDSRepositoryService *repositoryService,
    PDSRelayService *relayService, id<PDSAdminController> adminController,
    PDSBlobAuditManager *blobAuditManager,
    PDSServiceDatabases *serviceDatabases, PDSDatabasePool *userDatabasePool,
    JWTMinter *jwtMinter, PDSConfiguration *config,
    id<PDSEmailProvider> emailProvider,
    SubscribeReposHandler *subscribeReposHandler) {

  [XrpcLexiconResolver registerResolveLexiconMethodOnDispatcher:dispatcher
                                                   configuration:config];

  [XrpcProxyInterceptor installOnDispatcher:dispatcher
                              configuration:config
                                  jwtMinter:jwtMinter
                            adminController:adminController
                           serviceDatabases:serviceDatabases
                           userDatabasePool:userDatabasePool];


  // Create registration gate from configuration
  NSError *gateError = nil;
  id<PDSRegistrationGate> registrationGate =
      [PDSRegistrationGateFactory gateFromConfiguration:config
                                       serviceDatabases:serviceDatabases
                                                  error:&gateError];
  if (gateError) {
    PDS_LOG_ERROR(@"Failed to create registration gate: %@", gateError);
  }

  // Register domain modules in order
  [XrpcServerMethods registerWithDispatcher:dispatcher
                                  jwtMinter:jwtMinter
                            adminController:adminController
                             accountService:accountService
                          repositoryService:repositoryService
                           serviceDatabases:serviceDatabases
                           userDatabasePool:userDatabasePool
                              configuration:config
                   enforceDidWebServiceAuth:NO
                           registrationGate:registrationGate];

  [XrpcIdentityMethods registerWithDispatcher:dispatcher
                                    jwtMinter:jwtMinter
                              adminController:adminController
                             serviceDatabases:serviceDatabases
                             userDatabasePool:userDatabasePool
                                configuration:config
                                emailProvider:emailProvider
                        subscribeReposHandler:subscribeReposHandler];

  [XrpcRepoMethods registerWithDispatcher:dispatcher
                                jwtMinter:jwtMinter
                          adminController:adminController
                           accountService:accountService
                            recordService:recordService
                              blobService:blobService
                        repositoryService:repositoryService
                         serviceDatabases:serviceDatabases];

  [XrpcSyncMethods registerWithDispatcher:dispatcher
                                jwtMinter:jwtMinter
                          adminController:adminController
                         serviceDatabases:serviceDatabases
                         userDatabasePool:userDatabasePool
                            recordService:recordService
                              blobService:blobService
                        repositoryService:repositoryService
                              relayService:relayService
                            configuration:config];

  [XrpcAppBskyMethods registerWithDispatcher:dispatcher
                            serviceDatabases:serviceDatabases
                                    jwtMinter:jwtMinter
                              adminController:adminController
                                emailProvider:emailProvider];

  [XrpcAdminMethods registerWithDispatcher:dispatcher

                          serviceDatabases:serviceDatabases
                                 jwtMinter:jwtMinter
                           adminController:adminController
                         repositoryService:repositoryService
                              auditManager:blobAuditManager];

  [XrpcLabelMethods registerWithDispatcher:dispatcher
                          serviceDatabases:serviceDatabases
                                 jwtMinter:jwtMinter
                           adminController:adminController
                             configuration:config];

  [XrpcModerationMethods registerWithDispatcher:dispatcher
                                      jwtMinter:jwtMinter
                                adminController:adminController
                               serviceDatabases:serviceDatabases];

  [XrpcVendorMethods registerWithDispatcher:dispatcher
                          serviceDatabases:serviceDatabases
                                 jwtMinter:jwtMinter
                           adminController:adminController
                         repositoryService:repositoryService];
}

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller {
  if (!dispatcher || !controller) {
    return;
  }
  PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
  registerMethodsWithDispatcherUsingServices(
      self, dispatcher, controller.accountService, controller.recordService,
      controller.blobService, controller.repositoryService,
      controller.relayService, controller.adminController,
      controller.application.blobAuditManager,
      controller.serviceDatabases, controller.userDatabasePool,
      controller.jwtMinter, config, nil,
      controller.subscribeReposHandler);
}

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                          application:(PDSApplication *)application {
  if (!dispatcher || !application) {
    return;
  }
  registerMethodsWithDispatcherUsingServices(
      self, dispatcher, application.accountService, application.recordService,
      application.blobService, application.repositoryService,
      application.relayService, application.adminController,
      application.blobAuditManager,
      application.serviceDatabases, application.userDatabasePool,
      application.jwtMinter, application.configuration,
      application.emailProvider,
      application.subscribeReposHandler);
}

@end
