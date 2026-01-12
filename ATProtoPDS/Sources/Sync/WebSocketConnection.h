#import <Foundation/Foundation.h>
#import <stdint.h>

@class WebSocketConnection;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const WebSocketConnectionErrorDomain;
extern NSInteger const WebSocketConnectionErrorCodeConnectionClosed;
extern NSInteger const WebSocketConnectionErrorCodeInvalidFrame;
extern NSInteger const WebSocketConnectionErrorCodeWriteFailed;

typedef NS_ENUM(NSInteger, WebSocketConnectionState) {
    WebSocketConnectionStateConnecting,
    WebSocketConnectionStateConnected,
    WebSocketConnectionStateClosing,
    WebSocketConnectionStateClosed
};

@protocol WebSocketConnectionDelegate <NSObject>
@optional
- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveMessage:(NSData *)message;
- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveText:(NSString *)text;
- (void)webSocketConnection:(WebSocketConnection *)connection didCloseWithCode:(NSInteger)code reason:(NSString *)reason;
- (void)webSocketConnection:(WebSocketConnection *)connection didFailWithError:(NSError *)error;
- (void)webSocketConnectionStateDidChange:(WebSocketConnection *)connection;
@end

@interface WebSocketConnection : NSObject

@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly, copy) NSString *queryString;
@property (nonatomic, readonly, copy, nullable) NSDictionary<NSString *, NSString *> *queryParams;
@property (nonatomic, readonly) WebSocketConnectionState state;
@property (nonatomic, weak, nullable) id<WebSocketConnectionDelegate> delegate;
@property (nonatomic, assign) NSTimeInterval heartbeatInterval;
@property (nonatomic, assign) NSTimeInterval heartbeatTimeout;
@property (nonatomic, copy, nullable) NSString *subprotocol;
@property (nonatomic, readonly) NSUUID *identifier;
@property (nonatomic, assign) NSInteger closeCode;
@property (nonatomic, copy, nullable) NSString *closeReason;

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port path:(NSString *)path;
- (instancetype)initWithConnection:(id)connection;
- (BOOL)connect:(NSError **)error;
- (void)close;
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason;
- (void)sendMessage:(NSData *)data;
- (void)sendText:(NSString *)text;
- (void)sendPing:(NSData * _Nullable)payload;
- (void)sendPong:(NSData * _Nullable)payload;

@end

NS_ASSUME_NONNULL_END
