#import <Foundation/Foundation.h>
#import "Sync/Relay/RelayRepoStateManager.h"
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Network/HttpServer.h"
#import "Sync/Firehose/SubscribeReposHandler.h"

@class DIDPLCResolver;
@class XrpcIdentityHelper;

NS_ASSUME_NONNULL_BEGIN

@interface RelayXrpcRoutePack : NSObject

@property (nonatomic, strong, nullable) DIDPLCResolver *plcResolver;
@property (nonatomic, strong, nullable) NSString *plcUrl;
@property (nonatomic, strong, nullable) RelayUpstreamManager *upstreamManager;

- (instancetype)initWithRepoStateManager:(RelayRepoStateManager *)repoStateManager
                  subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler;

- (instancetype)initWithRepoStateManager:(RelayRepoStateManager *)repoStateManager
                  subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler
                              plcResolver:(nullable DIDPLCResolver *)plcResolver NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
