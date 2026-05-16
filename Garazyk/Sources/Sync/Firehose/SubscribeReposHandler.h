// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file SubscribeReposHandler.h
 
 @abstract Handler for com.atproto.sync.subscribeRepos endpoint.
 
 @discussion Manages WebSocket connections for the Firehose subscription
 endpoint. Broadcasts repository commits, identity changes, and account
 status updates to connected subscribers.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Compat/PDSTypes.h"

#import "Sync/Firehose/Firehose.h"
#import "Sync/Relay/RelayEventBuffer.h"

@class WebSocketServer;
@class WebSocketConnection;
@class PDSServiceDatabases;
@class EventFormatter;
@class RepoCommit;
@class CID;
@class HttpRequest;
@protocol ATProtoNetworkConnection;
@class PDSDatabasePool;
@class RelayMetrics;

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

/*! Legacy standalone WebSocket server (compatibility/test use only). */
@property (nonatomic, readonly) WebSocketServer *webSocketServer
    DEPRECATED_MSG_ATTRIBUTE("subscribeRepos uses HTTP upgrade path; use acceptUpgradedConnection:request:");

/*! Formats events for transmission. */
@property (nonatomic, readonly) EventFormatter *eventFormatter;

/*! Current WebSocket connections. */
@property (nonatomic, readonly) NSSet<WebSocketConnection *> *attachedConnections;

/*! The service databases for event persistence. */
@property (nonatomic, readonly) PDSServiceDatabases *serviceDatabases;

/*! Backward-compatible test hook for legacy signing-key injection. */
@property (nonatomic, copy, nullable) NSData *signingKey;

/*! Relay metrics sink. Set when running inside the Relay (`zuk`); nil for plain PDS. */
@property (nonatomic, strong, nullable) RelayMetrics *relayMetrics;

/*! In-memory event buffer for relay-mode replay when serviceDatabases is nil. */
@property (nonatomic, strong, nullable) RelayEventBuffer *eventBuffer;


- (instancetype)initWithServiceDatabases:(nullable PDSServiceDatabases *)serviceDatabases;

- (instancetype)initWithServiceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                        userDatabasePool:(nullable PDSDatabasePool *)userDatabasePool;

/*! Starts a legacy standalone listener (compatibility/test use only). */
- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error
    DEPRECATED_MSG_ATTRIBUTE("subscribeRepos uses HTTP upgrade path; this legacy listener is deprecated");

/*! Starts observing account and record change notifications for live firehose events. */
- (void)startObservingNotifications;

/*! Stops observing account and record change notifications. */
- (void)stopObservingNotifications;

/*! Stops the handler. */
- (void)stop;

/*! Waits for queued event persistence and fanout work to drain. */
- (BOOL)waitForIdleWithTimeout:(NSTimeInterval)timeout;

/*! Accepts a WebSocket-upgraded connection from the main HTTP server. */
- (void)acceptUpgradedConnection:(id<ATProtoNetworkConnection>)connection request:(HttpRequest *)request;

/*! Broadcasts a repository commit event object. */
- (void)broadcastCommitEvent:(FirehoseCommitEvent *)event;

/*! Broadcasts a repository commit event. */
- (void)broadcastRepositoryCommit:(RepoCommit *)commit 
                          forRepo:(NSString *)repoDid 
                              ops:(NSArray<NSDictionary *> *)ops 
                            blobs:(NSArray<CID *> *)blobs;

/*! Broadcasts an identity change event. */
- (void)broadcastIdentityChange:(NSString *)did handle:(nullable NSString *)handle;

/*! Broadcasts an account status event for any lifecycle transition. */
- (void)broadcastAccountStatus:(NSString *)did
                        active:(BOOL)active
                        status:(nullable NSString *)status;

/*! Broadcasts an account takedown event. Convenience method. */
- (void)broadcastAccountTakedown:(NSString *)did;

/*! Broadcasts an informational message. */
- (void)broadcastInfo:(NSString *)kind message:(NSString *)message;

/*! Broadcasts pre-encoded raw CBOR data to all connected clients. */
- (void)broadcastEventData:(NSData *)eventData;

/*! Returns and increments the next sequence number for this handler's stream. */
- (NSUInteger)nextSequenceNumber;

@end

NS_ASSUME_NONNULL_END
