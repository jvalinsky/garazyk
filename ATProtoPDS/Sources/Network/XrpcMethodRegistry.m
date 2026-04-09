#import "Network/XrpcMethodRegistry.h"
#import "Admin/PDSAdminAuth.h"
#import "Admin/PDSAdminController.h"
#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "App/Services/PDSAccountService.h"
#import "App/Services/PDSBlobService.h"
#import "App/Services/PDSRecordService.h"
#import "App/Services/PDSRepositoryService.h"
#import "AppView/ActorService.h"
#import "AppView/FeedService.h"
#import "AppView/NotificationService.h"
#import "Auth/CryptoUtils.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/Secp256k1.h"
#import "Blob/BlobStorage.h"
#import "Compat/PDSTypes.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoValidator.h"
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
#import "Network/XrpcServerMethods.h"
#import "Network/XrpcServiceAuthHelper.h"
#import "Network/XrpcSyncMethods.h"
#import "PLC/DIDPLCResolver.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCRotationKeyManager.h"
#import "Repository/CAR.h"
#import "Security/PDSAuthzManager.h"
#import "Services/PDSPhoneVerificationProvider.h"
#import <CommonCrypto/CommonKeyDerivation.h>
#include <errno.h>

static NSString *const kLexiconResolveErrorDomain = @"XrpcLexiconResolve";
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

static BOOL authorizeAdminRequest(HttpRequest *request, HttpResponse *response,
                                  PDSServiceDatabases *serviceDatabases,
                                  JWTMinter *jwtMinter,
                                  id<PDSAdminController> adminController) {
  return [XrpcAuthHelper authorizeAdminRequest:request
                                      response:response
                              serviceDatabases:serviceDatabases
                                     jwtMinter:jwtMinter
                              adminController:adminController];
}

// Implementation of resolveDid — now delegates to XrpcIdentityHelper
static NSDictionary *resolveDid(NSString *did, PDSServiceDatabases *dbs,
                                PDSConfiguration *config, NSError **error) {
  return [XrpcIdentityHelper resolveDid:did
                       serviceDatabases:dbs
                          configuration:config
                                  error:error];
}

static NSDictionary *loadLexiconJSONForNSID(NSString *nsid,
                                            NSString *dataDirectory,
                                            NSError **error) {
  ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
  NSArray<NSString *> *searchPaths =
      [registry searchPathsForDirectory:dataDirectory];
  NSString *relativePath =
      [[nsid stringByReplacingOccurrencesOfString:@"." withString:@"/"]
          stringByAppendingString:@".json"];
  NSFileManager *fileManager = [NSFileManager defaultManager];

  for (NSString *basePath in searchPaths) {
    NSString *candidate =
        [basePath stringByAppendingPathComponent:relativePath];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] ||
        isDirectory) {
      continue;
    }

    NSError *readError = nil;
    NSData *data =
        [NSData dataWithContentsOfFile:candidate options:0 error:&readError];
    if (!data) {
      if (error) {
        *error = readError
                     ?: [NSError errorWithDomain:kLexiconResolveErrorDomain
                                            code:500
                                        userInfo:@{
                                          NSLocalizedDescriptionKey :
                                              @"Failed to read lexicon file"
                                        }];
      }
      return nil;
    }

    NSError *parseError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data
                                              options:0
                                                error:&parseError];
    if (![json isKindOfClass:[NSDictionary class]]) {
      if (error) {
        *error = parseError
                     ?: [NSError errorWithDomain:kLexiconResolveErrorDomain
                                            code:500
                                        userInfo:@{
                                          NSLocalizedDescriptionKey :
                                              @"Lexicon JSON is not an object"
                                        }];
      }
      return nil;
    }

    return (NSDictionary *)json;
  }

  if (error) {
    *error = [NSError
        errorWithDomain:kLexiconResolveErrorDomain
                   code:404
               userInfo:@{NSLocalizedDescriptionKey : @"Lexicon not found"}];
  }
  return nil;
}

