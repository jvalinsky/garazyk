// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSWebSocketNetworkAdapter.h

 @abstract Adapts PDSNetworkConnection to PDSWebSocketTransport protocol.

 @discussion Wraps a PDSNetworkConnection (from HTTP upgrade path) and
 exposes it as a PDSWebSocketTransport by managing frame encoding/decoding.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSWebSocketTransport.h"

@protocol PDSNetworkConnection;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSWebSocketNetworkAdapter

 @abstract Wraps PDSNetworkConnection as a PDSWebSocketTransport.

 @discussion Manages WebSocket frame encoding and decoding over a
 PDSNetworkConnection, allowing the HTTP upgrade path to use the same
 frame-level transport abstraction as raw socket implementations.
 */
@interface PDSWebSocketNetworkAdapter : NSObject <PDSWebSocketTransport>

/*!
 @method initWithConnection:

 @abstract Creates an adapter wrapping a network connection.

 @param connection The PDSNetworkConnection to wrap (e.g., from HTTP upgrade).

 @return An initialized adapter instance.
 */
- (instancetype)initWithConnection:(id<PDSNetworkConnection>)connection;

@end

NS_ASSUME_NONNULL_END
