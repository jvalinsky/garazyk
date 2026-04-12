/*!
 @file PDSHttpServerBuilder.m

 @abstract Implementation of HTTP server builder.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSHttpServerBuilder.h"
#import "App/CappuccinoUI/CappuccinoUIHandler.h"
#import "App/Explore/ExploreHandler.h"
#import "App/MSTViewer/MSTViewerHandler.h"
#import "App/NodeInfo/NodeInfoHandler.h"
#import "App/OAuthDemo/OAuthDemoHandler.h"
#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2Handler.h"
#import "Auth/WebAuthnRegistrationHandler.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Metrics/PDSMetrics.h"
#import "Network/PDSHttpAdminRoutePack.h"
#import "Network/PDSHttpWellKnownRoutePack.h"
#import "Network/PDSHttpXrpcRoutePack.h"
#import "Sync/RelayAPIHandler.h"
#import "Sync/SubscribeReposHandler.h"
#import "HttpRequest.h"
#import "HttpResponse.h"
#import "HttpServer.h"
#import "PDSNetworkTransport.h"
#import "XrpcHandler.h"

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
    _enableCappuccinoUIDefault = YES;
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

  // Register Objective-J/Cappuccino UI routes
  [self registerCappuccinoUIRoutesWithServer:server];

  // Register MST Viewer routes
  if (self.enableMSTViewer) {
    [self registerMSTViewerRoutesWithServer:server];
  }

  // Register NodeInfo routes
  if (self.enableNodeInfo) {
    [self registerNodeInfoRoutesWithServer:server];
  }

  // Register Relay API routes
  [self registerRelayAPIRoutesWithServer:server];

  // Register .well-known routes (handle resolution)
  [self registerWellKnownRoutesWithServer:server];

  // Register Metrics endpoint (unauthenticated for Prometheus scraping)
  [self registerMetricsEndpointWithServer:server];

  // Register Admin routes
  [self registerAdminRoutesWithServer:server];

  // Register wildcard route LAST (must be after all specific routes)
  if (self.enableCappuccinoUIDefault) {
    // Cutover: Objective-J UI is the default entrypoint.
    CappuccinoUIHandler *defaultUIHandler = [CappuccinoUIHandler sharedHandler];
    [server addRoute:@"GET"
                path:@"/*"
             handler:^(HttpRequest *request, HttpResponse *response) {
               [defaultUIHandler handleRequest:request response:response];
             }];
  } else if (self.enableExploreUI && exploreHandler) {
    // Legacy fallback: keep ExploreHandler as the default.
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

  PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
  WebAuthnRegistrationHandler *webauthnHandler = [[WebAuthnRegistrationHandler alloc] initWithDatabase:db serverOrigin:config.issuer];
  [webauthnHandler registerRoutesWithServer:server];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: WebAuthn routes registered");
}

- (void)setCorsHeaders:(HttpResponse *)response forRequest:(HttpRequest *)request {
  NSArray<NSString *> *allowedOrigins = [self getCorsAllowedOrigins];
  NSString *origin = [request headerForKey:@"Origin"];

  if (origin && [allowedOrigins containsObject:@"*"]) {
    [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
  } else if (origin && [allowedOrigins containsObject:origin]) {
    [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
  } else if (!origin && [allowedOrigins containsObject:@"*"]) {
    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
  }

  [response setHeader:[self getCorsAllowedMethods]
               forKey:@"Access-Control-Allow-Methods"];
  [response setHeader:[self getCorsAllowedHeaders]
               forKey:@"Access-Control-Allow-Headers"];
  [response setHeader:[self getCorsMaxAge] forKey:@"Access-Control-Max-Age"];
  [response setHeader:@"Origin" forKey:@"Vary"];
}

- (void)registerXrpcRoutesWithServer:(HttpServer *)server {
  [PDSHttpXrpcRoutePack registerRoutesWithServer:server
                                      dispatcher:self.xrpcDispatcher
                                     application:self.application
                                      controller:self.controller
                           subscribeReposHandler:self.subscribeReposHandler
                                  setCorsHeaders:^(
                                      HttpResponse *response,
                                      HttpRequest *request) {
                                    [self setCorsHeaders:response
                                              forRequest:request];
                                  }];
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

  [server addRoute:@"POST"
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

- (void)registerCappuccinoUIRoutesWithServer:(HttpServer *)server {
  CappuccinoUIHandler *cappuccinoUIHandler = [CappuccinoUIHandler sharedHandler];

  // Prefer direct data directory injection, fall back to controller wiring.
  if (self.dataDirectory.length > 0) {
    [cappuccinoUIHandler setDataDirectory:self.dataDirectory];
  } else if (self.controller) {
    [cappuccinoUIHandler setController:self.controller];
  }

  [server addRoute:@"GET"
              path:@"/ui"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [cappuccinoUIHandler handleRequest:request response:response];
           }];

  [server addRoute:@"GET"
              path:@"/ui/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [cappuccinoUIHandler handleRequest:request response:response];
           }];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: Cappuccino UI routes registered");
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

- (void)registerRelayAPIRoutesWithServer:(HttpServer *)server {
  RelayAPIHandler *relayAPIHandler = [RelayAPIHandler sharedHandler];

  // Relay metrics endpoint
  [server addRoute:@"GET"
              path:@"/api/relay/metrics"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [relayAPIHandler handleRequest:request response:response];
           }];

  // Relay upstreams endpoint
  [server addRoute:@"GET"
              path:@"/api/relay/upstreams"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [relayAPIHandler handleRequest:request response:response];
           }];

  // Relay health endpoint
  [server addRoute:@"GET"
              path:@"/api/relay/health"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [relayAPIHandler handleRequest:request response:response];
           }];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: Relay API routes registered");
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
  [PDSHttpWellKnownRoutePack registerRoutesWithServer:server
                                      serviceDatabases:self.serviceDatabases
                                            controller:self.controller
                                         configuration:self.configuration
                                        setCorsHeaders:^(
                                            HttpResponse *response,
                                            HttpRequest *request) {
                                          [self setCorsHeaders:response
                                                    forRequest:request];
                                        }];
}

- (void)registerMetricsEndpointWithServer:(HttpServer *)server {
  [server addRoute:@"GET"
              path:@"/metrics"
           handler:^(HttpRequest *request, HttpResponse *response) {
             response.statusCode = HttpStatusOK;
             [response setHeader:@"text/plain; version=0.0.4; charset=utf-8"
                          forKey:@"Content-Type"];
             [response setBodyString:[[PDSMetrics sharedMetrics] exportPrometheus]];
           }];

  PDS_LOG_DEBUG(@"PDSHttpServerBuilder: Metrics endpoint registered");
}

- (void)registerAdminRoutesWithServer:(HttpServer *)server {
  [PDSHttpAdminRoutePack registerAdminRoutesWithServer:server];
}

- (void)registerAdminUIRoutesWithServer:(HttpServer *)server {
  [PDSHttpAdminRoutePack registerAdminUIRoutesWithServer:server];
}

@end