static NSDictionary *resolveLexiconResponseForNSID(NSString *nsid,
                                                   PDSConfiguration *config,
                                                   NSError **error) {
  NSDictionary *schema =
      loadLexiconJSONForNSID(nsid, config.dataDirectory, error);
  if (!schema) {
    return nil;
  }

  NSError *cborError = nil;
  NSData *cborData =
      [ATProtoCBORSerialization encodeDataWithJSONObject:schema
                                                   error:&cborError];
  if (!cborData) {
    if (error) {
      *error = cborError
                   ?: [NSError errorWithDomain:kLexiconResolveErrorDomain
                                          code:500
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"Failed to encode lexicon schema"
                                      }];
    }
    return nil;
  }

  CID *schemaCID = [CID cidWithDigest:[CID sha256Digest:cborData] codec:0x71];
  if (!schemaCID) {
    if (error) {
      *error = [NSError
          errorWithDomain:kLexiconResolveErrorDomain
                     code:500
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to compute lexicon CID"
                 }];
    }
    return nil;
  }

  NSString *hostname = config.serverHost ?: @"localhost";
  NSString *serverDid = [NSString stringWithFormat:@"did:web:%@", hostname];
  NSString *uri =
      [NSString stringWithFormat:@"at://%@/com.atproto.lexicon.schema/%@",
                                 serverDid, nsid];

  return @{
    @"uri" : uri,
    @"cid" : schemaCID.stringValue ?: @"",
    @"schema" : schema
  };
}

static NSString *trimmedNonEmptyString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [value
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  return trimmed.length > 0 ? trimmed : nil;
}

static BOOL parseUnsignedLongLongString(NSString *value,
                                        unsigned long long *result) {
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
      @"connection", @"keep-alive", @"proxy-authenticate",
      @"proxy-authorization", @"te", @"trailer", @"transfer-encoding",
      @"upgrade", @"host", @"content-length", @"atproto-proxy",
      // Strip upstream CORS headers — our XrpcHandler sets these explicitly.
      // Copying them from the AppView creates duplicate *, * values.
      @"access-control-allow-origin", @"access-control-allow-methods",
      @"access-control-allow-headers", @"access-control-max-age",
      @"access-control-expose-headers"
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

  NSString *fullyQualified = [[did.lowercaseString
      stringByAppendingString:normalizedFragment] lowercaseString];
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
    if (([type containsString:@"appview"] ||
         [identifier containsString:@"appview"]) &&
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
      *error =
          [NSError errorWithDomain:@"XrpcProxy"
                              code:1
                          userInfo:@{
                            NSLocalizedDescriptionKey : @"Proxy target is empty"
                          }];
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
    serviceFragment =
        [trimmedDescriptor substringFromIndex:fragmentRange.location + 1];
  }

  if (![did hasPrefix:@"did:"]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"XrpcProxy"
                     code:2
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Proxy target must be an absolute URL or DID reference"
                 }];
    }
    return nil;
  }

  // Special case for configured AppView, similar to reference implementation
  NSString *configuredDescriptor = [NSString stringWithFormat:@"%@#bsky_appview", config.appViewDID];
  if ([trimmedDescriptor isEqualToString:configuredDescriptor]) {
    NSString *appViewURL = config.appViewURL;
    if (appViewURL.length > 0) {
      return [NSURL URLWithString:appViewURL];
    }
  }

  DIDResolver *resolver = [[DIDResolver alloc] init];
  if (config.plcURL.length > 0) {
    resolver.plcURL = config.plcURL;
  }

  NSError *resolveError = nil;
  DIDDocument *document = [resolver resolveDIDSync:did error:&resolveError];
  if (!document) {
    if (error) {
      *error = resolveError
                   ?: [NSError errorWithDomain:@"XrpcProxy"
                                          code:3
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"Failed to resolve proxy DID"
                                      }];
    }
    return nil;
  }

  NSDictionary *serviceEntry =
      proxyServiceEntryFromDocument(document, did, serviceFragment);
  if (!serviceEntry) {
    if (error) {
      NSString *message =
          serviceFragment.length > 0
              ? [NSString stringWithFormat:
                              @"Service '#%@' was not found in DID document",
                              serviceFragment]
              : @"No service endpoint found in DID document";
      *error = [NSError errorWithDomain:@"XrpcProxy"
                                   code:4
                               userInfo:@{NSLocalizedDescriptionKey : message}];
    }
    return nil;
  }

  NSString *endpoint = trimmedNonEmptyString(serviceEntry[@"serviceEndpoint"]);
  NSURL *endpointURL =
      endpoint.length > 0 ? [NSURL URLWithString:endpoint] : nil;
  if (endpointURL.scheme.length == 0 || endpointURL.host.length == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"XrpcProxy"
                     code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Resolved service endpoint is not a valid absolute URL"
                 }];
    }
    return nil;
  }
  return endpointURL;
}

