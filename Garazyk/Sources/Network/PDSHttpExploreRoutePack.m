#import "Network/PDSHttpExploreRoutePack.h"

#import "App/Explore/ExploreHandler.h"
#import "App/PDSController.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation PDSHttpExploreRoutePack

+ (nullable ExploreHandler *)registerRoutesWithServer:(HttpServer *)server
                                           controller:(nullable PDSController *)controller {
  if (!controller) {
    PDS_LOG_WARN(@"PDSHttpExploreRoutePack: Explore routes not registered - "
                 @"missing controller");
    return nil;
  }

  ExploreHandler *exploreHandler = [ExploreHandler sharedHandler];
  [exploreHandler setController:controller];

  // Redirect /explore to the standalone UI server (default port 2590)
  [server addRoute:@"GET"
              path:@"/explore"
           handler:^(HttpRequest *request, HttpResponse *response) {
             response.statusCode = 302;
             [response setHeader:@"/admin#explorer" forKey:@"Location"];
             response.contentType = @"text/plain; charset=utf-8";
             [response setBodyString:@"Redirecting to UI server\n"];
           }];

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

  PDS_LOG_DEBUG(@"PDSHttpExploreRoutePack: Explore routes registered");
  return exploreHandler;
}

@end
