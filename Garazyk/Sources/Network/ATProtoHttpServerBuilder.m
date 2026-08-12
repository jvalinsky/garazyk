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

static NSString *ATProtoHttpServerBuilderEscapeHTML(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || value.length == 0) {
    return @"";
  }
  NSString *escaped = [value stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
  return escaped;
}

static NSString *ATProtoHttpServerBuilderPublicAdminURL(void) {
  const char *raw = getenv("PDS_ADMIN_UI_PUBLIC_URL");
  if (raw == NULL || raw[0] == '\0') {
    raw = getenv("PDS_UI_SERVER_URL");
  }
  if (raw != NULL && raw[0] != '\0') {
    return ATProtoHttpServerBuilderEscapeHTML([NSString stringWithUTF8String:raw]);
  }
  return @"/admin";
}

static NSString *ATProtoHttpServerBuilderPublicLandingFallbackHTML(void) {
  return @"<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">"
         @"<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
         @"<title>{{server_hostname}} — Garazyk PDS</title>"
         @"<style>"
         @":root{--bg:oklch(96% .003 200);--panel:oklch(99% .003 200);--text:oklch(13% .005 200);"
         @"--muted:oklch(45% .005 200);--accent:oklch(52% .18 255);--strawberry:oklch(65% .22 25);"
         @"--border:oklch(85% .003 200);--font:-apple-system,BlinkMacSystemFont,\"Segoe UI\",sans-serif}"
         @"body{margin:0;font-family:var(--font);color:var(--text);background:radial-gradient(ellipse 80% 50% at 50% 0%,"
         @"color-mix(in srgb,var(--strawberry) 8%,transparent),transparent 70%),var(--bg);min-height:100vh}"
         @"main{max-width:40rem;margin:2rem auto;padding:2rem;background:var(--panel);border:1px solid var(--border);"
         @"border-radius:8px;box-shadow:0 2px 8px oklch(0% 0 0/.12)}"
         @".kicker{margin:0 0 .25rem;color:var(--strawberry);font-size:11px;font-weight:600;letter-spacing:.02em;"
         @"text-transform:uppercase}"
         @"h1{margin:0 0 .5rem;font-size:24px}p.sub{margin:0 0 1.5rem;color:var(--muted);font-size:12px}"
         @".btn{display:inline-flex;align-items:center;padding:8px 12px;border-radius:6px;font-size:12px;"
         @"font-weight:500;text-decoration:none;min-height:28px}"
         @".btn-primary{background:var(--accent);color:#fff}.btn-secondary{background:oklch(93% .005 200);"
         @"color:var(--text);border:1px solid var(--border);margin-left:.5rem}"
         @"ul{padding-left:1.2rem;color:var(--muted)}.mono{font-family:ui-monospace,monospace;font-size:11px;"
         @"word-break:break-all}"
         @"</style></head><body><main>"
         @"<p class=\"kicker\">Garazyk PDS</p>"
         @"<h1>{{server_hostname}}</h1>"
         @"<p class=\"sub\">Public Personal Data Server status — no sign-in required.</p>"
         @"<p><strong>Status:</strong> Online · <strong>Uptime:</strong> {{server_uptime}} · "
         @"<strong>Accounts:</strong> {{account_count}}</p>"
         @"<p><a class=\"btn btn-primary\" href=\"{{admin_ui_url}}\">Sign in to admin panel</a>"
         @"<a class=\"btn btn-secondary\" href=\"/xrpc/_health\">Health</a></p>"
         @"<h2>Accounts</h2><ul><!-- {{#each accounts}} --><!-- {{/each}} --></ul>"
         @"</main></body></html>";
}

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
      _enableMSTViewer = configuration.mstViewerEnabled;
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

- (nullable ATProtoHttpServer *)buildWithError:(NSError **)error {
  ATProtoHttpServer *server = [ATProtoHttpServer serverWithPort:self.port];

  if (![self configureServer:server error:error]) {
    return nil;
  }

  return server;
}

