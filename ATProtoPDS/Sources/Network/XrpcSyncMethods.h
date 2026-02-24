#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSServiceDatabases;
@class PDSDatabasePool;
@class PDSRecordService;
@class PDSBlobService;
@class PDSRepositoryService;
@class PDSConfiguration;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcSyncMethods : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
              userDatabasePool:(PDSDatabasePool *)userDatabasePool
                 recordService:(PDSRecordService *)recordService
                   blobService:(PDSBlobService *)blobService
             repositoryService:(PDSRepositoryService *)repositoryService
                        config:(PDSConfiguration *)config;

@end

NS_ASSUME_NONNULL_END
