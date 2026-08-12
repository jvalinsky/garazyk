// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Defines WSHeartbeatAction values exposed by this API.
 */
typedef NS_ENUM(NSInteger, WSHeartbeatAction) {
    WSHeartbeatActionNone,
    WSHeartbeatActionSendPing,
    WSHeartbeatActionTimeout     // connection should be closed
};

/**
 * @abstract Declares the ATProtoWebSocketHeartbeatPolicy public API.
 */
@interface ATProtoWebSocketHeartbeatPolicy : NSObject

/**
 * @abstract Exposes the heartbeat interval value.
 */
@property (nonatomic, assign) NSTimeInterval heartbeatInterval; // default 30.0
@property (nonatomic, assign) NSTimeInterval heartbeatTimeout;  // default 10.0

// Called by the adapter at regular intervals (e.g., timer tick)
- (WSHeartbeatAction)tick:(NSTimeInterval)now;

// Called when a pong is received
- (void)pongReceived:(NSTimeInterval)now;

// Called when a ping is sent
- (void)pingSent:(NSTimeInterval)now;

@end

NS_ASSUME_NONNULL_END