- (BOOL)configureServer:(ATProtoHttpServer *)server error:(NSError **)error {
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
                                        ATProtoHttpResponse *response,
                                        ATProtoHttpRequest *request) {
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
                                            ATProtoHttpResponse *response,
                                            ATProtoHttpRequest *request) {
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
           handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
             // Public signed-out landing. Never redirect protocol `/` into the
             // admin UI — operators reach that via an explicit link.
             response.statusCode = HttpStatusOK;
             response.contentType = @"text/html; charset=utf-8";

             NSError *readErr = nil;
             NSString *html = [NSString stringWithContentsOfFile:@"index.html"
                                                       encoding:NSUTF8StringEncoding
                                                          error:&readErr];
             if (!html) {
                 html = ATProtoHttpServerBuilderPublicLandingFallbackHTML();
             }

             NSArray *accounts = [capturedAccountService getAllAccountsWithError:nil] ?: @[];
             NSUInteger count = accounts.count;

             NSTimeInterval uptime = [[NSProcessInfo processInfo] systemUptime];
             int hours = (int)(uptime / 3600);
             int mins = (int)((uptime - hours * 3600) / 60);
             NSString *uptimeStr = [NSString stringWithFormat:@"%dh %dm", hours, mins];

             unsigned long long physicalMem = [[NSProcessInfo processInfo] physicalMemory];
             NSString *memTotal = [NSString stringWithFormat:@"%llu MB", physicalMem / 1024 / 1024];

             NSString *adminURL = ATProtoHttpServerBuilderPublicAdminURL();
             NSString *safeIssuer = ATProtoHttpServerBuilderEscapeHTML(issuer);

             html = [html stringByReplacingOccurrencesOfString:@"{{server_hostname}}" withString:safeIssuer];
             html = [html stringByReplacingOccurrencesOfString:@"{{server_uptime}}" withString:uptimeStr];
             html = [html stringByReplacingOccurrencesOfString:@"{{memory_total}}" withString:memTotal];
             html = [html stringByReplacingOccurrencesOfString:@"{{memory_used}}" withString:@"N/A"];
             html = [html stringByReplacingOccurrencesOfString:@"{{memory_free}}" withString:@"N/A"];
             html = [html stringByReplacingOccurrencesOfString:@"{{account_count}}" withString:[@(count) stringValue]];
             html = [html stringByReplacingOccurrencesOfString:@"{{admin_ui_url}}" withString:adminURL];

             NSMutableString *accountsHtml = [NSMutableString string];
             if (accounts.count == 0) {
                 [accountsHtml appendString:@"<li class=\"muted\">No accounts registered yet.</li>"];
             } else {
                 for (PDSDatabaseAccount *acc in accounts) {
                     NSString *handle = ATProtoHttpServerBuilderEscapeHTML(acc.handle ?: @"Unknown");
                     NSString *did = ATProtoHttpServerBuilderEscapeHTML(acc.did ?: @"Unknown");
                     NSString *createdAtStr = @"N/A";

                     NSTimeInterval createdAt = acc.createdAt;
                     if (createdAt > 0) {
                         NSDate *date = [NSDate dateWithTimeIntervalSince1970:createdAt];
                         NSDateFormatter *df = [[NSDateFormatter alloc] init];
                         df.dateStyle = NSDateFormatterMediumStyle;
                         df.timeStyle = NSDateFormatterShortStyle;
                         createdAtStr = ATProtoHttpServerBuilderEscapeHTML([df stringFromDate:date]);
                     }

                     [accountsHtml appendFormat:
                      @"<li><details><summary>%@</summary>"
                      @"<ul><li class=\"mono\">%@</li><li>Created: %@</li></ul></details></li>",
                      handle, did, createdAtStr];
                 }
             }

             NSRange startRange = [html rangeOfString:@"<!-- {{#each accounts}} -->"];
             NSRange endRange = [html rangeOfString:@"<!-- {{/each}} -->"];
             if (startRange.location != NSNotFound && endRange.location != NSNotFound) {
                 NSRange replaceRange = NSMakeRange(startRange.location,
                                                   endRange.location + endRange.length - startRange.location);
                 html = [html stringByReplacingCharactersInRange:replaceRange withString:accountsHtml];
             }

             [response setBodyString:html];
           }];

  // Suppress browser console noise for favicon probes when no icon asset is
  // shipped with the current runtime bundle.
  [server addRoute:@"GET"
              path:@"/favicon.ico"
           handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
             response.statusCode = HttpStatusNoContent;
             response.contentType = @"image/x-icon";
             [response setBodyData:[NSData data]];
           }];

  return YES;
}

- (void)setCorsHeaders:(ATProtoHttpResponse *)response forRequest:(ATProtoHttpRequest *)request {
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
