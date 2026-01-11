#import <stdint.h>
#import <stdint.h>
#import <Foundation/Foundation.h>
#include <stdint.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PDSNetworkConnectionState) {
    PDSNetworkConnectionStateWaiting = 0,
    PDSNetworkConnectionStatePreparing,
    PDSNetworkConnectionStateReady,
    PDSNetworkConnectionStateFailed,
    PDSNetworkConnectionStateCancelled
};

typedef NS_ENUM(NSInteger, PDSNetworkListenerState) {
    PDSNetworkListenerStateWaiting = 0,
    PDSNetworkListenerStateReady,
    PDSNetworkListenerStateFailed,
    PDSNetworkListenerStateCancelled
};

@protocol PDSNetworkTransport <NSObject>
- (void)cancel;
- (void)startWithQueue:(dispatch_queue_t)queue;
@end

@protocol PDSNetworkConnection <PDSNetworkTransport>

@property (nonatomic, copy, nullable) void (^stateChangedHandler)(PDSNetworkConnectionState state, NSError * _Nullable error);
@property (nonatomic, readonly, nullable) NSString *remoteAddress;

- (void)sendData:(NSData *)data completion:(void (^ _Nullable)(NSError * _Nullable error))completion;
- (void)receiveWithMinimumLength:(NSUInteger)minLength 
                  maximumLength:(NSUInteger)maxLength 
                     completion:(void (^)(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error))completion;

@end

@protocol PDSNetworkListener <PDSNetworkTransport>

@property (nonatomic, copy, nullable) void (^stateChangedHandler)(PDSNetworkListenerState state, NSError * _Nullable error);
@property (nonatomic, copy, nullable) void (^newConnectionHandler)(id<PDSNetworkConnection> connection);
@property (nonatomic, readonly) NSUInteger port;

@end

@interface PDSNetworkTransportFactory : NSObject

+ (id<PDSNetworkListener>)createListenerWithPort:(NSUInteger)port;
+ (id<PDSNetworkConnection>)createConnectionWithHost:(NSString *)host port:(NSUInteger)port;

@end

NS_ASSUME_NONNULL_END
