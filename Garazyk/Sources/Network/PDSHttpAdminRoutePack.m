#import "Network/PDSHttpAdminRoutePack.h"

#import "Admin/PDSAdminHandler.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

static PDSHTTPMethod PDSAdminMethodFromHttpMethod(HttpMethod method) {
  switch (method) {
  case HttpMethodGET:
    return PDSHTTPMethodGET;
  case HttpMethodPOST:
    return PDSHTTPMethodPOST;
  case HttpMethodPUT:
    return PDSHTTPMethodPUT;
  case HttpMethodDELETE:
    return PDSHTTPMethodDELETE;
  default:
    return PDSHTTPMethodGET;
  }
}

static NSString *PDSAdminPathWithQuery(HttpRequest *request) {
  if (request.queryString.length == 0) {
    return request.path;
  }
  return [NSString stringWithFormat:@"%@?%@", request.path, request.queryString];
}

@implementation PDSHttpAdminRoutePack

+ (void)registerAdminRoutesWithServer:(HttpServer *)server {
  PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];

  NSArray *adminPaths = @[
    @"/admin", @"/admin/login", @"/admin/logout", @"/admin/users",
    @"/admin/users/*", @"/admin/users/bulk/takedown", @"/admin/users/bulk/delete",
    @"/admin/invites", @"/admin/invites/disable", @"/admin/blobs",
    @"/admin/metrics", @"/admin/health", @"/admin/stats", @"/admin/audit-log",
    @"/admin/plc/lookup", @"/admin/plc/export", @"/admin/plc/metrics",
    @"/admin/plc/operations",
    @"/admin/relay/upstreams", @"/admin/relay/events", @"/admin/relay/crawl",
    @"/admin/relay/operators",
    @"/admin/appview/backfill", @"/admin/appview/index", @"/admin/appview/metrics",
    @"/admin/chat/convos", @"/admin/chat/messages", @"/admin/chat/reports",
    @"/admin/ozone/events", @"/admin/ozone/statuses", @"/admin/ozone/team", @"/admin/ozone/templates",
    @"/admin/ozone/sets", @"/admin/ozone/correlations", @"/admin/ozone/verification",
    @"/admin/ozone/safelinks", @"/admin/ozone/scheduled", @"/admin/ozone/config",
    @"/admin/security/sessions", @"/admin/security/app-passwords"
  ];

  NSArray<NSString *> *httpMethods = @[@"GET", @"POST", @"PUT", @"DELETE"];

  for (NSString *path in adminPaths) {
    for (NSString *httpMethod in httpMethods) {
      [server addRoute:httpMethod
                  path:path
               handler:^(HttpRequest *request, HttpResponse *response) {
                 NSInteger statusCode = 200;
                 NSString *contentType = nil;
                 NSDictionary<NSString *, NSString *> *customHeaders = nil;
                 NSString *result =
                     [adminHandler handleRequestWithMethod:PDSAdminMethodFromHttpMethod(request.method)
                                                     path:PDSAdminPathWithQuery(request)
                                                   headers:request.headers
                                                      body:request.body
                                                statusCode:&statusCode
                                               contentType:&contentType
                                              outHeaders:&customHeaders];
                 if (result) {
                   response.statusCode = statusCode;
                   if (contentType.length > 0) {
                     [response setHeader:contentType forKey:@"Content-Type"];
                   }
                   if (customHeaders.count > 0) {
                     for (NSString *key in customHeaders) {
                       [response setHeader:customHeaders[key] forKey:key];
                     }
                   }
                   [response setBodyString:result];
                 } else {
                   response.statusCode = 404;
                   [response setJsonBody:@{@"error" : @"Not Found"}];
                 }
               }];
    }
  }

  [self registerPartialRoutesWithServer:server adminHandler:adminHandler];
  [self registerAdminUIRoutesWithServer:server];
  PDS_LOG_DEBUG(@"PDSHttpAdminRoutePack: Admin routes registered");
}

