#import <Foundation/Foundation.h>
#import "Sync/RelayRepoStateManager.h"
#import "Network/HttpServer.h"
#import "Sync/SubscribeReposHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface RelayXrpcRoutePack : NSObject

- (instancetype)initWithRepoStateManager:(RelayRepoStateManager *)repoStateManager
                  subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler;

- (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
