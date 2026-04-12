#import "Network/PDSHttpNodeInfoRoutePack.h"

#import "App/NodeInfo/NodeInfoHandler.h"
#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpServer.h"

@implementation PDSHttpNodeInfoRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                          issuer:(nullable NSString *)issuer
                            port:(NSUInteger)port
                   configuration:(nullable PDSConfiguration *)configuration
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller {
  NodeInfoHandler *nodeInfoHandler = [NodeInfoHandler sharedHandler];

  NSString *resolvedIssuer = issuer;
  if (resolvedIssuer.length == 0 && configuration) {
    resolvedIssuer = [configuration canonicalIssuerWithPortHint:port];
  }
  if (resolvedIssuer.length == 0) {
    resolvedIssuer = [[PDSConfiguration sharedConfiguration]
        canonicalIssuerWithPortHint:port];
  }

  [nodeInfoHandler setIssuer:resolvedIssuer];
  if (application.accountService) {
    [nodeInfoHandler setAccountService:application.accountService];
  } else if (controller.accountService) {
    [nodeInfoHandler setAccountService:controller.accountService];
  }
  [nodeInfoHandler setConfigured];
  [nodeInfoHandler registerRoutesWithServer:server];

  PDS_LOG_DEBUG(@"PDSHttpNodeInfoRoutePack: NodeInfo routes registered");
}

@end
