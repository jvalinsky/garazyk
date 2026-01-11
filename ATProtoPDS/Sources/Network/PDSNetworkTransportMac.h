#import "Network/PDSNetworkTransport.h"
#import <Network/Network.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSNetworkConnectionMac : NSObject <PDSNetworkConnection>
- (instancetype)initWithConnection:(nw_connection_t)connection;
- (instancetype)initWithHost:(NSString *)host port:(NSUInteger)port;
@end

@interface PDSNetworkListenerMac : NSObject <PDSNetworkListener>
- (instancetype)initWithPort:(NSUInteger)port;
@end

NS_ASSUME_NONNULL_END
