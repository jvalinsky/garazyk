// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHttpServerBuilder.m

 @abstract Builds and wires HTTP server runtime components and route packs.

 @discussion Constructs the HTTP server instance, installs route packs, and applies runtime configuration for transport and routing layers before request serving begins.
 */

#import "ATProtoHttpServerBuilder.h"
#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "App/PDSController.h"
#import "Network/ATProtoHttpMetricsRoutePack.h"
#import "Network/ATProtoHttpMSTViewerRoutePack.h"
#import "Network/ATProtoHttpNodeInfoRoutePack.h"
#import "Network/ATProtoHttpOAuthRoutePack.h"
#import "Network/PDSHttpPDSAdminRoutePack.h"
#import "Network/ATProtoHttpRelayAPIRoutePack.h"
#import "Network/ATProtoHttpWellKnownRoutePack.h"
#import "Network/ATProtoHttpXrpcRoutePack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import <Foundation/Foundation.h>

@interface ATProtoHttpServerBuilder ()
@property(nonatomic, strong, nullable) ATProtoServiceConfiguration *configuration;
@end

@implementation ATProtoHttpServerBuilder

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

- (instancetype)initWithConfiguration:(ATProtoServiceConfiguration *)configuration {
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
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  NSArray<NSString *> *defaultOrigins = @[ @"*" ];
  NSString *originsStr = [config stringForKey:@"cors.allowed_origins"];
  NSArray<NSString *> *origins = originsStr ? [originsStr componentsSeparatedByString:@","] : nil;
  return origins ?: defaultOrigins;
}

- (NSString *)getCorsAllowedMethods {
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  NSString *defaultMethods = @"GET, POST, PUT, DELETE, OPTIONS, HEAD";
  NSString *methods = [config stringForKey:@"cors.allowed_methods"];
  return methods ?: defaultMethods;
}

- (NSString *)getCorsAllowedHeaders {
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  NSString *defaultHeaders = @"DPoP, Authorization, Content-Type, *";
  NSString *headers = [config stringForKey:@"cors.allowed_headers"];
  return headers ?: defaultHeaders;
}

- (NSString *)getCorsMaxAge {
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
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
          [NSError errorWithDomain:@"ATProtoHttpServerBuilderErrorDomain"
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
    [ATProtoHttpOAuthRoutePack registerRoutesWithServer:server
                                   serviceDatabases:self.serviceDatabases
                                          jwtMinter:self.jwtMinter
                                      dataDirectory:self.dataDirectory
                                        application:self.application
                                         controller:self.controller];
  }

  [PDSHttpPDSAdminRoutePack registerRoutesWithServer:server
                                    serviceDatabases:self.serviceDatabases];

  if (self.enableXrpc) {
    [ATProtoHttpXrpcRoutePack registerRoutesWithServer:server
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
    [ATProtoHttpNodeInfoRoutePack registerRoutesWithServer:server
                                                issuer:self.issuer
                                                  port:self.port
                                         configuration:self.configuration
                                           application:self.application
                                            controller:self.controller];
  }

  [ATProtoHttpRelayAPIRoutePack registerRoutesWithServer:server];

  [ATProtoHttpWellKnownRoutePack registerRoutesWithServer:server
                                      serviceDatabases:self.serviceDatabases
                                            controller:self.controller
                                         configuration:self.configuration
                                        setCorsHeaders:^(
                                            HttpResponse *response,
                                            HttpRequest *request) {
                                          [self setCorsHeaders:response
                                                    forRequest:request];
                                        }];

  [ATProtoHttpMetricsRoutePack registerRoutesWithServer:server];

  if (self.enableMSTViewer) {
    [ATProtoHttpMSTViewerRoutePack registerRoutesWithServer:server
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
  NSString *origin = [request headerForKey: @"Origin"];
  if (origin && ([allowedOrigins containsObject: @"*"] || [origin hasPrefix: @"http://127.0.0.1"] || [origin hasPrefix: @"http://localhost"])) {
    [response setHeader:origin forKey: @"Access-Control-Allow-Origin"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Credentials"];
  } else if (origin && [allowedOrigins containsObject:origin]) {
    [response setHeader:origin forKey: @"Access-Control-Allow-Origin"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Credentials"];
  } else if (!origin && [allowedOrigins containsObject: @"*"]) {
    [response setHeader: @"*" forKey: @"Access-Control-Allow-Origin"];
  }

  [response setHeader:[self getCorsAllowedMethods]
               forKey:@"Access-Control-Allow-Methods"];
  [response setHeader:[self getCorsAllowedHeaders]
               forKey:@"Access-Control-Allow-Headers"];
  [response setHeader:[self getCorsMaxAge] forKey:@"Access-Control-Max-Age"];
  [response setHeader:@"DPoP-Nonce, WWW-Authenticate"
               forKey:@"Access-Control-Expose-Headers"];
  [response setHeader:@"Origin" forKey:@"Vary"];
}

@end
