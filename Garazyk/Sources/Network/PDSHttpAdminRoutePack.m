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
    @"/admin/metrics", @"/admin/health", @"/admin/stats", @"/admin/audit-log"
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
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *assetsPath = nil;

  NSArray *candidates = @[
    [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"AdminUI/Assets"],
    [[NSBundle bundleForClass:[self class]].resourcePath
        stringByAppendingPathComponent:@"AdminUI/Assets"],
    [[fm currentDirectoryPath]
        stringByAppendingPathComponent:@"Garazyk/Sources/Admin/AdminUI/Assets"],
    [[fm currentDirectoryPath]
        stringByAppendingPathComponent:@"Garazyk/Sources/App/AdminUI/Assets"],
    [[[fm currentDirectoryPath]
        stringByAppendingPathComponent:@"../Garazyk/Sources/Admin/AdminUI/Assets"]
        stringByStandardizingPath],
    [[[fm currentDirectoryPath]
        stringByAppendingPathComponent:@"../Garazyk/Sources/App/AdminUI/Assets"]
        stringByStandardizingPath],
    @"/usr/share/atprotopds/assets/AdminUI",
    @"/usr/local/share/atprotopds/assets/AdminUI"
  ];

  for (NSString *candidate in candidates) {
    if ([fm fileExistsAtPath:candidate]) {
      assetsPath = candidate;
      break;
    }
  }

  if (!assetsPath) {
    PDS_LOG_WARN(@"PDSHttpAdminRoutePack: Admin UI assets not found");
    return;
  }
  PDS_LOG_INFO(@"PDSHttpAdminRoutePack: Admin UI assets found at %@",
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

  PDS_LOG_DEBUG(@"PDSHttpAdminRoutePack: Admin UI routes registered");
}

@end
