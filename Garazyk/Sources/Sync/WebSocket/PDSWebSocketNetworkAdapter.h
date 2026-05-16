// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSWebSocketNetworkAdapter.h

 @abstract Adapts ATProtoNetworkConnection to PDSWebSocketTransport protocol.

 @discussion Wraps a ATProtoNetworkConnection (from HTTP upgrade path) and
 exposes it as a PDSWebSocketTransport by managing frame encoding/decoding.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSWebSocketTransport.h"

@protocol ATProtoNetworkConnection;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSWebSocketNetworkAdapter

 @abstract Wraps ATProtoNetworkConnection as a PDSWebSocketTransport.

 @discussion Manages WebSocket frame encoding and decoding over a
 ATProtoNetworkConnection, allowing the HTTP upgrade path to use the same
 frame-level transport abstraction as raw socket implementations.
 */
@interface PDSWebSocketNetworkAdapter : NSObject <PDSWebSocketTransport>

/*!
 @method initWithConnection:

 @abstract Creates an adapter wrapping a network connection.

 @param connection The ATProtoNetworkConnection to wrap (e.g., from HTTP upgrade).

 @return An initialized adapter instance.
 */
- (instancetype)initWithConnection:(id<ATProtoNetworkConnection>)connection;

@end

NS_ASSUME_NONNULL_END
