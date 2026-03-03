#import <Foundation/Foundation.h>

typedef void (^WebSocketMessageHandler)(NSData *message);
typedef void (^WebSocketCloseHandler)(NSInteger code, NSString *reason);

@interface WebSocketConnection : NSObject

@property (nonatomic, copy, readonly) NSString *remoteAddress;
@property (nonatomic, assign, readonly) NSUInteger pendingSendCount;
@property (nonatomic, assign, readonly) NSUInteger pendingSendBytes;

- (instancetype)initWithSocket:(int)socket;

- (void)start;
- (void)sendMessage:(NSData *)message;
- (void)close;
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason;

@property (nonatomic, copy) WebSocketMessageHandler messageHandler;
@property (nonatomic, copy) WebSocketCloseHandler closeHandler;

@end
