#import "Network/PDSHttpMSTViewerRoutePack.h"

#import "App/MSTViewer/MSTViewerHandler.h"
#import "App/PDSController.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation PDSHttpMSTViewerRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                      controller:(nullable PDSController *)controller {
  if (!controller) {
    PDS_LOG_WARN(@"PDSHttpMSTViewerRoutePack: MST Viewer routes not registered - "
                 @"missing controller");
    return;
  }

  MSTViewerHandler *mstViewerHandler = [MSTViewerHandler sharedHandler];
  [mstViewerHandler setController:controller];

  [server addHandlerForPath:@"/mst-viewer"
                    handler:^(HttpRequest *request, HttpResponse *response) {
                      [mstViewerHandler handleRequest:request response:response];
                    }];

  [server addHandlerForPath:@"/api/mst"
                    handler:^(HttpRequest *request, HttpResponse *response) {
                      [mstViewerHandler handleRequest:request response:response];
                    }];

  PDS_LOG_DEBUG(@"PDSHttpMSTViewerRoutePack: MST Viewer routes registered");
}

@end
