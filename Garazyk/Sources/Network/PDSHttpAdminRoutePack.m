#import "Network/PDSHttpAdminRoutePack.h"

#import "Admin/PDSAdminHandler.h"
#import "Admin/AdminPartialHandler.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation PDSHttpAdminRoutePack

+ (void)registerAdminRoutesWithServer:(HttpServer *)server {
  PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];

  NSArray *adminPaths = @[
    @"/admin", @"/admin/login", @"/admin/logout", @"/admin/users",
    @"/admin/invites", @"/admin/invites/disable", @"/admin/blobs",
    @"/admin/metrics", @"/admin/health", @"/admin/stats", @"/admin/audit-log",
    @"/admin/plc/lookup", @"/admin/plc/export", @"/admin/plc/metrics",
    @"/admin/relay/upstreams", @"/admin/relay/events", @"/admin/relay/crawl",
    @"/admin/appview/backfill", @"/admin/appview/index", @"/admin/appview/metrics"
  ];

  for (NSString *path in adminPaths) {
    [server addRoute:@"GET"
                path:path
             handler:^(HttpRequest *request, HttpResponse *response) {
               NSInteger statusCode = 200;
               NSString *contentType = nil;
               NSString *result =
                   [adminHandler handleRequestWithMethod:PDSHTTPMethodGET
                                                    path:path
                                                 headers:request.headers
                                                    body:request.body
                                              statusCode:&statusCode
                                             contentType:&contentType];
               if (result) {
                 response.statusCode = statusCode;
                 if (contentType.length > 0) {
                   [response setHeader:contentType forKey:@"Content-Type"];
                 }
                 [response setBodyString:result];
               } else {
                 response.statusCode = 404;
                 [response setJsonBody:@{@"error" : @"Not Found"}];
               }
             }];

    [server addRoute:@"POST"
                path:path
             handler:^(HttpRequest *request, HttpResponse *response) {
               NSInteger statusCode = 200;
               NSString *contentType = nil;
               NSString *result =
                   [adminHandler handleRequestWithMethod:PDSHTTPMethodPOST
                                                    path:path
                                                 headers:request.headers
                                                    body:request.body
                                              statusCode:&statusCode
                                             contentType:&contentType];
               if (result) {
                 response.statusCode = statusCode;
                 if (contentType.length > 0) {
                   [response setHeader:contentType forKey:@"Content-Type"];
                 }
                 [response setBodyString:result];
               } else {
                 response.statusCode = 404;
                 [response setJsonBody:@{@"error" : @"Not Found"}];
               }
             }];
  }

  [self registerPartialRoutesWithServer:server adminHandler:adminHandler];
  [self registerAdminUIRoutesWithServer:server];
  PDS_LOG_DEBUG(@"PDSHttpAdminRoutePack: Admin routes registered");
}

+ (void)registerPartialRoutesWithServer:(HttpServer *)server
                           adminHandler:(PDSAdminHandler *)adminHandler {
  // Register partial routes for HTMX
  AdminPartialHandler *partialHandler = [AdminPartialHandler sharedHandler];

  [server addRoute:@"GET"
              path:@"/admin/partials/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
             NSString *partial = [request.path substringFromIndex:@"/admin/partials/".length];
             NSString *html = [partialHandler handlePartialRequestWithPath:request.path
                                                                  headers:request.headers
                                                                     body:request.body];
             if (html) {
               response.statusCode = 200;
               [response setHeader:@"text/html; charset=utf-8" forKey:@"Content-Type"];
               [response setBodyString:html];
             } else {
               response.statusCode = 404;
               [response setJsonBody:@{@"error" : @"Partial not found", @"path" : request.path}];
             }
           }];

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
