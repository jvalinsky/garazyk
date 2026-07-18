// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcMethodRegistry.h"
#import "Admin/PDSAdminController.h"
#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "App/PDSController.h"
#import "Debug/GZLogger.h"
#import "Network/XrpcAdminPack.h"
#import "Network/XrpcAppBskyPack.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcIdentityPack.h"
#import "Network/XrpcLabelPack.h"
#import "Network/XrpcRepoPack.h"
#import "Network/XrpcModerationPack.h"
#import "Network/XrpcVendorPack.h"
#import "Network/XrpcLexiconResolver.h"
#import "Network/XrpcProxyInterceptor.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/XrpcRoutePackRegistrar.h"
#import "Network/XrpcServerPack.h"
#import "Network/XrpcSyncPack.h"
#import "Network/XrpcSpacePack.h"
#import "Network/XrpcSpaceRecoveryTestPack.h"
#import "Services/PDS/PDSSpaceReconciler.h"
#import "Registration/PDSRegistrationGate.h"

@implementation XrpcMethodRegistry

static void registerMethodsWithDispatcherUsingServices(
    Class registryClass, XrpcDispatcher *dispatcher,
    id<PDSAccountService> accountService, PDSRecordService *recordService,
    PDSBlobService *blobService, PDSRepositoryService *repositoryService,
    PDSRelayService *relayService, id<PDSAdminController> adminController,
    PDSBlobAuditManager *blobAuditManager,
    PDSServiceDatabases *serviceDatabases, PDSDatabasePool *userDatabasePool,
    JWTMinter *jwtMinter, RateLimiter *rateLimiter, ATProtoServiceConfiguration *config,
    id<PDSEmailProvider> emailProvider,
    SubscribeReposHandler *subscribeReposHandler, PDSSpaceStore *spaceStore,
    PDSSpaceReconciler *spaceReconciler) {

  // A dispatcher can outlive a PDSApplication in tests and controlled restarts.
  // This registry owns the complete handler set, so rebuild it rather than
  // treating a prior application's handlers as a second route owner.
  [dispatcher resetRegisteredMethods];

  [XrpcLexiconResolver registerResolveLexiconMethodOnDispatcher:dispatcher
                                                   configuration:config];

  [XrpcProxyInterceptor installOnDispatcher:dispatcher
                              configuration:config
                                  jwtMinter:jwtMinter
                            adminController:adminController
                           serviceDatabases:serviceDatabases
                           userDatabasePool:userDatabasePool];

  XrpcRoutePackServiceBag *routePackServices =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:jwtMinter
                                          adminController:adminController
                                             configuration:config
                                               adminSecret:nil
                                         serviceDatabases:serviceDatabases
                                         userDatabasePool:userDatabasePool
                                               rateLimiter:rateLimiter];
  routePackServices.accountService = accountService;
  routePackServices.recordService = recordService;
  routePackServices.blobService = blobService;
  routePackServices.repositoryService = repositoryService;
  routePackServices.relayService = relayService;
  routePackServices.emailProvider = emailProvider;
  routePackServices.subscribeReposHandler = subscribeReposHandler;
  routePackServices.blobAuditManager = blobAuditManager;
  routePackServices.spaceStore = spaceStore;
  routePackServices.spaceReconciler = spaceReconciler;

  // Register domain modules in order
  [XrpcServerPack registerWithDispatcher:dispatcher services:routePackServices];
  [XrpcIdentityPack registerWithDispatcher:dispatcher services:routePackServices];
  [XrpcRepoPack registerWithDispatcher:dispatcher services:routePackServices];
  [XrpcSyncPack registerWithDispatcher:dispatcher services:routePackServices];

  [XrpcSpacePack registerWithDispatcher:dispatcher services:routePackServices];
  NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
  if ([XrpcSpaceRecoveryTestPack isEnabledForEnvironment:environment]) {
    [XrpcSpaceRecoveryTestPack registerWithDispatcher:dispatcher services:routePackServices];
  }

  [XrpcAppBskyPack registerWithDispatcher:dispatcher services:routePackServices];

  [XrpcAdminPack registerWithDispatcher:dispatcher services:routePackServices];

  [XrpcLabelPack registerWithDispatcher:dispatcher services:routePackServices];

  [XrpcModerationPack registerWithDispatcher:dispatcher services:routePackServices];

  [XrpcVendorPack registerWithDispatcher:dispatcher services:routePackServices];
}

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller {
  if (!dispatcher || !controller) {
    return;
  }
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  registerMethodsWithDispatcherUsingServices(
      self, dispatcher, controller.accountService, controller.recordService,
      controller.blobService, controller.repositoryService,
      controller.relayService, controller.adminController,
      controller.application.blobAuditManager,
      controller.serviceDatabases, controller.userDatabasePool,
      controller.jwtMinter, controller.rateLimiter, config, nil,
      controller.subscribeReposHandler, controller.application.spaceStore,
      controller.application.spaceReconciler);
}

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                          application:(PDSApplication *)application {
  if (!dispatcher || !application) {
    return;
  }
  registerMethodsWithDispatcherUsingServices(
      self, dispatcher, application.accountService, application.recordService,
      application.blobService, application.repositoryService,
      application.relayService, application.adminController,
      application.blobAuditManager,
      application.serviceDatabases, application.userDatabasePool,
      application.jwtMinter, application.rateLimiter, application.configuration,
      application.emailProvider,
      application.subscribeReposHandler, application.spaceStore,
      application.spaceReconciler);
}

@end
