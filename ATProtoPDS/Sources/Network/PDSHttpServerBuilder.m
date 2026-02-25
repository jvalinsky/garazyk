/*!
 @file PDSHttpServerBuilder.m

 @abstract Implementation of HTTP server builder.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSHttpServerBuilder.h"
#import "../Admin/PDSAdminHandler.h"
#import "../App/Explore/ExploreHandler.h"
#import "../App/MSTViewer/MSTViewerHandler.h"
#import "../App/NodeInfo/NodeInfoHandler.h"
#import "../App/OAuthDemo/OAuthDemoHandler.h"
#import "../App/PDSApplication.h"
#import "../App/PDSConfiguration.h"
#import "../App/PDSController.h"
#import "../Auth/JWT.h"
#import "../Auth/OAuth2Handler.h"
#import "../Database/PDSDatabase.h"
#import "../Database/Service/ServiceDatabases.h"
#import "../Debug/PDSLogger.h"
#import "../Identity/ATProtoHandleValidator.h"
#import "../Sync/SubscribeReposHandler.h"
#import "HttpRequest.h"
#import "HttpResponse.h"
#import "HttpServer.h"
#import "PDSNetworkTransport.h"
#import "XrpcHandler.h"
#import "XrpcMethodRegistry.h"

@interface PDSHttpServerBuilder ()
@property(nonatomic, strong, nullable) PDSConfiguration *configuration;
@end

@implementation PDSHttpServerBuilder

#pragma mark - Initialization

- (instancetype)init {
  self = [super init];
  if (self) {
    _port = 2583;
    _enableXrpc = YES;
    _enableOAuth = YES;
    _enableExploreUI = YES;
    _enableOAuthDemo = YES;
    _enableMSTViewer = YES;
    _enableNodeInfo = YES;
  }
  return self;
}

- (instancetype)initWithConfiguration:(PDSConfiguration *)configuration {
  self = [self init];
  if (self) {
    _configuration = configuration;
    if (configuration) {
      _port = configuration.serverPort > 0 ? configuration.serverPort : 2583;
      _enableNodeInfo = configuration.nodeinfoEnabled;
      _issuer = [configuration canonicalIssuerWithPortHint:_port];
    }
  }
  return self;
}

- (NSArray<NSString *> *)getCorsAllowedOrigins {
  PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
  NSArray<NSString *> *defaultOrigins = @[ @"*" ];
  NSArray<NSString *> *origins = [config stringForKey:@"cors.allowed_origins"];
  return origins ?: defaultOrigins;
}

- (NSString *)getCorsAllowedMethods {
  PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
  NSString *defaultMethods = @"GET, POST, PUT, DELETE, OPTIONS, HEAD";
  NSString *methods = [config stringForKey:@"cors.allowed_methods"];
  return methods ?: defaultMethods;
}

- (NSString *)getCorsAllowedHeaders {
  PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
  NSString *defaultHeaders = @"DPoP, Authorization, Content-Type, *";
  NSString *headers = [config stringForKey:@"cors.allowed_headers"];
  return headers ?: defaultHeaders;
}

- (NSString *)getCorsMaxAge {
  PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
  NSInteger defaultMaxAge = 86400;
  NSInteger maxAge = [config integerForKey:@"cors.max_age"];
  return [NSString
      stringWithFormat:@"%ld", (long)(maxAge > 0 ? maxAge : defaultMaxAge)];
}

#pragma mark - Building

- (nullable HttpServer *)buildWithError:(NSError **)error {
  HttpServer *server = [HttpServer serverWithPort:self.port];

  if (![self configureServer:server error:error]) {
    return nil;
  }

  return server;
}

- (BOOL)configureServer:(HttpServer *)server error:(NSError **)error {
  if (!server) {
    if (error) {
      *error =
          [NSError errorWithDomain:@"PDSHttpServerBuilderErrorDomain"
                              code:1
                          userInfo:@{
                            NSLocalizedDescriptionKey : @"Server cannot be nil"
                          }];
    }
    return NO;
  }

  // Register OAuth routes first (specific paths take precedence)
  if (self.enableOAuth) {
    [self registerOAuthRoutesWithServer:server];
  }

  // Register XRPC routes
  if (self.enableXrpc) {
    [self registerXrpcRoutesWithServer:server];
  }

  // Register Explore UI routes
  ExploreHandler *exploreHandler = nil;
  if (self.enableExploreUI) {
    exploreHandler = [self registerExploreRoutesWithServer:server];
  }

  // Register OAuth Demo routes
  if (self.enableOAuthDemo) {
    [self registerOAuthDemoRoutesWithServer:server];
  }

  // Register MST Viewer routes
  if (self.enableMSTViewer) {
    [self registerMSTViewerRoutesWithServer:server];
  }

  // Register NodeInfo routes
  if (self.enableNodeInfo) {
    [self registerNodeInfoRoutesWithServer:server];
  }

  // Register .well-known routes (handle resolution)
  [self registerWellKnownRoutesWithServer:server];

  // Register Admin routes
  [self registerAdminRoutesWithServer:server];

  // Register wildcard route LAST (must be after all specific routes)
  if (self.enableExploreUI && exploreHandler) {
    [server addRoute:@"GET"
                path:@"/*"
             handler:^(HttpRequest *request, HttpResponse *response) {
               [exploreHandler handleRequest:request response:response];
             }];
  }

  return YES;
}

#pragma mark - Route Registration (Private)

- (void)registerOAuthRoutesWithServer:(HttpServer *)server {
  if (!self.serviceDatabases || !self.jwtMinter) {
    PDS_LOG_WARN(@"PDSHttpServerBuilder: OAuth routes not registered - missing "
                 @"serviceDatabases or jwtMinter");
    return;
  }

  NSError *dbError = nil;
  PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:&dbError];
  if (!db) {
    PDS_LOG_WARN(@"PDSHttpServerBuilder: OAuth routes not registered - could "
                 @"not get service database: %@",
                 dbError);
    return;
  }

  OAuth2Handler *oauthHandler = [[OAuth2Handler alloc] initWithDatabase:db];
  oauthHandler.minter = self.jwtMinter;
  oauthHandler.dataDirectory = self.dataDirectory;
  if (self.application.accountService) {
    oauthHandler.accountService = self.application.accountService;
  } else if (self.controller.accountService) {
    oauthHandler.accountService = self.controller.accountService;
  }
  [oauthHandler registerRoutesWithServer:server];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: OAuth routes registered");
}

- (void)registerXrpcRoutesWithServer:(HttpServer *)server {
  XrpcDispatcher *dispatcher = self.xrpcDispatcher;
  if (!dispatcher) {
    dispatcher = [[XrpcDispatcher alloc] init];
  }

  if (self.application) {
    [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher
                                          application:self.application];
  } else if (self.controller) {
    [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher
                                           controller:self.controller];
  } else {
    PDS_LOG_ERROR(@"No application provided to PDSHttpServerBuilder for XRPC "
                  @"registration");
  }

  __weak XrpcDispatcher *weakDispatcher = dispatcher;
  __weak SubscribeReposHandler *weakSubscribeReposHandler =
      self.subscribeReposHandler;

  // OPTIONS preflight for XRPC prefix
  [server addRoute:@"OPTIONS"
              path:@"/xrpc"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
             [response setHeader:@"POST, OPTIONS"
                          forKey:@"Access-Control-Allow-Methods"];
             [response setHeader:@"Content-Type, Authorization, DPoP"
                          forKey:@"Access-Control-Allow-Headers"];
             [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
             response.statusCode = HttpStatusOK;
           }];

  // Handler for /xrpc (prefix match for all XRPC methods)
  [server
      addHandlerForPath:@"/xrpc"
                handler:^(HttpRequest *request, HttpResponse *response) {
                  PDS_LOG_HTTP_INFO(
                      @"About to call dispatcher handleRequest for %@",
                      request.path);
                  [dispatcher handleRequest:request response:response];
                  PDS_LOG_HTTP_INFO(@"dispatcher handleRequest returned for %@",
                                    request.path);
                }];

  // OPTIONS preflight for XRPC methods
  [server addRoute:@"OPTIONS"
              path:@"/xrpc/:method"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
             [response setHeader:@"POST, OPTIONS"
                          forKey:@"Access-Control-Allow-Methods"];
             [response setHeader:@"Content-Type, Authorization, DPoP"
                          forKey:@"Access-Control-Allow-Headers"];
             [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
             response.statusCode = HttpStatusOK;
           }];

  // Handler for /xrpc/:method
  [server addRoute:@"*"
              path:@"/xrpc/:method"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [dispatcher handleRequest:request response:response];
           }];

  if (self.subscribeReposHandler) {
    // OPTIONS preflight for WebSocket upgrade
    [server addRoute:@"OPTIONS"
                path:@"/xrpc/com.atproto.sync.subscribeRepos"
             handler:^(HttpRequest *request, HttpResponse *response) {
               [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
               [response setHeader:@"GET, POST, OPTIONS"
                            forKey:@"Access-Control-Allow-Methods"];
               [response setHeader:@"Content-Type, Authorization, DPoP"
                            forKey:@"Access-Control-Allow-Headers"];
               [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
               response.statusCode = HttpStatusOK;
             }];

    [server addWebSocketRoute:@"/xrpc/com.atproto.sync.subscribeRepos"
                      handler:^(HttpRequest *request, HttpResponse *response,
                                id<PDSNetworkConnection> connection) {
                        SubscribeReposHandler *strongSubscribeReposHandler =
                            weakSubscribeReposHandler;
                        if (!strongSubscribeReposHandler) {
                          [connection cancel];
                          return;
                        }
                        [strongSubscribeReposHandler
                            acceptUpgradedConnection:connection
                                             request:request];
                      }];
  }

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: XRPC routes registered");
}

- (ExploreHandler *)registerExploreRoutesWithServer:(HttpServer *)server {
  PDSController *controller = self.controller;

  if (!controller) {
    PDS_LOG_WARN(@"PDSHttpServerBuilder: Explore routes not registered - "
                 @"missing controller");
    return nil;
  }

  ExploreHandler *exploreHandler = [ExploreHandler sharedHandler];
  [exploreHandler setController:controller];

  // API endpoint for PDS data
  [server addRoute:@"GET"
              path:@"/api/pds/:endpoint"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [exploreHandler handleRequest:request response:response];
           }];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: Explore routes registered");

  return exploreHandler;
}

- (void)registerOAuthDemoRoutesWithServer:(HttpServer *)server {
  PDSController *controller = self.controller;

  if (!self.dataDirectory && !controller) {
    PDS_LOG_WARN(@"PDSHttpServerBuilder: OAuth Demo routes not registered - "
                 @"missing dataDirectory and controller");
    return;
  }

  OAuthDemoHandler *oauthDemoHandler = [OAuthDemoHandler sharedHandler];

  // Prefer direct data directory injection, fall back to controller
  if (self.dataDirectory) {
    [oauthDemoHandler setDataDirectory:self.dataDirectory];
  } else {
    [oauthDemoHandler setController:controller];
  }

  [server
      addHandlerForPath:@"/oauth-demo"
                handler:^(HttpRequest *request, HttpResponse *response) {
                  [oauthDemoHandler handleRequest:request response:response];
                }];

  [server addRoute:@"GET"
              path:@"/oauth-demo/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [oauthDemoHandler handleRequest:request response:response];
           }];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: OAuth Demo routes registered");
}

- (void)registerMSTViewerRoutesWithServer:(HttpServer *)server {
  PDSController *controller = self.controller;

  if (!controller) {
    PDS_LOG_WARN(@"PDSHttpServerBuilder: MST Viewer routes not registered - "
                 @"missing controller");
    return;
  }

  MSTViewerHandler *mstViewerHandler = [MSTViewerHandler sharedHandler];
  [mstViewerHandler setController:controller];

  [server
      addHandlerForPath:@"/mst-viewer"
                handler:^(HttpRequest *request, HttpResponse *response) {
                  [mstViewerHandler handleRequest:request response:response];
                }];

  [server
      addHandlerForPath:@"/api/mst"
                handler:^(HttpRequest *request, HttpResponse *response) {
                  [mstViewerHandler handleRequest:request response:response];
                }];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: MST Viewer routes registered");
}

- (void)registerNodeInfoRoutesWithServer:(HttpServer *)server {
  NodeInfoHandler *nodeInfoHandler = [NodeInfoHandler sharedHandler];

  // Use configured issuer if provided by caller, then shared config
  // canonicalization.
  NSString *issuer = self.issuer;
  if (issuer.length == 0 && self.configuration) {
    issuer = [self.configuration canonicalIssuerWithPortHint:self.port];
  }
  if (issuer.length == 0) {
    issuer = [[PDSConfiguration sharedConfiguration]
        canonicalIssuerWithPortHint:self.port];
  }
  [nodeInfoHandler setIssuer:issuer];
  if (self.application.accountService) {
    [nodeInfoHandler setAccountService:self.application.accountService];
  } else if (self.controller.accountService) {
    [nodeInfoHandler setAccountService:self.controller.accountService];
  }
  [nodeInfoHandler setConfigured];
  [nodeInfoHandler registerRoutesWithServer:server];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: NodeInfo routes registered");
}

- (void)registerWellKnownRoutesWithServer:(HttpServer *)server {
  __weak PDSServiceDatabases *weakServiceDatabases = self.serviceDatabases;
  __weak PDSController *weakController = self.controller;
  __weak PDSConfiguration *weakConfiguration = self.configuration;

  NSString *_Nullable (^normalizedHostFromHostHeader)(NSString *_Nullable) =
      ^NSString *_Nullable(NSString *_Nullable hostHeader) {
    if (![hostHeader isKindOfClass:[NSString class]]) {
      return nil;
    }

    NSString *host = [hostHeader
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if (host.length == 0) {
      return nil;
    }

    // Remove any trailing dot(s).
    while ([host hasSuffix:@"."] && host.length > 1) {
      host = [host substringToIndex:host.length - 1];
    }

    // Strip port if present (e.g., "example.com:443" -> "example.com").
    // Keep IPv6 literal support ("[::1]:2583" -> "::1") even though handles are
    // domains.
    if ([host hasPrefix:@"["]) {
      NSRange closingBracket = [host rangeOfString:@"]"];
      if (closingBracket.location != NSNotFound &&
          closingBracket.location > 1) {
        host = [host
            substringWithRange:NSMakeRange(1, closingBracket.location - 1)];
      }
    } else {
      NSRange lastColon = [host rangeOfString:@":" options:NSBackwardsSearch];
      if (lastColon.location != NSNotFound) {
        // Only treat as host:port if there's a single colon.
        if ([host rangeOfString:@":"
                        options:0
                          range:NSMakeRange(0, lastColon.location)]
                .location == NSNotFound) {
          host = [host substringToIndex:lastColon.location];
        }
      }
    }

    host = [ATProtoHandleValidator normalizeHandle:host];
    return host.length > 0 ? host : nil;
  };

  BOOL (^hostMatchesAllowedDomains)(NSString *host,
                                    NSArray<NSString *> *allowedDomains) =
      ^BOOL(NSString *host, NSArray<NSString *> *allowedDomains) {
        if (allowedDomains.count == 0) {
          return YES;
        }

        for (NSString *domain in allowedDomains) {
          NSString *normalizedDomain =
              [normalizedHostFromHostHeader(domain) ?: @"" copy];
          if (normalizedDomain.length == 0) {
            continue;
          }
          if ([host isEqualToString:normalizedDomain]) {
            return YES;
          }
          NSString *suffix = [@"." stringByAppendingString:normalizedDomain];
          if ([host hasSuffix:suffix]) {
            return YES;
          }
        }
        return NO;
      };

  void (^handleWellKnownAtprotoDid)(HttpRequest *request,
                                    HttpResponse *response, BOOL includeBody) =
      ^(HttpRequest *request, HttpResponse *response, BOOL includeBody) {
        // Per ATProto spec: The handle is determined by the Host header in the
        // HTTP request.
        NSString *hostHeader = [request headerForKey:@"Host"];
        NSString *handle = normalizedHostFromHostHeader(hostHeader);
        PDS_LOG_INFO(@"Well-known: Resolving handle [%@] from Host header [%@]",
                     handle ?: @"nil", hostHeader ?: @"nil");

        if (handle.length == 0) {
          response.statusCode = HttpStatusBadRequest;
          response.contentType = @"text/plain; charset=utf-8";
          if (includeBody) {
            [response setBodyString:@"missing host header\n"];
          }
          return;
        }

        // Optionally scope to configured available user domains.
        PDSConfiguration *config = weakConfiguration;
        NSArray<NSString *> *allowedDomains =
            config.availableUserDomains ?: @[];
        if (!hostMatchesAllowedDomains(handle, allowedDomains)) {
          response.statusCode = HttpStatusNotFound;
          response.contentType = @"text/plain; charset=utf-8";
          if (includeBody) {
            [response setBodyString:@"not found\n"];
          }
          return;
        }

        // Look up the DID for this handle in the database.
        PDSServiceDatabases *strongServiceDatabases = weakServiceDatabases;
        if (!strongServiceDatabases) {
          PDSController *strongController = weakController;
          strongServiceDatabases = strongController.serviceDatabases;
        }

        if (!strongServiceDatabases) {
          response.statusCode = HttpStatusInternalServerError;
          response.contentType = @"text/plain; charset=utf-8";
          if (includeBody) {
            [response setBodyString:@"internal error\n"];
          }
          return;
        }

        NSError *dbError = nil;
        PDSDatabaseAccount *account =
            [strongServiceDatabases getAccountByHandle:handle error:&dbError];
        if (dbError) {
          PDS_LOG_ERROR(@"Database error looking up handle %@: %@", handle,
                        dbError.localizedDescription ?: @"unknown error");
          response.statusCode = HttpStatusInternalServerError;
          response.contentType = @"text/plain; charset=utf-8";
          if (includeBody) {
            [response setBodyString:@"internal error\n"];
          }
          return;
        }

        if (!account || account.did.length == 0) {
          response.statusCode = HttpStatusNotFound;
          response.contentType = @"text/plain; charset=utf-8";
          if (includeBody) {
            [response setBodyString:@"not found\n"];
          }
          return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = @"text/plain; charset=utf-8";
        [response setHeader:@"Host" forKey:@"Vary"];
        [response setHeader:@"max-age=300" forKey:@"Cache-Control"];
        if (includeBody) {
          [response setBodyString:[account.did stringByAppendingString:@"\n"]];
        }
      };

  [server addRoute:@"GET"
              path:@"/.well-known/atproto-did"
           handler:^(HttpRequest *request, HttpResponse *response) {
             handleWellKnownAtprotoDid(request, response, YES);
           }];

  [server addRoute:@"HEAD"
              path:@"/.well-known/atproto-did"
           handler:^(HttpRequest *request, HttpResponse *response) {
             handleWellKnownAtprotoDid(request, response, NO);
           }];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: .well-known routes registered");
}

- (void)registerAdminRoutesWithServer:(HttpServer *)server {
  PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];

  NSArray *adminPaths = @[
    @"/admin", @"/admin/login", @"/admin/logout", @"/admin/users",
    @"/admin/invites", @"/admin/invites/disable", @"/admin/blobs",
    @"/admin/metrics", @"/admin/health", @"/admin/stats", @"/admin/audit-log"
  ];

  for (NSString *path in adminPaths) {
    [server addRoute:@"GET"
                path:path
             handler:^(HttpRequest *request, HttpResponse *response) {
               NSString *result =
                   [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                    path:path
                                                 headers:request.headers
                                                    body:request.body];
               if (result) {
                 response.statusCode = 200;
                 [response setBodyString:result];
               } else {
                 response.statusCode = 404;
                 [response setJsonBody:@{@"error" : @"Not Found"}];
               }
             }];

    [server addRoute:@"POST"
                path:path
             handler:^(HttpRequest *request, HttpResponse *response) {
               NSString *result =
                   [adminHandler handleRequestWithMethod:PDSHTTPMethodPOST
                                                    path:path
                                                 headers:request.headers
                                                    body:request.body];
               if (result) {
                 response.statusCode = 200;
                 [response setBodyString:result];
               } else {
                 response.statusCode = 404;
                 [response setJsonBody:@{@"error" : @"Not Found"}];
               }
             }];
  }

  [self registerAdminUIRoutesWithServer:server];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: Admin routes registered");
}

- (void)registerAdminUIRoutesWithServer:(HttpServer *)server {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *assetsPath = nil;

  // Try multiple locations for AdminUI/Assets
  NSArray *candidates = @[
    [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"AdminUI/Assets"],
    [[NSBundle bundleForClass:[self class]].resourcePath
        stringByAppendingPathComponent:@"AdminUI/Assets"],
    [[fm currentDirectoryPath] stringByAppendingPathComponent:
                                   @"ATProtoPDS/Sources/App/AdminUI/Assets"],
    @"/Users/jack/Software/objpds/ATProtoPDS/Sources/App/AdminUI/Assets"
  ];

  for (NSString *candidate in candidates) {
    if ([fm fileExistsAtPath:candidate]) {
      assetsPath = candidate;
      break;
    }
  }

  if (!assetsPath) {
    PDS_LOG_WARN(@"PDSHttpServerBuilder: Admin UI assets not found in any "
                 @"candidate path");
    return;
  }
  PDS_LOG_INFO(@"PDSHttpServerBuilder: Admin UI assets found at %@",
               assetsPath);

  [server addRoute:@"GET"
              path:@"/admin-ui/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
             NSString *filePath = [request.path
                 stringByReplacingOccurrencesOfString:@"/admin-ui/"
                                           withString:@""];
             if ([filePath containsString:@".."]) {
               response.statusCode = 403;
               [response setJsonBody:@{@"error" : @"Forbidden"}];
               return;
             }

             NSString *fullPath =
                 [assetsPath stringByAppendingPathComponent:filePath];
             NSData *data = [NSData dataWithContentsOfFile:fullPath];
             if (data) {
               response.statusCode = 200;
               if ([filePath hasSuffix:@".js"]) {
                 [response setHeader:@"application/javascript"
                              forKey:@"Content-Type"];
               } else if ([filePath hasSuffix:@".css"]) {
                 [response setHeader:@"text/css" forKey:@"Content-Type"];
               } else if ([filePath hasSuffix:@".html"]) {
                 [response setHeader:@"text/html" forKey:@"Content-Type"];
               }
               [response setBodyData:data];
             } else {
               response.statusCode = 404;
               [response setJsonBody:@{@"error" : @"Not Found"}];
             }
           }];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: Admin UI routes registered");
}

@end
