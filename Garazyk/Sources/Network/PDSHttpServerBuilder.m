/*!
 @file PDSHttpServerBuilder.m

 @abstract Implementation of HTTP server builder.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSHttpServerBuilder.h"
#import "App/Explore/ExploreHandler.h"
#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Network/PDSHttpAdminRoutePack.h"
#import "Network/PDSHttpExploreRoutePack.h"
#import "Network/PDSHttpMetricsRoutePack.h"
#import "Network/PDSHttpMSTViewerRoutePack.h"
#import "Network/PDSHttpNodeInfoRoutePack.h"
#import "Network/PDSHttpOAuthDemoRoutePack.h"
#import "Network/PDSHttpOAuthRoutePack.h"
#import "Network/PDSHttpRelayAPIRoutePack.h"
#import "Network/PDSHttpWellKnownRoutePack.h"
#import "Network/PDSHttpXrpcRoutePack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import <Foundation/Foundation.h>

static NSString *PDSDesignSystemRootPath(void) {
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *bundlePath =
      [[NSBundle mainBundle] pathForResource:@"Shared/DesignSystem" ofType:@""];
  if (bundlePath.length > 0 && [fm fileExistsAtPath:bundlePath]) {
    return bundlePath;
  }

  NSString *cwd = [fm currentDirectoryPath];
  NSArray<NSString *> *candidates = @[
    [cwd stringByAppendingPathComponent:@"Garazyk/Sources/Shared/DesignSystem"],
    [cwd stringByAppendingPathComponent:@"Sources/Shared/DesignSystem"],
    [[cwd stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"Garazyk/Sources/Shared/DesignSystem"],
    [[[cwd stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"Garazyk/Sources/Shared/DesignSystem"]
  ];

  for (NSString *candidate in candidates) {
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:candidate isDirectory:&isDir] && isDir) {
      return candidate;
    }
  }

  return nil;
}

static NSString *PDSContentTypeForAssetPath(NSString *path) {
  NSString *ext = path.pathExtension.lowercaseString;
  if ([ext isEqualToString:@"html"])
    return @"text/html; charset=utf-8";
  if ([ext isEqualToString:@"css"])
    return @"text/css; charset=utf-8";
  if ([ext isEqualToString:@"js"])
    return @"application/javascript; charset=utf-8";
  if ([ext isEqualToString:@"json"])
    return @"application/json; charset=utf-8";
  if ([ext isEqualToString:@"svg"])
    return @"image/svg+xml";
  if ([ext isEqualToString:@"woff2"])
    return @"font/woff2";
  if ([ext isEqualToString:@"woff"])
    return @"font/woff";
  return @"application/octet-stream";
}

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
    // Keep legacy feature toggles enabled by default for compatibility tests.
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

  // Registration order is intentionally fixed:
  // auth -> xrpc -> ui/api packs -> well-known -> metrics -> admin -> wildcard
  if (self.enableOAuth) {
    [PDSHttpOAuthRoutePack registerRoutesWithServer:server
                                   serviceDatabases:self.serviceDatabases
                                          jwtMinter:self.jwtMinter
                                      dataDirectory:self.dataDirectory
                                        application:self.application
                                         controller:self.controller];
  }

  if (self.enableXrpc) {
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

  ExploreHandler *exploreHandler = nil;
  if (self.enableExploreUI) {
    exploreHandler =
        [PDSHttpExploreRoutePack registerRoutesWithServer:server
                                               controller:self.controller];
  }

  if (self.enableOAuthDemo) {
    [PDSHttpOAuthDemoRoutePack registerRoutesWithServer:server
                                          dataDirectory:self.dataDirectory
                                             controller:self.controller];
  }

  // Register Admin UI routes (new HTML5/HTMX admin interface)
  // Admin routes are registered in PDSHttpAdminRoutePack

  if (self.enableMSTViewer) {
    [PDSHttpMSTViewerRoutePack registerRoutesWithServer:server
                                             controller:self.controller];
  }

  if (self.enableNodeInfo) {
    [PDSHttpNodeInfoRoutePack registerRoutesWithServer:server
                                                issuer:self.issuer
                                                  port:self.port
                                         configuration:self.configuration
                                           application:self.application
                                            controller:self.controller];
  }

  [PDSHttpRelayAPIRoutePack registerRoutesWithServer:server];

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

  [PDSHttpMetricsRoutePack registerRoutesWithServer:server];
  [PDSHttpAdminRoutePack registerAdminRoutesWithServer:server];

  void (^serveDesignSystemAsset)(NSString *, HttpResponse *) =
      ^(NSString *relativePath, HttpResponse *response) {
        if (relativePath.length == 0 || [relativePath hasPrefix:@"/"] ||
            [relativePath containsString:@".."]) {
          response.statusCode = HttpStatusNotFound;
          [response setJsonBody:@{@"error" : @"Invalid design-system path"}];
          return;
        }

        NSString *rootPath = PDSDesignSystemRootPath();
        if (!rootPath) {
          response.statusCode = HttpStatusNotFound;
          [response setJsonBody:@{
            @"error" : @"Design system assets not found"
          }];
          return;
        }

        NSString *fullPath =
            [[rootPath stringByAppendingPathComponent:relativePath]
                stringByStandardizingPath];
        NSString *basePath = [rootPath stringByStandardizingPath];
        if (![fullPath hasPrefix:[basePath stringByAppendingString:@"/"]] &&
            ![fullPath isEqualToString:basePath]) {
          response.statusCode = HttpStatusNotFound;
          [response setJsonBody:@{@"error" : @"Invalid asset path"}];
          return;
        }

        NSData *data = [NSData dataWithContentsOfFile:fullPath];
        if (!data) {
          response.statusCode = HttpStatusNotFound;
          [response setJsonBody:@{
            @"error" : @"Design system asset not found",
            @"path" : relativePath ?: @""
          }];
          return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = PDSContentTypeForAssetPath(relativePath);
        [response setBodyData:data];
      };

  [server addRoute:@"GET"
              path:@"/design-system"
           handler:^(HttpRequest *request, HttpResponse *response) {
             serveDesignSystemAsset(@"index.html", response);
           }];

  [server addRoute:@"GET"
              path:@"/design-system/"
           handler:^(HttpRequest *request, HttpResponse *response) {
             serveDesignSystemAsset(@"index.html", response);
           }];

  [server addRoute:@"GET"
              path:@"/design-system/css/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
             NSString *prefix = @"/design-system/";
             NSString *relativePath = [request.path hasPrefix:prefix]
                                          ? [request.path substringFromIndex:prefix.length]
                                          : @"";
             serveDesignSystemAsset(relativePath, response);
           }];

  // Suppress browser console noise for favicon probes when no icon asset is
  // shipped with the current runtime bundle.
  [server addRoute:@"GET"
              path:@"/favicon.ico"
           handler:^(HttpRequest *request, HttpResponse *response) {
             response.statusCode = HttpStatusNoContent;
             response.contentType = @"image/x-icon";
             [response setBodyData:[NSData data]];
           }];

  // Register default route LAST (must be after all specific routes)
  // Admin UI is served at /admin/ - default route falls through to Explore
  if (self.enableExploreUI && exploreHandler) {
    [server addRoute:@"GET"
                path:@"/*"
             handler:^(HttpRequest *request, HttpResponse *response) {
               [exploreHandler handleRequest:request response:response];
             }];
  }

  return YES;
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

@end
