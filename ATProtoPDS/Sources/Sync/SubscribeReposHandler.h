#import <Foundation/Foundation.h>

@class WebSocketServer;
@class WebSocketConnection;
@class PDSController;
@class EventFormatter;
@class RepoCommit;
@class CID;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SubscribeReposHandlerErrorDomain;
extern NSInteger const SubscribeReposHandlerErrorCodeConnectionFailed;

@protocol SubscribeReposHandlerDelegate <NSObject>
@optional
- (void)subscribeReposHandlerDidStart:(id)handler;
- (void)subscribeReposHandlerDidStop:(id)handler;
- (void)subscribeReposHandler:(id)handler didAcceptConnection:(WebSocketConnection *)connection;
- (void)subscribeReposHandler:(id)handler didCloseConnection:(WebSocketConnection *)connection;
@end

@interface SubscribeReposHandler : NSObject

@property (nonatomic, weak, nullable) id<SubscribeReposHandlerDelegate> delegate;
@property (nonatomic, readonly) WebSocketServer *webSocketServer;
@property (nonatomic, readonly) EventFormatter *eventFormatter;
@property (nonatomic, readonly) PDSController *controller;

- (instancetype)initWithController:(PDSController *)controller;
- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error;
- (void)stop;

/*!
 @method acceptUpgradedConnection:withPath:
 @abstract Accepts a WebSocket connection that has already completed the HTTP upgrade.
 @discussion This method is used when the main HTTP server handles the WebSocket
             upgrade handshake and hands off the connection to this handler.
 @param connection The network connection (post-upgrade).
 @param path The request path including query string.
 @return YES if the connection was accepted, NO otherwise.
 */
- (BOOL)acceptUpgradedConnection:(id)connection withPath:(NSString *)path;
- (void)broadcastRepositoryCommit:(RepoCommit *)commit 
                          forRepo:(NSString *)repoDid 
                              ops:(NSArray<NSDictionary *> *)ops 
                            blobs:(NSArray<CID *> *)blobs;
- (void)broadcastIdentityChange:(NSString *)did handle:(nullable NSString *)handle;
- (void)broadcastAccountTakedown:(NSString *)did;
- (void)broadcastInfo:(NSString *)kind message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END