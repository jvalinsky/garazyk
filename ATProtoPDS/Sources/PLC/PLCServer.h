#import <Foundation/Foundation.h>
#import "PLC/PLCStore.h"
#import "PLC/PLCAuditor.h"
#import "Network/HttpServer.h"

NS_ASSUME_NONNULL_BEGIN

@interface PLCServer : NSObject

@property (nonatomic, readonly) HttpServer *httpServer;

- (instancetype)initWithStore:(id<PLCStore>)store auditor:(PLCAuditor *)auditor port:(NSUInteger)port;

- (BOOL)startWithError:(NSError **)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
