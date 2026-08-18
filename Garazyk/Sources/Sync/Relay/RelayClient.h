// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoRelayClient.h

 @abstract Client for subscribing to ATProto relay/BGS feeds.

 @discussion Connects to ATProto relay servers to receive ATProtoFirehose events.
 Supports cursor-based resumption and automatic reconnection.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Sync/Firehose/Firehose.h"

@class ATProtoRelayClient;
@class ATProtoFirehose;
@class ATProtoFirehoseCommitEvent;
@class ATProtoFirehoseIdentityEvent;
@class ATProtoFirehoseAccountEvent;
@class ATProtoFirehoseSyncEvent;
@class ATProtoFirehoseErrorEvent;
@class ATProtoFirehoseRawEvent;

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
- (void)relayClient:(ATProtoRelayClient *)client didReceiveCommitEvent:(ATProtoFirehoseCommitEvent *)event;
- (void)relayClient:(ATProtoRelayClient *)client didReceiveIdentityEvent:(ATProtoFirehoseIdentityEvent *)event;
- (void)relayClient:(ATProtoRelayClient *)client didReceiveAccountEvent:(ATProtoFirehoseAccountEvent *)event;
- (void)relayClient:(ATProtoRelayClient *)client didReceiveSyncEvent:(ATProtoFirehoseSyncEvent *)event;
- (void)relayClient:(ATProtoRelayClient *)client didReceiveErrorEvent:(ATProtoFirehoseErrorEvent *)event;
- (void)relayClient:(ATProtoRelayClient *)client didReceiveRawEvent:(ATProtoFirehoseRawEvent *)event;
- (void)relayClientDidConnect:(ATProtoRelayClient *)client;
- (void)relayClient:(ATProtoRelayClient *)client didDisconnectWithError:(nullable NSError *)error;
- (void)relayClient:(ATProtoRelayClient *)client didReceiveCursor:(int64_t)cursor;
@end

/*!
 @class ATProtoRelayClient

 @abstract Client for ATProto relay ATProtoFirehose subscription.

 @discussion Maintains a WebSocket connection to a relay server.
 */
@interface ATProtoRelayClient : NSObject

/*! Delegate for events. */
@property (nonatomic, weak, nullable) id<RelayClientDelegate> delegate;

/*! URL of the relay server. */
@property (nonatomic, readonly) NSURL *serverURL;

/*! The underlying ATProtoFirehose client. */
@property (nonatomic, strong, readonly, nullable) ATProtoFirehose *firehose;

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

/*!
 @method pauseReading

 @abstract Pauses reading from the relay. TCP backpressure propagates.

 @discussion When paused, the OS socket buffer fills, the TCP window
 shrinks, and the relay naturally slows or stops sending events.
 Used by the AppView ingest engine for backpressure.
*/
- (void)pauseReading;

/*!
 @method resumeReading

 @abstract Resumes reading from the relay after a previous pause.

 @discussion Restarts the WebSocket read loop. Events will flow again.
*/
- (void)resumeReading;

/*! Whether reading is currently paused. */
@property (nonatomic, readonly) BOOL isReadingPaused;

/*!
 When YES, reconnect uses sequences acknowledged after processing rather than
 the last decoded frame. AppView leaves this off; Zuk bounded ingress turns it on.
 */
@property (nonatomic, assign) BOOL reconnectUsesProcessedCursor;

/*!
 Optional synchronous admission gate, installed onto every
 @c ATProtoFirehose this client creates (including across reconnects) by
 @c configuredFirehoseForWebSocketURL:. Threaded the same way as
 @c reconnectUsesProcessedCursor: it is a client-level opt-in, not a
 per-connection one-off. AppView leaves this nil; Zuk's bounded ingress
 installs it via @c ATProtoRelayUpstreamManager. See ADR 0039 and
 @c ATProtoFirehose.ingressGate for the full threading contract.
 */
@property (nonatomic, copy, nullable) ATProtoFirehoseIngressGate ingressGate;

/*! Latest sequence observed on the wire, including not-yet-processed frames. */
@property (nonatomic, readonly) int64_t lastReceivedSequence;

/*! Advances the reconnect cursor after the processing contract completes. */
- (void)acknowledgeProcessedSequence:(int64_t)sequence;

/*! Sets the access token for authentication. */
- (void)setAccessToken:(NSString *)accessToken;

/*! Gets stored cursor for a repo. */
- (int64_t)getStoredCursorForRepo:(NSString *)repo;

/*! Stores a cursor for a repo. */
- (void)storeCursor:(int64_t)cursor forRepo:(NSString *)repo;

@end

NS_ASSUME_NONNULL_END
