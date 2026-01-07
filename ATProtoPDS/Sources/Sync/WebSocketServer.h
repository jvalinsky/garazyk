#import <Foundation/Foundation.h>

@class WebSocketConnection;
@class WebSocketServer;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const WebSocketServerErrorDomain;
extern NSInteger const WebSocketServerErrorCodeListenerFailed;
extern NSInteger const WebSocketServerErrorCodeInvalidHandshake;
extern NSInteger const WebSocketServerErrorCodeConnectionFailed;

typedef NS_ENUM(NSInteger, WebSocketServerState) {
    WebSocketServerStateIdle,
    WebSocketServerStateStarting,
    WebSocketServerStateRunning,
    WebSocketServerStateStopping,
    WebSocketServerStateFailed
};

@protocol WebSocketServerDelegate <NSObject>
@optional
- (void)webSocketServer:(WebSocketServer *)server didAcceptConnection:(WebSocketConnection *)connection;
- (void)webSocketServer:(WebSocketServer *)server didCloseConnection:(WebSocketConnection *)connection;
- (void)webSocketServer:(WebSocketServer *)server didFailWithError:(NSError *)error;
- (void)webSocketServer:(WebSocketServer *)server stateDidChange:(WebSocketServerState)state;
@end

@interface WebSocketServer : NSObject

@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) WebSocketServerState state;
@property (nonatomic, weak, nullable) id<WebSocketServerDelegate> delegate;
@property (nonatomic, readonly) NSSet<WebSocketConnection *> *connections;
@property (nonatomic, copy, nullable) NSString *subprotocol;
@property (nonatomic, strong, readonly) NSMutableSet<WebSocketConnection *> *mutableConnections;

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port;
- (BOOL)start:(NSError **)error;
- (void)stop;
- (void)broadcastMessage:(NSData *)message toConnectionsMatching:(NSPredicate * _Nullable)predicate;

@end

NS_ASSUME_NONNULL_END
