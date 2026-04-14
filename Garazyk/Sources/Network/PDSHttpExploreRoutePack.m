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
