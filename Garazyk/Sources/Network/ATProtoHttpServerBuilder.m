// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHttpServerBuilder.m

 @abstract Builds and wires HTTP server runtime components and route packs.

 @discussion Constructs the HTTP server instance, installs route packs, and applies runtime configuration for transport and routing layers before request serving begins.
 */

#import "ATProtoHttpServerBuilder.h"
#import "App/PDSApplication.h"
#import "Services/PDS/PDSAccountService.h"
#import "Database/PDSDatabaseAccount.h"
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
  NSArray<NSString *> *origins = [config arrayForKey:@"cors.allowed_origins"];
  return origins ?: defaultOrigins;
}

- (NSString *)getCorsAllowedMethods {
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  NSString *defaultMethods = @"GET, POST, PUT, DELETE, OPTIONS, HEAD";
  NSArray<NSString *> *methods = [config arrayForKey:@"cors.allowed_methods"];
  if (methods) {
    return [methods componentsJoinedByString:@", "];
  }
  return defaultMethods;
}

- (NSString *)getCorsAllowedHeaders {
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  NSString *defaultHeaders = @"DPoP, Authorization, Content-Type, *";
  NSArray<NSString *> *headers = [config arrayForKey:@"cors.allowed_headers"];
  if (headers) {
    return [headers componentsJoinedByString:@", "];
  }
  return defaultHeaders;
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

  PDSApplication *app = self.application;
  id<PDSAccountService> capturedAccountService = app.accountService ?: self.controller.accountService;
  NSString *issuer = self.issuer ?: @"pds.garazyk.xyz";
  [server addRoute:@"GET"
              path:@"/"
           handler:^(HttpRequest *request, HttpResponse *response) {
             response.statusCode = HttpStatusOK;
             response.contentType = @"text/html; charset=utf-8";
             
             NSError *readErr = nil;
             NSString *html = [NSString stringWithContentsOfFile:@"index.html" encoding:NSUTF8StringEncoding error:&readErr];
             if (!html) {
                 [response setBodyString:[NSString stringWithFormat:@"Failed to read index.html: %@", readErr]];
                 return;
             }
             
             NSArray *accounts = [capturedAccountService getAllAccountsWithError:nil] ?: @[];
             NSUInteger count = accounts.count;
             
             NSTimeInterval uptime = [[NSProcessInfo processInfo] systemUptime];
             int hours = (int)(uptime / 3600);
             int mins = (int)((uptime - hours * 3600) / 60);
             NSString *uptimeStr = [NSString stringWithFormat:@"%dh %dm", hours, mins];
             
             unsigned long long physicalMem = [[NSProcessInfo processInfo] physicalMemory];
             NSString *memTotal = [NSString stringWithFormat:@"%llu MB", physicalMem / 1024 / 1024];
             
             html = [html stringByReplacingOccurrencesOfString:@"{{server_hostname}}" withString:issuer];
             html = [html stringByReplacingOccurrencesOfString:@"{{server_uptime}}" withString:uptimeStr];
             html = [html stringByReplacingOccurrencesOfString:@"{{memory_total}}" withString:memTotal];
             html = [html stringByReplacingOccurrencesOfString:@"{{memory_used}}" withString:@"N/A"];
             html = [html stringByReplacingOccurrencesOfString:@"{{memory_free}}" withString:@"N/A"];
             html = [html stringByReplacingOccurrencesOfString:@"{{account_count}}" withString:[@(count) stringValue]];
             
             NSMutableString *accountsHtml = [NSMutableString string];
             for (PDSDatabaseAccount *acc in accounts) {
                 NSString *handle = acc.handle ?: @"Unknown";
                 NSString *did = acc.did ?: @"Unknown";
                 NSString *createdAtStr = @"N/A";
                 
                 NSTimeInterval createdAt = acc.createdAt;
                 if (createdAt > 0) {
                     NSDate *date = [NSDate dateWithTimeIntervalSince1970:createdAt];
                     NSDateFormatter *df = [[NSDateFormatter alloc] init];
                     df.dateStyle = NSDateFormatterMediumStyle;
                     df.timeStyle = NSDateFormatterShortStyle;
                     createdAtStr = [df stringFromDate:date];
                 }
                 
                 [accountsHtml appendFormat:@"<li><details open><summary><strong>%@</strong></summary><ul><li>DID: %@</li><li>Created: %@</li><li>Status: Active</li></ul></details></li>",
                     handle, did, createdAtStr];
             }
             
             NSRange startRange = [html rangeOfString:@"<!-- {{#each accounts}} -->"];
             NSRange endRange = [html rangeOfString:@"<!-- {{/each}} -->"];
             if (startRange.location != NSNotFound && endRange.location != NSNotFound) {
                 NSRange replaceRange = NSMakeRange(startRange.location, endRange.location + endRange.length - startRange.location);
                 html = [html stringByReplacingCharactersInRange:replaceRange withString:accountsHtml];
             }
             
             [response setBodyString:html];
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
