// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UITileDataProtocol.h

 @abstract Web Tiles data-passing protocol contract.

 @discussion Exposes the reserved `/.well-known/web-tiles/data.js` module and
 validates the protocol's postMessage action/payload envelope. This bounded
 slice does not grant network access or host arbitrary tile content.

 @see https://dasl.ing/tiles-protocols.html
 @see https://dasl.ing/tp-data.html
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const UITileDataProtocolReadyAction;
FOUNDATION_EXPORT NSString * const UITileDataProtocolDownPayloadAction;
FOUNDATION_EXPORT NSString * const UITileDataProtocolUpPayloadAction;

/** Returns the deterministic JavaScript module served at the reserved route. */
FOUNDATION_EXPORT NSString *UITileDataProtocolJavaScript(void);

/** Returns YES only for a protocol action with the expected direction and payload shape. */
FOUNDATION_EXPORT BOOL UITileDataProtocolIsValidMessage(NSDictionary *message,
                                                        BOOL fromHost,
                                                        NSError **error);

NS_ASSUME_NONNULL_END
