// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UITileDataProtocol.m

 @abstract Web Tiles data-passing protocol implementation.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import "AdminUIServer/UITileDataProtocol.h"

NSString * const GZAdminUITileDataProtocolReadyAction = @"tiles-protocol-up-data-ready";
NSString * const GZAdminUITileDataProtocolDownPayloadAction = @"tiles-protocol-down-data-payload";
NSString * const GZAdminUITileDataProtocolUpPayloadAction = @"tiles-protocol-up-data-payload";

static NSError *GZAdminUITileProtocolError(NSString *message) {
    return [NSError errorWithDomain:@"com.atproto.ui.tiles.data"
                                code:1
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSString *GZAdminUITileDataProtocolJavaScript(void) {
    return GZAdminUITileDataProtocolJavaScriptWithTrustedOrigin(nil);
}

NSString *GZAdminUITileDataProtocolJavaScriptWithTrustedOrigin(NSString *trustedOrigin) {
    NSString *targetLiteral = @"'*'";
    NSString *originCheck = @"  // No trusted-origin gate configured.\n";
    if (trustedOrigin.length > 0) {
        NSMutableString *escaped = [NSMutableString string];
        for (NSUInteger i = 0; i < trustedOrigin.length; i++) {
            unichar c = [trustedOrigin characterAtIndex:i];
            if (c == '\\' || c == '\'') {
                [escaped appendFormat:@"\\%C", c];
            } else {
                [escaped appendFormat:@"%C", c];
            }
        }
        targetLiteral = [NSString stringWithFormat:@"'%@'", escaped];
        originCheck = [NSString stringWithFormat:
                       @"  if (event.origin !== '%@') return;\n", escaped];
    }
    return [NSString stringWithFormat:
           @"const handlers = new Set();\n"
           @"export function addDataHandler(handler) {\n"
           @"  if (typeof handler !== 'function') throw new TypeError('handler must be a function');\n"
           @"  handlers.add(handler);\n"
           @"}\n"
           @"export function removeDataHandler(handler) { handlers.delete(handler); }\n"
           @"export function listen() { window.parent.postMessage({ action: 'tiles-protocol-up-data-ready' }, %@); }\n"
           @"export function sendData(payload) { window.parent.postMessage({ action: 'tiles-protocol-up-data-payload', payload }, %@); }\n"
           @"window.addEventListener('message', (event) => {\n"
           @"  if (event.source !== window.parent) return;\n"
           @"%@"
           @"  if (!event.data || event.data.action !== 'tiles-protocol-down-data-payload') return;\n"
           @"  for (const handler of handlers) handler(event.data.payload);\n"
           @"});\n",
           targetLiteral, targetLiteral, originCheck];
}

BOOL GZAdminUITileDataProtocolIsValidMessage(NSDictionary *message,
                                      BOOL fromHost,
                                      NSError **error) {
    if (![message isKindOfClass:[NSDictionary class]]) {
        if (error) *error = GZAdminUITileProtocolError(@"Tiles protocol message must be an object");
        return NO;
    }
    NSString *action = message[@"action"];
    if (![action isKindOfClass:[NSString class]]) {
        if (error) *error = GZAdminUITileProtocolError(@"Tiles protocol message requires a string action");
        return NO;
    }

    NSString *expected = nil;
    BOOL payloadRequired = NO;
    if (fromHost) {
        expected = GZAdminUITileDataProtocolDownPayloadAction;
        payloadRequired = YES;
    } else if ([action isEqualToString:GZAdminUITileDataProtocolReadyAction]) {
        expected = GZAdminUITileDataProtocolReadyAction;
    } else if ([action isEqualToString:GZAdminUITileDataProtocolUpPayloadAction]) {
        expected = GZAdminUITileDataProtocolUpPayloadAction;
        payloadRequired = YES;
    }

    if (![action isEqualToString:expected]) {
        if (error) *error = GZAdminUITileProtocolError(@"Unexpected Tiles data-protocol action");
        return NO;
    }
    if (payloadRequired && !message[@"payload"]) {
        if (error) *error = GZAdminUITileProtocolError(@"Payload action requires a payload member");
        return NO;
    }
    if (!payloadRequired && message[@"payload"] != nil) {
        if (error) *error = GZAdminUITileProtocolError(@"Ready action must not include a payload");
        return NO;
    }
    return YES;
}