+ (void)registerPartialRoutesWithServer:(HttpServer *)server
                           adminHandler:(PDSAdminHandler *)adminHandler {
  NSArray<NSString *> *httpMethods = @[@"GET", @"POST", @"PUT", @"DELETE"];
  for (NSString *httpMethod in httpMethods) {
    [server addRoute:httpMethod
                path:@"/admin/partials/*"
             handler:^(HttpRequest *request, HttpResponse *response) {
               NSInteger statusCode = 200;
               NSString *contentType = nil;
               NSDictionary<NSString *, NSString *> *customHeaders = nil;
               NSString *result =
                   [adminHandler handleRequestWithMethod:PDSAdminMethodFromHttpMethod(request.method)
                                                    path:PDSAdminPathWithQuery(request)
                                                 headers:request.headers
                                                    body:request.body
                                              statusCode:&statusCode
                                             contentType:&contentType
                                            outHeaders:&customHeaders];
               if (result) {
                 response.statusCode = statusCode;
                 NSString *resolvedContentType =
                     contentType.length > 0 ? contentType : @"text/html; charset=utf-8";
                 [response setHeader:resolvedContentType forKey:@"Content-Type"];
                 if (customHeaders.count > 0) {
                   for (NSString *key in customHeaders) {
                     [response setHeader:customHeaders[key] forKey:key];
                   }
                 }
                 [response setBodyString:result];
               } else {
                 response.statusCode = 404;
                 [response setJsonBody:@{@"error" : @"Partial not found", @"path" : request.path}];
               }
             }];
  }

  PDS_LOG_DEBUG(@"PDSHttpAdminRoutePack: Partial routes registered");
}

+ (void)registerAdminUIRoutesWithServer:(HttpServer *)server {
  PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];

  // Register /admin/ui entry point
  [server addRoute:@"GET"
              path:@"/admin/ui"
           handler:^(HttpRequest *request, HttpResponse *response) {
             NSInteger statusCode = 200;
             NSString *contentType = nil;
             NSString *result =
                 [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                  path:@"/admin/ui"
                                               headers:request.headers
                                                  body:request.body
                                            statusCode:&statusCode
                                           contentType:&contentType];
             if (result) {
               response.statusCode = statusCode;
               response.contentType = @"text/html; charset=utf-8";
               [response setBodyString:result];
             } else {
               response.statusCode = 404;
               [response setJsonBody:@{@"error" : @"Not Found"}];
             }
           }];

  // Register /admin/assets/* for static assets
  [server addRoute:@"GET"
              path:@"/admin/assets/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
             NSInteger statusCode = 200;
             NSString *contentType = nil;
             NSString *result =
                 [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                  path:request.path
                                               headers:request.headers
                                                  body:request.body
                                            statusCode:&statusCode
                                           contentType:&contentType];
             if (result) {
               response.statusCode = statusCode;
               response.contentType = (contentType && contentType.length > 0) ? contentType : @"application/octet-stream";
               [response setBodyString:result];
             } else {
               response.statusCode = 404;
               [response setJsonBody:@{@"error" : @"Not Found"}];
             }
           }];

  // Register /admin/css/* for CSS files
  [server addRoute:@"GET"
              path:@"/admin/css/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
             NSInteger statusCode = 200;
             NSString *contentType = nil;
             NSString *result =
                 [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                  path:request.path
                                               headers:request.headers
                                                  body:request.body
                                            statusCode:&statusCode
                                           contentType:&contentType];
             if (result) {
               response.statusCode = statusCode;
               response.contentType = @"text/css; charset=utf-8";
               [response setBodyString:result];
             } else {
               response.statusCode = 404;
               [response setJsonBody:@{@"error" : @"Not Found"}];
             }
           }];

  // Register /admin/js/* for JavaScript files
  [server addRoute:@"GET"
              path:@"/admin/js/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
             NSInteger statusCode = 200;
             NSString *contentType = nil;
             NSString *result =
                 [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                  path:request.path
                                               headers:request.headers
                                                  body:request.body
                                            statusCode:&statusCode
                                           contentType:&contentType];
             if (result) {
               response.statusCode = statusCode;
               response.contentType = @"application/javascript; charset=utf-8";
               [response setBodyString:result];
             } else {
               response.statusCode = 404;
               [response setJsonBody:@{@"error" : @"Not Found"}];
             }
           }];

  PDS_LOG_DEBUG(@"PDSHttpAdminRoutePack: Admin UI routes registered");
}

@end
