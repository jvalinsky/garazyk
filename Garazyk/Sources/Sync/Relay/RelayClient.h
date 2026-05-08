/*!
 @file RelayClient.h

 @abstract Client for subscribing to ATProto relay/BGS feeds.

 @discussion Connects to ATProto relay servers to receive Firehose events.
 Supports cursor-based resumption and automatic reconnection.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class RelayClient;
@class Firehose;
@class FirehoseCommitEvent;
@class FirehoseIdentityEvent;
@class FirehoseErrorEvent;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for relay client. */
extern NSString * const RelayClientErrorDomain;

/*! Error code when connection fails. */
extern NSInteger const RelayClientErrorCodeConnectionFailed;

/*! Error code when authentication fails. */
extern NSInteger const RelayClientErrorCodeAuthenticationFailed;

/*!
 @protocol RelayClientDelegate

 @abstract Delegate for relay client events.
 */
@protocol RelayClientDelegate <NSObject>
@optional
- (void)relayClient:(RelayClient *)client didReceiveCommitEvent:(FirehoseCommitEvent *)event;
- (void)relayClient:(RelayClient *)client didReceiveIdentityEvent:(FirehoseIdentityEvent *)event;
- (void)relayClient:(RelayClient *)client didReceiveErrorEvent:(FirehoseErrorEvent *)event;
- (void)relayClientDidConnect:(RelayClient *)client;
- (void)relayClient:(RelayClient *)client didDisconnectWithError:(nullable NSError *)error;
- (void)relayClient:(RelayClient *)client didReceiveCursor:(int64_t)cursor;
@end

/*!
 @class RelayClient

 @abstract Client for ATProto relay Firehose subscription.

 @discussion Maintains a WebSocket connection to a relay server.
 */
@interface RelayClient : NSObject

/*! Delegate for events. */
@property (nonatomic, weak, nullable) id<RelayClientDelegate> delegate;

/*! URL of the relay server. */
@property (nonatomic, readonly) NSURL *serverURL;

/*! The underlying Firehose client. */
@property (nonatomic, strong, readonly, nullable) Firehose *firehose;

/*! Whether connected to the server. */
@property (nonatomic, readonly) BOOL isConnected;

/*! Current cursor position (sequence number). */
@property (nonatomic, readonly) int64_t currentSeq;

/*! Interval between reconnect attempts. */
@property (nonatomic, assign, readonly) NSTimeInterval reconnectInterval;

/*! Maximum reconnect attempts. */
@property (nonatomic, assign, readonly) NSInteger maxReconnectAttempts;

- (instancetype)initWithServerURL:(NSURL *)serverURL;
- (instancetype)initWithServerURL:(NSURL *)serverURL accessToken:(nullable NSString *)accessToken;

/*! Connects to the relay server. */
- (void)connect;

/*! Disconnects from the server. */
- (void)disconnect;

/*! Sets the access token for authentication. */
- (void)setAccessToken:(NSString *)accessToken;

/*! Gets stored cursor for a repo. */
- (int64_t)getStoredCursorForRepo:(NSString *)repo;

/*! Stores a cursor for a repo. */
- (void)storeCursor:(int64_t)cursor forRepo:(NSString *)repo;

@end

NS_ASSUME_NONNULL_END