static NSURL *proxyURLForMethodAndQuery(NSURL *baseURL, NSString *methodId,
                                        NSString *queryString) {
  NSURLComponents *components =
      [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
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
  // Check for explicit URL override first
  NSString *envTarget = trimmedNonEmptyString(
      [[NSProcessInfo processInfo] environment][@"PDS_APPVIEW_URL"]);
  if (envTarget.length > 0) {
    return envTarget;
  }

  NSString *configTarget =
      trimmedNonEmptyString([config stringForKey:@"appview.url"]);
  if (configTarget.length > 0) {
    return configTarget;
  }

  return trimmedNonEmptyString([config stringForKey:@"app_view.url"]);
}

static NSString *configuredAppViewProxyDescriptor(PDSConfiguration *config) {
  // Check for explicit descriptor override
  NSString *envDescriptor = trimmedNonEmptyString(
      [[NSProcessInfo processInfo] environment][@"PDS_APPVIEW_DESCRIPTOR"]);
  if (envDescriptor.length > 0) {
    return envDescriptor;
  }

  // Also check for explicit URL override in environment (common in tests)
  NSString *envURL = trimmedNonEmptyString(
      [[NSProcessInfo processInfo] environment][@"PDS_APPVIEW_URL"]);
  if (envURL.length > 0) {
    return envURL;
  }

  // Construct DID#service descriptor from AppView configuration
  NSString *appViewDID = config.appViewDID;
  if (appViewDID.length > 0) {
    return [NSString stringWithFormat:@"%@#bsky_appview", appViewDID];
  }

  // Fallback to configured URL
  NSString *appViewURL = config.appViewURL;
  if (appViewURL.length > 0) {
    return appViewURL;
  }

  return nil;
}

static BOOL proxyXrpcRequest(HttpRequest *request, HttpResponse *response,
                             NSString *methodId, NSString *proxyDescriptor,
                             PDSConfiguration *config,
                             BOOL explicitProxyHeader,
                             JWTMinter *jwtMinter,
                             id<PDSAdminController> adminController,
                             PDSServiceDatabases *serviceDatabases,
                             PDSDatabasePool *userDatabasePool) {
  NSError *targetError = nil;
  NSURL *baseURL =
      proxyBaseURLFromDescriptor(proxyDescriptor, config, &targetError);
  if (!baseURL) {
    response.statusCode = explicitProxyHeader ? HttpStatusBadRequest : 502;
    [response setJsonBody:@{
      @"error" : explicitProxyHeader ? @"InvalidAtprotoProxy"
                                     : @"AppViewProxyUnavailable",
      @"message" : targetError.localizedDescription
          ?: @"Failed to resolve proxy target"
    }];
    return YES;
  }

  NSURL *targetURL =
      proxyURLForMethodAndQuery(baseURL, methodId, request.queryString ?: @"");
  if (!targetURL) {
    response.statusCode = explicitProxyHeader ? HttpStatusBadRequest : 502;
    [response setJsonBody:@{
      @"error" : @"ProxyTargetInvalid",
      @"message" : @"Failed to construct upstream URL"
    }];
    return YES;
  }

  NSInteger hopCount =
      [[request headerForKey:@"x-objpds-proxy-hop"] integerValue];
  if (hopCount >= 4) {
    response.statusCode = 502;
    [response setJsonBody:@{
      @"error" : @"ProxyLoopDetected",
      @"message" : @"Rejected proxy request after too many proxy hops"
    }];
    return YES;
  }

  NSMutableURLRequest *upstreamRequest = [NSMutableURLRequest
       requestWithURL:targetURL
          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
      timeoutInterval:30.0];
  upstreamRequest.HTTPMethod = request.methodString ?: @"GET";
  if (request.body.length > 0 && request.method != HttpMethodGET &&
      request.method != HttpMethodHEAD) {
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

    // Normalize common header casing for upstream compatibility.
    NSString *headerFieldName = key;
    if ([lowercaseKey isEqualToString:@"authorization"]) {
      headerFieldName = @"Authorization";
    } else if ([lowercaseKey isEqualToString:@"dpop"]) {
      headerFieldName = @"DPoP";
    } else if ([lowercaseKey isEqualToString:@"atproto-proxy"]) {
      headerFieldName = @"Atproto-Proxy";
    }

    [upstreamRequest setValue:value forHTTPHeaderField:headerFieldName];
  }
  [upstreamRequest setValue:[NSString
                                stringWithFormat:@"%ld", (long)(hopCount + 1)]
         forHTTPHeaderField:@"x-objpds-proxy-hop"];

  // Service auth: replace user's Bearer token with a service auth JWT
  // so the upstream AppView trusts the request.
  if (jwtMinter && serviceDatabases && userDatabasePool) {
    NSString *authHeader =
        trimmedNonEmptyString([request headerForKey:@"Authorization"]);
    if ([authHeader.lowercaseString hasPrefix:@"bearer "]) {
      NSString *did = [XrpcMethodRegistry
          extractDIDFromAuthHeader:authHeader
                         jwtMinter:jwtMinter
                   adminController:adminController
                           request:request];
      if (did.length > 0) {
        NSError *storeError = nil;
        PDSActorStore *store =
            [userDatabasePool storeForDid:did error:&storeError];
        if (store) {
          // Resolve the upstream DID for the audience claim
          NSString *upstreamDID = nil;
          if ([proxyDescriptor hasPrefix:@"did:"]) {
            NSRange hashRange = [proxyDescriptor rangeOfString:@"#"];
            upstreamDID = (hashRange.location != NSNotFound)
                              ? [proxyDescriptor
                                    substringToIndex:hashRange.location]
                              : proxyDescriptor;
          }
          if (!upstreamDID) {
            // Use the base URL host as a fallback audience
            upstreamDID =
                [NSString stringWithFormat:@"did:web:%@", baseURL.host];
          }

          long long nowSeconds =
              (long long)[[NSDate date] timeIntervalSince1970];
          NSDictionary *servicePayload = @{
            @"iss" : did,
            @"sub" : did,
            @"aud" : upstreamDID,
            @"lxm" : methodId ?: @"",
            @"iat" : @(nowSeconds),
            @"exp" : @(nowSeconds + 60),
            @"jti" : [[NSUUID UUID] UUIDString]
          };

          NSError *mintError = nil;
          NSString *serviceToken =
              [jwtMinter signPayload:servicePayload
                    actorKeyManager:store.keyManager
                              error:&mintError];
          if (serviceToken.length > 0) {
            [upstreamRequest
                setValue:[NSString stringWithFormat:@"Bearer %@",
                                                    serviceToken]
                forHTTPHeaderField:@"Authorization"];
          }
        }
      }
    }
  }

  // Use NSURLSession with redirect blocking to avoid "Invalid redirect" errors.
  // Upstream redirects are passed through to the client instead of followed.
  NSURLSessionConfiguration *sessionConfig =
      [NSURLSessionConfiguration ephemeralSessionConfiguration];
  sessionConfig.timeoutIntervalForRequest = 30.0;
  NSURLSession *session = [NSURLSession
      sessionWithConfiguration:sessionConfig
                      delegate:nil
                 delegateQueue:nil];

  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  __block NSHTTPURLResponse *upstreamResponse = nil;
  __block NSData *upstreamBody = nil;
  __block NSError *proxyError = nil;

  NSURLSessionDataTask *task = [session
      dataTaskWithRequest:upstreamRequest
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
          upstreamBody = data;
          upstreamResponse = ([resp isKindOfClass:[NSHTTPURLResponse class]])
                                 ? (NSHTTPURLResponse *)resp
                                 : nil;
          proxyError = error;
          dispatch_semaphore_signal(sem);
        }];
  [task resume];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  [session finishTasksAndInvalidate];

  if (!upstreamResponse) {
    response.statusCode = 502;
    [response setJsonBody:@{
      @"error" : @"ProxyRequestFailed",
      @"message" : proxyError.localizedDescription ?: @"Upstream request failed"
    }];
    return YES;
  }

  response.statusCode = (HttpStatusCode)upstreamResponse.statusCode;
  response.contentType = nil;

  NSDictionary *upstreamHeaders = upstreamResponse.allHeaderFields ?: @{};
  for (id rawKey in upstreamHeaders) {
    NSString *key = [rawKey isKindOfClass:[NSString class]]
                        ? (NSString *)rawKey
                        : [rawKey description];
    NSString *value = [upstreamHeaders[rawKey] isKindOfClass:[NSString class]]
                          ? upstreamHeaders[rawKey]
                          : [upstreamHeaders[rawKey] description];
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
  } else if (request.method != HttpMethodHEAD && upstreamBody &&
             upstreamBody.length == 0) {
    [response setBodyData:[NSData data]];
  }

  return YES;
}

