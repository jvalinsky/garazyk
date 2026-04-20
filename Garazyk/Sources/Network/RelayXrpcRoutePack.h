#import <Foundation/Foundation.h>
#import "Sync/Relay/RelayRepoStateManager.h"
#import "Network/HttpServer.h"
#import "Sync/Firehose/SubscribeReposHandler.h"

@class DIDPLCResolver;
@class XrpcIdentityHelper;

NS_ASSUME_NONNULL_BEGIN

@interface RelayXrpcRoutePack : NSObject

@property (nonatomic, strong, nullable) DIDPLCResolver *plcResolver;
@property (nonatomic, strong, nullable) NSString *plcUrl;

- (instancetype)initWithRepoStateManager:(RelayRepoStateManager *)repoStateManager
                  subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler;

- (instancetype)initWithRepoStateManager:(RelayRepoStateManager *)repoStateManager
                  subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler
                              plcResolver:(nullable DIDPLCResolver *)plcResolver NS_DESIGNATED_INITIALIZER;

- (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
