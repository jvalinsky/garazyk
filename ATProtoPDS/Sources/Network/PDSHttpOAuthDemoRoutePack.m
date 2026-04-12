#import "Network/PDSHttpOAuthDemoRoutePack.h"

#import "App/OAuthDemo/OAuthDemoHandler.h"
#import "App/PDSController.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation PDSHttpOAuthDemoRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                   dataDirectory:(nullable NSString *)dataDirectory
                      controller:(nullable PDSController *)controller {
  if (dataDirectory.length == 0 && !controller) {
    PDS_LOG_WARN(@"PDSHttpOAuthDemoRoutePack: OAuth Demo routes not registered - "
                 @"missing dataDirectory and controller");
    return;
  }

  OAuthDemoHandler *oauthDemoHandler = [OAuthDemoHandler sharedHandler];
  if (dataDirectory.length > 0) {
    [oauthDemoHandler setDataDirectory:dataDirectory];
  } else {
    [oauthDemoHandler setController:controller];
  }

  [server addHandlerForPath:@"/oauth-demo"
                    handler:^(HttpRequest *request, HttpResponse *response) {
                      [oauthDemoHandler handleRequest:request response:response];
                    }];

  [server addRoute:@"GET"
              path:@"/oauth-demo/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [oauthDemoHandler handleRequest:request response:response];
           }];

  PDS_LOG_DEBUG(@"PDSHttpOAuthDemoRoutePack: OAuth Demo routes registered");
}

@end