static void installXrpcProxyInterceptor(XrpcDispatcher *dispatcher,
                                        PDSConfiguration *config,
                                        JWTMinter *jwtMinter,
                                        id<PDSAdminController> adminController,
                                        PDSServiceDatabases *serviceDatabases,
                                        PDSDatabasePool *userDatabasePool) {
  dispatcher.requestInterceptor =
      ^BOOL(HttpRequest *request, HttpResponse *response, NSString *methodId,
            BOOL hasLocalHandler) {
        NSString *explicitProxyTarget =
            trimmedNonEmptyString([request headerForKey:@"atproto-proxy"]);
        if (explicitProxyTarget.length > 0) {
          // Explicitly proxied requests override forceLocal, but NOT for core PDS identity methods
          // that MUST be handled locally to avoid infinite loops or identity sync issues.
          BOOL forceLocal = [methodId isEqualToString:@"com.atproto.identity.resolveDid"] ||
                            [methodId isEqualToString:@"com.atproto.identity.updateHandle"];

          if (hasLocalHandler && forceLocal) {
            return NO;
          }
          return proxyXrpcRequest(request, response, methodId,
                                  explicitProxyTarget, config, YES,
                                  jwtMinter, adminController,
                                  serviceDatabases, userDatabasePool);
        }

        if (hasLocalHandler || ![methodId hasPrefix:@"app.bsky."]) {
          return NO;
        }

        if ([[request headerForKey:@"x-objpds-proxy-hop"] integerValue] > 0) {
          return NO;
        }

        NSString *fallbackDescriptor = configuredAppViewProxyDescriptor(config);
        if (fallbackDescriptor.length == 0) {
          return NO;
        }

        return proxyXrpcRequest(request, response, methodId, fallbackDescriptor,
                                config, NO, jwtMinter, adminController,
                                serviceDatabases, userDatabasePool);
      };
}

