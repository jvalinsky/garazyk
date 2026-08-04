// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UITileDataProtocol.m

 @abstract Web Tiles data-passing protocol implementation.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import "AdminUIServer/UITileDataProtocol.h"

NSString * const UITileDataProtocolReadyAction = @"tiles-protocol-up-data-ready";
NSString * const UITileDataProtocolDownPayloadAction = @"tiles-protocol-down-data-payload";
NSString * const UITileDataProtocolUpPayloadAction = @"tiles-protocol-up-data-payload";

static NSError *UITileProtocolError(NSString *message) {
    return [NSError errorWithDomain:@"com.atproto.ui.tiles.data"
                                code:1
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSString *UITileDataProtocolJavaScript(void) {
    // The module is intentionally limited to the protocol's structured-clone
    // boundary. Host-side origin and capability policy remains outside this
    // module and is not widened by the reserved route.
    return @"const handlers = new Set();\n"
           @"export function addDataHandler(handler) {\n"
           @"  if (typeof handler !== 'function') throw new TypeError('handler must be a function');\n"
           @"  handlers.add(handler);\n"
           @"}\n"
           @"export function removeDataHandler(handler) { handlers.delete(handler); }\n"
           // The browser runtime does not expose a portable parent-origin
           // discovery API to this standalone module. The embedding context
           // must wrap/rewrite this boundary with its trusted origin policy;
           // this bounded helper is not a confidentiality boundary.
           @"export function listen() { window.parent.postMessage({ action: 'tiles-protocol-up-data-ready' }, '*'); }\n"
           @"export function sendData(payload) { window.parent.postMessage({ action: 'tiles-protocol-up-data-payload', payload }, '*'); }\n"
           @"window.addEventListener('message', (event) => {\n"
           @"  if (event.source !== window.parent) return;\n"
           @"  if (!event.data || event.data.action !== 'tiles-protocol-down-data-payload') return;\n"
           @"  for (const handler of handlers) handler(event.data.payload);\n"
           @"});\n";
}

BOOL UITileDataProtocolIsValidMessage(NSDictionary *message,
                                      BOOL fromHost,
                                      NSError **error) {
    if (![message isKindOfClass:[NSDictionary class]]) {
        if (error) *error = UITileProtocolError(@"Tiles protocol message must be an object");
        return NO;
    }
    NSString *action = message[@"action"];
    if (![action isKindOfClass:[NSString class]]) {
        if (error) *error = UITileProtocolError(@"Tiles protocol message requires a string action");
        return NO;
    }

    NSString *expected = nil;
    BOOL payloadRequired = NO;
    if (fromHost) {
        expected = UITileDataProtocolDownPayloadAction;
        payloadRequired = YES;
    } else if ([action isEqualToString:UITileDataProtocolReadyAction]) {
        expected = UITileDataProtocolReadyAction;
    } else if ([action isEqualToString:UITileDataProtocolUpPayloadAction]) {
        expected = UITileDataProtocolUpPayloadAction;
        payloadRequired = YES;
    }

    if (![action isEqualToString:expected]) {
        if (error) *error = UITileProtocolError(@"Unexpected Tiles data-protocol action");
        return NO;
    }
    if (payloadRequired && !message[@"payload"]) {
        if (error) *error = UITileProtocolError(@"Payload action requires a payload member");
        return NO;
    }
    if (!payloadRequired && message[@"payload"] != nil) {
        if (error) *error = UITileProtocolError(@"Ready action must not include a payload");
        return NO;
    }
    return YES;
}
