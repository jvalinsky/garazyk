/*!
 @file PDSHttpServerBuilder.m

 @abstract Builds and wires HTTP server runtime components and route packs.

 @discussion Constructs the HTTP server instance, installs route packs, and applies runtime configuration for transport and routing layers before request serving begins.
 */

#import "PDSHttpServerBuilder.h"
#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Network/PDSHttpMetricsRoutePack.h"
#import "Network/PDSHttpMSTViewerRoutePack.h"
#import "Network/PDSHttpNodeInfoRoutePack.h"
#import "Network/PDSHttpOAuthRoutePack.h"
#import "Network/PDSHttpPDSAdminRoutePack.h"
#import "Network/PDSHttpRelayAPIRoutePack.h"
#import "Network/PDSHttpWellKnownRoutePack.h"
#import "Network/PDSHttpXrpcRoutePack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import <Foundation/Foundation.h>

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
  // auth -> xrpc -> optional packs -> well-known -> relay API -> metrics
  if (self.enableOAuth) {
    [PDSHttpOAuthRoutePack registerRoutesWithServer:server
                                   serviceDatabases:self.serviceDatabases
                                          jwtMinter:self.jwtMinter
                                      dataDirectory:self.dataDirectory
                                        application:self.application
                                         controller:self.controller];
  }

  [PDSHttpPDSAdminRoutePack registerRoutesWithServer:server
                                    serviceDatabases:self.serviceDatabases];

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

  if (self.enableMSTViewer) {
    [PDSHttpMSTViewerRoutePack registerRoutesWithServer:server
                                             controller:self.controller];
  }

  [server addRoute:@"GET"
              path:@"/"
           handler:^(HttpRequest *request, HttpResponse *response) {
             response.statusCode = HttpStatusOK;
             response.contentType = @"text/plain; charset=utf-8";
[response setBodyString:@",--.                                                                     \n   ,--/  /|                                       ,--,                     ,-.  \n',---,': / '                                     ,--.'|                 ,--/ /|  \n:   : '/ /                                ,----,|  | :               ,--. :/ |  \n|   '   ,                .--.--.        .'   .`|:  : '               :  : ' /   \n'   |  /     ,--.--.    /  /    '    .'   .'  .'|  ' |     ,--.--.   |  '  /    \n|   ;  ;    /       \\  |  :  /`./  ,---, '   ./ '  | |    /       \\  '  |  :    \n:   '   \\  .--.  .-. | |  :  ;_    ;   | .'  /  |  | :   .--.  .-. | |  |   \\   \n|   |    '  \\__\\/: . .  \\  \\    `. `---' /  ;--,'  : |__  \\__\\/: . . '  : |. \\  \n'   : |.  \\ ,\" .--.; |   \\`----.   \\  /  /  / .`||  | '.'| ,\" .--.; | |  | ' \\ \\ \n|   | '_\\.'/  /  ,.  |  /  /\\`--'  /./__;     .' ;  :    ;/  /  ,.  | '  : |--'  \n'   : |   ;  :   .'   \\'--'.     / ;   |  .'    |  ,   /;  :   .'   \\;  |,'     \n;   |,'   |  ,     .-./  \\`--'---'  \\`---'         ---\\`-' |  ,     .-./'--'       \n'---'      \\`--\\`---'                                      \\`--\\`---' \n"];
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
