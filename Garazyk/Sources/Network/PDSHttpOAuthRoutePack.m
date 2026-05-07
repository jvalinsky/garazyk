/*!
 @file PDSHttpOAuthRoutePack.m

 @abstract Registers core OAuth-related HTTP routes for authentication protocol endpoints.

 @discussion Wires OAuth endpoint paths into server routing and delegates implementation to auth/runtime handlers. Establishes endpoint exposure and integration points without implementing token/state logic directly.
 */

#import "Network/PDSHttpOAuthRoutePack.h"

#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2Handler.h"
#import "Auth/WebAuthnRegistrationHandler.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpServer.h"

@implementation PDSHttpOAuthRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                       jwtMinter:(nullable JWTMinter *)jwtMinter
                   dataDirectory:(nullable NSString *)dataDirectory
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller {
  if (!serviceDatabases || !jwtMinter) {
    PDS_LOG_WARN(@"PDSHttpOAuthRoutePack: OAuth routes not registered - missing "
                 @"serviceDatabases or jwtMinter");
    return;
  }

  NSError *dbError = nil;
  PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:&dbError];
  if (!db) {
    PDS_LOG_WARN(@"PDSHttpOAuthRoutePack: OAuth routes not registered - could "
                 @"not get service database: %@",
                 dbError);
    return;
  }

  OAuth2Handler *oauthHandler = [[OAuth2Handler alloc] initWithDatabase:db];
  oauthHandler.minter = jwtMinter;
  oauthHandler.dataDirectory = dataDirectory;
  if (application.accountService) {
    oauthHandler.accountService = application.accountService;
  } else if (controller.accountService) {
    oauthHandler.accountService = controller.accountService;
  }
  [oauthHandler registerRoutesWithServer:server];
  PDS_LOG_DEBUG(@"PDSHttpOAuthRoutePack: OAuth routes registered");

  PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
  WebAuthnRegistrationHandler *webauthnHandler =
      [[WebAuthnRegistrationHandler alloc] initWithDatabase:db
                                                serverOrigin:config.issuer];
  [webauthnHandler registerRoutesWithServer:server];
  PDS_LOG_DEBUG(@"PDSHttpOAuthRoutePack: WebAuthn routes registered");
}

@end
