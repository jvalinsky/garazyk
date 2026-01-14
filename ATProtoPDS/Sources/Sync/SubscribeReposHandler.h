/*!
 @file SubscribeReposHandler.h

 @abstract Handler for com.atproto.sync.subscribeRepos endpoint.

 @discussion Manages WebSocket connections for the Firehose subscription
 endpoint. Broadcasts repository commits, identity changes, and account
 status updates to connected subscribers.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class WebSocketServer;
@class WebSocketConnection;
@class PDSController;
@class EventFormatter;
@class RepoCommit;
@class CID;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for subscribeRepos handler. */
extern NSString * const SubscribeReposHandlerErrorDomain;

/*! Error code for connection failures. */
extern NSInteger const SubscribeReposHandlerErrorCodeConnectionFailed;

/*!
 @protocol SubscribeReposHandlerDelegate

 @abstract Delegate for subscription lifecycle events.
 */
@protocol SubscribeReposHandlerDelegate <NSObject>
@optional
- (void)subscribeReposHandlerDidStart:(id)handler;
- (void)subscribeReposHandlerDidStop:(id)handler;
- (void)subscribeReposHandler:(id)handler didAcceptConnection:(WebSocketConnection *)connection;
- (void)subscribeReposHandler:(id)handler didCloseConnection:(WebSocketConnection *)connection;
@end

/*!
 @class SubscribeReposHandler

 @abstract Manages Firehose subscriptions.

 @discussion Broadcasts repository events to WebSocket subscribers.
 */
@interface SubscribeReposHandler : NSObject

/*! Delegate for lifecycle events. */
@property (nonatomic, weak, nullable) id<SubscribeReposHandlerDelegate> delegate;

/*! The WebSocket server for connections. */
@property (nonatomic, readonly) WebSocketServer *webSocketServer;

/*! Formats events for transmission. */
@property (nonatomic, readonly) EventFormatter *eventFormatter;

/*! The PDS controller. */
@property (nonatomic, readonly) PDSController *controller;

- (instancetype)initWithController:(PDSController *)controller;

/*! Starts listening on a port. */
- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error;

/*! Stops the handler. */
- (void)stop;

/*! Broadcasts a repository commit event. */
- (void)broadcastRepositoryCommit:(RepoCommit *)commit 
                          forRepo:(NSString *)repoDid 
                              ops:(NSArray<NSDictionary *> *)ops 
                            blobs:(NSArray<CID *> *)blobs;

/*! Broadcasts an identity change event. */
- (void)broadcastIdentityChange:(NSString *)did handle:(nullable NSString *)handle;

/*! Broadcasts an account takedown event. */
- (void)broadcastAccountTakedown:(NSString *)did;

/*! Broadcasts an info event. */
- (void)broadcastInfo:(NSString *)kind message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END