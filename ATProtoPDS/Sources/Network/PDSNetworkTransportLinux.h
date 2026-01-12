#import "PDSNetworkTransport.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSNetworkConnectionLinux : NSObject <PDSNetworkConnection>
- (instancetype)initWithHost:(NSString *)host port:(NSUInteger)port;
- (instancetype)initWithSocket:(int)sockfd address:(NSString *)address;
@end

@interface PDSNetworkListenerLinux : NSObject <PDSNetworkListener>
- (instancetype)initWithPort:(NSUInteger)port;
@end

NS_ASSUME_NONNULL_END
