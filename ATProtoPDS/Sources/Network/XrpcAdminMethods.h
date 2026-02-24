#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSServiceDatabases;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAdminMethods : NSObject

+ (void)registerAdminAccountMaintenanceWithDispatcher:(XrpcDispatcher *)dispatcher
                                    serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                           jwtMinter:(JWTMinter *)jwtMinter
                                     adminController:(id<PDSAdminController>)adminController;

+ (void)registerAdminAccountAndInviteWithDispatcher:(XrpcDispatcher *)dispatcher
                                  serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                         jwtMinter:(JWTMinter *)jwtMinter
                                   adminController:(id<PDSAdminController>)adminController;

+ (void)registerAdminModerationAndLabelWithDispatcher:(XrpcDispatcher *)dispatcher
                                    serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                           jwtMinter:(JWTMinter *)jwtMinter
                                     adminController:(id<PDSAdminController>)adminController
                                    includeExtraLabel:(BOOL)includeExtraLabel;

@end

NS_ASSUME_NONNULL_END