static BOOL parseByteRangeHeader(NSString *rangeHeader,
                                 unsigned long long totalLength, BOOL *hasRange,
                                 BOOL *satisfiable, unsigned long long *start,
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
  if (!parseUnsignedLongLongString(endPart, &suffixLength) ||
      suffixLength == 0) {
    if (satisfiable) {
      *satisfiable = NO;
    }
    return YES;
  }

  unsigned long long parsedStart =
      (suffixLength >= totalLength) ? 0 : (totalLength - suffixLength);
  if (start) {
    *start = parsedStart;
  }
  if (end) {
    *end = totalLength - 1;
  }
  return YES;
}

static HttpResponseBodyChunkProducer
blobFileChunkProducer(NSString *path, unsigned long long startOffset,
                      unsigned long long endOffset, NSError **error) {
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
  if (!fileHandle) {
    if (error) {
      *error = [NSError errorWithDomain:@"XrpcBlobStream"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to open blob file for streaming"
                               }];
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
                               userInfo:@{
                                 NSLocalizedDescriptionKey : exception.reason
                                     ?: @"Failed to seek blob file"
                               }];
    }
    return nil;
  }

  __block NSFileHandle *capturedHandle = fileHandle;
  __block unsigned long long bytesRemaining =
      (endOffset >= startOffset) ? (endOffset - startOffset + 1) : 0;
  static const NSUInteger kBlobChunkSize = 64 * 1024;

  return ^NSData *_Nullable(NSError **producerError) {
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

    NSUInteger readLength =
        (NSUInteger)MIN((unsigned long long)kBlobChunkSize, bytesRemaining);
    NSData *chunk = [capturedHandle readDataOfLength:readLength];
    if (chunk.length == 0) {
      @try {
        [capturedHandle closeFile];
      } @catch (__unused NSException *closeException) {
      }
      capturedHandle = nil;
      if (producerError && bytesRemaining > 0) {
        *producerError =
            [NSError errorWithDomain:@"XrpcBlobStream"
                                code:3
                            userInfo:@{
                              NSLocalizedDescriptionKey :
                                  @"Unexpected end-of-file while streaming blob"
                            }];
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

static void registerLexiconResolveMethod(XrpcDispatcher *dispatcher,
                                         PDSConfiguration *config) {
  [dispatcher registerComAtprotoLexiconResolveLexicon:^(
                  HttpRequest *request, HttpResponse *response) {
    if (request.method != HttpMethodGET) {
      response.statusCode = HttpStatusMethodNotAllowed;
      [response setHeader:@"GET" forKey:@"Allow"];
      [response setJsonBody:@{
        @"error" : @"MethodNotAllowed",
        @"message" : @"Expected GET"
      }];
      return;
    }

    NSString *nsid = [request queryParamForKey:@"nsid"];
    if (nsid.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing nsid parameter"
      }];
      return;
    }

    NSError *nsidError = nil;
    if (![ATProtoValidator validateNSID:nsid error:&nsidError]) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : nsidError.localizedDescription ?: @"Invalid NSID"
      }];
      return;
    }

    NSError *resolveError = nil;
    NSDictionary *result =
        resolveLexiconResponseForNSID(nsid, config, &resolveError);
    if (!result) {
      if ([resolveError.domain isEqualToString:kLexiconResolveErrorDomain] &&
          resolveError.code == 404) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
          @"error" : @"LexiconNotFound",
          @"message" : resolveError.localizedDescription ?: @"Lexicon not found"
        }];
        return;
      }
      response.statusCode = HttpStatusInternalServerError;
      [response setJsonBody:@{
        @"error" : @"InternalError",
        @"message" : resolveError.localizedDescription
            ?: @"Failed to resolve lexicon"
      }];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
  }];
}

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
    PDSServiceDatabases *serviceDatabases, PDSDatabasePool *userDatabasePool,
    JWTMinter *jwtMinter, PDSConfiguration *config,
    id<PDSEmailProvider> emailProvider,
    SubscribeReposHandler *subscribeReposHandler) {

  // Install proxy interceptor for AppView delegation
  installXrpcProxyInterceptor(dispatcher, config, jwtMinter, adminController,
                              serviceDatabases, userDatabasePool);

  // Register lexicon resolution method
  registerLexiconResolveMethod(dispatcher, config);

  // Register domain modules in order
  [XrpcServerMethods registerWithDispatcher:dispatcher
                                  jwtMinter:jwtMinter
                            adminController:adminController
                             accountService:accountService
                          repositoryService:repositoryService
                           serviceDatabases:serviceDatabases
                           userDatabasePool:userDatabasePool
                              configuration:config
                   enforceDidWebServiceAuth:NO];

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
                             adminController:adminController];

  [XrpcAdminMethods registerWithDispatcher:dispatcher
                          serviceDatabases:serviceDatabases
                                 jwtMinter:jwtMinter
                           adminController:adminController];

  [XrpcLabelMethods registerWithDispatcher:dispatcher
                          serviceDatabases:serviceDatabases
                                 jwtMinter:jwtMinter
                           adminController:adminController
                             configuration:config];

  [XrpcModerationMethods registerWithDispatcher:dispatcher
                                      jwtMinter:jwtMinter
                                adminController:adminController
                               serviceDatabases:serviceDatabases];
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
      application.serviceDatabases, application.userDatabasePool,
      application.jwtMinter, application.configuration,
      application.emailProvider,
      application.subscribeReposHandler);
}

@end
