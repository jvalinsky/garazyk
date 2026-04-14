#import "Network/PDSHttpCappuccinoUIRoutePack.h"

#import "App/CappuccinoUI/CappuccinoUIHandler.h"
#import "App/PDSController.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation PDSHttpCappuccinoUIRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                   dataDirectory:(nullable NSString *)dataDirectory
                      controller:(nullable PDSController *)controller {
  [self registerRoutesWithServer:server
                   dataDirectory:dataDirectory
                      controller:controller
                  serviceProfile:@"pds"];
}

+ (void)registerRoutesWithServer:(HttpServer *)server
                   dataDirectory:(nullable NSString *)dataDirectory
                      controller:(nullable PDSController *)controller
                  serviceProfile:(NSString *)serviceProfile {
  CappuccinoUIHandler *cappuccinoUIHandler = [CappuccinoUIHandler sharedHandler];

  if (dataDirectory.length > 0) {
    [cappuccinoUIHandler setDataDirectory:dataDirectory];
  } else if (controller) {
    [cappuccinoUIHandler setController:controller];
  }
  [cappuccinoUIHandler setServiceProfile:serviceProfile];

  [server addRoute:@"GET"
              path:@"/ui"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [cappuccinoUIHandler handleRequest:request response:response];
           }];

  [server addRoute:@"GET"
              path:@"/ui/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [cappuccinoUIHandler handleRequest:request response:response];
           }];

  PDS_LOG_DEBUG(@"PDSHttpCappuccinoUIRoutePack: Cappuccino UI routes "
                @"registered (profile=%@)",
                serviceProfile);
}

@end
