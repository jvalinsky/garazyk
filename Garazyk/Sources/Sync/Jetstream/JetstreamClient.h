// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file JetstreamClient.h

 @abstract Client for subscribing to the Bluesky Jetstream firehose.

 @discussion Jetstream emits decoded JSON (no CAR/CBOR), so this bypasses
 block decoding entirely. Each event carries a microsecond-timestamp cursor
 that survives restarts via the existing AppView checkpoint table (the `seq`
 column stores either a relay sequence number or a Jetstream timestamp).

 Connect with `wantedCollections` to filter at the source — at ~5-10k
 longform events/day, this is ~99.99% more efficient than the full relay.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class JetstreamClient;
@class ATProtoFirehoseCommitEvent;
@class ATProtoFirehoseIdentityEvent;
@class ATProtoFirehoseAccountEvent;
@class ATProtoFirehoseErrorEvent;

/*!
 @protocol JetstreamClientDelegate

 @abstract Receives decoded Jetstream events. The delegate methods mirror
 RelayClientDelegate so the ingest engine treats both sources uniformly.
 */
@protocol JetstreamClientDelegate <NSObject>
@optional
- (void)jetstreamClient:(JetstreamClient *)client didReceiveCommitEvent:(ATProtoFirehoseCommitEvent *)event;
- (void)jetstreamClient:(JetstreamClient *)client didReceiveIdentityEvent:(ATProtoFirehoseIdentityEvent *)event;
- (void)jetstreamClient:(JetstreamClient *)client didReceiveErrorEvent:(ATProtoFirehoseErrorEvent *)event;
- (void)jetstreamClientDidConnect:(JetstreamClient *)client;
- (void)jetstreamClient:(JetstreamClient *)client didDisconnectWithError:(nullable NSError *)error;
- (void)jetstreamClient:(JetstreamClient *)client didReceiveCursor:(int64_t)cursor;
@end

/*!
 @class JetstreamClient

 @abstract WebSocket client for the Bluesky Jetstream.

 @discussion Connects to wss://jetstream2.us-east.bsky.network/subscribe,
 optionally with `?wantedCollections=` and `?cursor=` query params.
 Events are plain JSON — no CAR/CBOR, no ATProtoCID link resolution.
 */
@interface JetstreamClient : NSObject

/*! Delegate for events. */
@property (nonatomic, weak, nullable) id<JetstreamClientDelegate> delegate;

/*! The Jetstream subscription URL (with query params). */
@property (nonatomic, readonly) NSURL *subscriptionURL;

/*! Whether currently connected. */
@property (nonatomic, readonly) BOOL isConnected;

/*! Current cursor position (microsecond timestamp). */
@property (nonatomic, readonly) int64_t currentCursor;

/*! Whether reading is paused (TCP backpressure). */
@property (nonatomic, readonly) BOOL isReadingPaused;

/*!
 @method initWithJetstreamURL:wantedCollections:startingCursor:

 @param jetstreamURL Base URL (e.g. https://jetstream2.us-east.bsky.network).
 @param wantedCollections Array of collection NSIDs to filter for.
                          Empty = subscribe to all collections.
 @param startingCursor  Microsecond timestamp to resume from (0 = live).
 */
- (instancetype)initWithJetstreamURL:(NSURL *)jetstreamURL
                  wantedCollections:(NSArray<NSString *> *)wantedCollections
                     startingCursor:(int64_t)startingCursor;

/*! Connect to the Jetstream. Safe to call multiple times (no-op if connected). */
- (void)connect;

/*! Disconnect and tear down. */
- (void)disconnect;

/*! Pause reading — TCP backpressure propagates to the Jetstream server. */
- (void)pauseReading;

/*! Resume reading after a pause. */
- (void)resumeReading;

@end

NS_ASSUME_NONNULL_END
