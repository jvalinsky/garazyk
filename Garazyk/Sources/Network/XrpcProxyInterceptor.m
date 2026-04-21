#import "Network/XrpcProxyInterceptor.h"

#import "App/PDSConfiguration.h"
#import "Auth/JWT.h"
#import "Core/DID.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcHandler.h"

static NSString *trimmedNonEmptyString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [value
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  return trimmed.length > 0 ? trimmed : nil;
}

static BOOL isProxyHopByHopHeader(NSString *headerKey) {
  static NSSet<NSString *> *blocked = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    blocked = [NSSet setWithArray:@[
      @"connection", @"keep-alive", @"proxy-authenticate",
      @"proxy-authorization", @"te", @"trailer", @"transfer-encoding",
      @"upgrade", @"host", @"content-length", @"atproto-proxy",
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

  NSString *configuredDescriptor =
      [NSString stringWithFormat:@"%@#bsky_appview", config.appViewDID];
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

static NSString *configuredAppViewProxyDescriptor(PDSConfiguration *config) {
  NSString *envDescriptor = trimmedNonEmptyString(
      [[NSProcessInfo processInfo] environment][@"PDS_APPVIEW_DESCRIPTOR"]);
  if (envDescriptor.length > 0) {
    return envDescriptor;
  }

  NSString *envURL = trimmedNonEmptyString(
      [[NSProcessInfo processInfo] environment][@"PDS_APPVIEW_URL"]);
  if (envURL.length > 0) {
    return envURL;
  }

  NSString *appViewDID = config.appViewDID;
  if (appViewDID.length > 0) {
    return [NSString stringWithFormat:@"%@#bsky_appview", appViewDID];
  }

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

  NSInteger hopCount = [[request headerForKey:@"x-objpds-proxy-hop"] integerValue];
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
  [upstreamRequest setValue:[NSString stringWithFormat:@"%ld", (long)(hopCount + 1)]
         forHTTPHeaderField:@"x-objpds-proxy-hop"];

  if (jwtMinter && serviceDatabases && userDatabasePool) {
    NSString *authHeader =
        trimmedNonEmptyString([request headerForKey:@"Authorization"]);
    if ([authHeader.lowercaseString hasPrefix:@"bearer "]) {
      NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                     jwtMinter:jwtMinter
                                               adminController:adminController
                                                       request:request];
      if (did.length > 0) {
        NSError *storeError = nil;
        PDSActorStore *store = [userDatabasePool storeForDid:did error:&storeError];
        if (store) {
          NSString *upstreamDID = nil;
          if ([proxyDescriptor hasPrefix:@"did:"]) {
            NSRange hashRange = [proxyDescriptor rangeOfString:@"#"];
            upstreamDID = (hashRange.location != NSNotFound)
                              ? [proxyDescriptor substringToIndex:hashRange.location]
                              : proxyDescriptor;
          }
          if (!upstreamDID) {
            upstreamDID = [NSString stringWithFormat:@"did:web:%@", baseURL.host];
          }

          long long nowSeconds = (long long)[[NSDate date] timeIntervalSince1970];
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
          NSString *serviceToken = [jwtMinter signPayload:servicePayload
                                          actorKeyManager:store.keyManager
                                                    error:&mintError];
          if (serviceToken.length > 0) {
            [upstreamRequest setValue:[NSString stringWithFormat:@"Bearer %@",
                                                                  serviceToken]
                   forHTTPHeaderField:@"Authorization"];
          }
        }
      }
    }
  }

  NSURLSessionConfiguration *sessionConfig =
      [NSURLSessionConfiguration ephemeralSessionConfiguration];
  sessionConfig.timeoutIntervalForRequest = 30.0;
  NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig
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

@implementation XrpcProxyInterceptor

+ (void)installOnDispatcher:(XrpcDispatcher *)dispatcher
              configuration:(PDSConfiguration *)configuration
                  jwtMinter:(JWTMinter *)jwtMinter
            adminController:(id<PDSAdminController>)adminController
           serviceDatabases:(PDSServiceDatabases *)serviceDatabases
           userDatabasePool:(PDSDatabasePool *)userDatabasePool {
  dispatcher.requestInterceptor =
      ^BOOL(HttpRequest *request, HttpResponse *response, NSString *methodId,
            BOOL hasLocalHandler) {
        NSString *explicitProxyTarget =
            trimmedNonEmptyString([request headerForKey:@"atproto-proxy"]);
        if (explicitProxyTarget.length > 0) {
          BOOL forceLocal =
              [methodId isEqualToString:@"com.atproto.identity.resolveDid"] ||
              [methodId isEqualToString:@"com.atproto.identity.updateHandle"];

          if (hasLocalHandler && forceLocal) {
            return NO;
          }
          return proxyXrpcRequest(request, response, methodId,
                                  explicitProxyTarget, configuration, YES,
                                  jwtMinter, adminController, serviceDatabases,
                                  userDatabasePool);
        }

        if (hasLocalHandler || ![methodId hasPrefix:@"app.bsky."]) {
          // If we have a local handler AND an AppView is configured, prefer
          // the AppView for GET (query) requests. The PDS should handle
          // POST (mutation) endpoints locally since those modify state.
          if (hasLocalHandler && [methodId hasPrefix:@"app.bsky."]) {
            NSString *fallbackDescriptor =
                configuredAppViewProxyDescriptor(configuration);
            if (fallbackDescriptor.length > 0 &&
                request.method == HttpMethodGET &&
                [[request headerForKey:@"x-objpds-proxy-hop"] integerValue] == 0) {
              return proxyXrpcRequest(request, response, methodId,
                                      fallbackDescriptor, configuration, NO,
                                      jwtMinter, adminController, serviceDatabases,
                                      userDatabasePool);
            }
          }
          return NO;
        }

        if ([[request headerForKey:@"x-objpds-proxy-hop"] integerValue] > 0) {
          return NO;
        }

        NSString *fallbackDescriptor =
            configuredAppViewProxyDescriptor(configuration);
        if (fallbackDescriptor.length == 0) {
          return NO;
        }

        return proxyXrpcRequest(request, response, methodId, fallbackDescriptor,
                                configuration, NO, jwtMinter, adminController,
                                serviceDatabases, userDatabasePool);
      };
}

@end

