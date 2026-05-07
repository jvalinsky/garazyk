/*!
 @file WebSocketUpgradeHandler.m

 @abstract Implements HTTP-to-WebSocket upgrade handling for eligible connection requests.

 @discussion Evaluates upgrade preconditions, negotiates WebSocket handshake transitions, and routes successful upgrades into WebSocket session handling. Owns upgrade-path mechanics, not downstream message business logic.
 */

#import "WebSocketUpgradeHandler.h"
#import "HttpRequest.h"
#import "HttpResponse.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const kWebSocketGUID = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

@implementation WebSocketUpgradeHandler

- (BOOL)handleUpgradeRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *upgrade = [[request headerForKey:@"Upgrade"] lowercaseString];
    NSString *connection = [[request headerForKey:@"Connection"] lowercaseString];
    NSString *wsVersion = [request headerForKey:@"Sec-WebSocket-Version"];
    NSString *wsKey = [request headerForKey:@"Sec-WebSocket-Key"];

    if (![self isSubscriptionPath:request.path]) {
        return NO;
    }

    BOOL hasUpgradeHeader = [upgrade isEqualToString:@"websocket"];
    BOOL hasConnectionUpgrade = [connection containsString:@"upgrade"];
    BOOL hasValidVersion = [wsVersion isEqualToString:@"13"];
    BOOL hasValidKey = wsKey.length == 24;

    if (!hasUpgradeHeader || !hasConnectionUpgrade) {
        response.statusCode = 426;
        [response setHeader:@"websocket" forKey:@"Upgrade"];
        [response setHeader:@"Upgrade" forKey:@"Connection"];
        [response setJsonBody:@{
            @"error": @"UpgradeRequired",
            @"message": @"WebSocket upgrade required. Missing Upgrade or Connection header."
        }];
        response.keepAlive = NO;
        return NO;
    }

    if (request.method != HttpMethodGET) {
        response.statusCode = 405;
        [response setHeader:@"GET" forKey:@"Allow"];
        [response setJsonBody:@{
            @"error": @"MethodNotAllowed",
            @"message": @"WebSocket endpoints only support GET method."
        }];
        response.keepAlive = NO;
        return NO;
    }

    if (!hasValidVersion) {
        response.statusCode = 501;
        [response setJsonBody:@{
            @"error": @"NotImplemented",
            @"message": [NSString stringWithFormat:@"WebSocket version %@ not supported. Only version 13 is supported.", wsVersion ?: @"unknown"]
        }];
        response.keepAlive = NO;
        return NO;
    }

    if (!hasValidKey) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"BadRequest",
            @"message": @"Invalid Sec-WebSocket-Key header."
        }];
        response.keepAlive = NO;
        return NO;
    }

    NSString *acceptKey = [self computeAcceptKey:wsKey];
    [response setHeader:@"websocket" forKey:@"Upgrade"];
    [response setHeader:@"Upgrade" forKey:@"Connection"];
    [response setHeader:acceptKey forKey:@"Sec-WebSocket-Accept"];
    [response setHeader:@"13" forKey:@"Sec-WebSocket-Version"];

    NSString *subprotocol = [request headerForKey:@"Sec-WebSocket-Protocol"];
    if (subprotocol) {
        [response setHeader:subprotocol forKey:@"Sec-WebSocket-Protocol"];
    }

    response.statusCode = 101;
    response.statusMessage = @"Switching Protocols";

    return YES;
}

- (NSString *)computeAcceptKey:(NSString *)key {
    NSString *combined = [key stringByAppendingString:kWebSocketGUID];
    const char *cStr = [combined UTF8String];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];

    CC_SHA1(cStr, (CC_LONG)strlen(cStr), digest);

    NSData *data = [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
    return [data base64EncodedStringWithOptions:0];
}

- (BOOL)isWebSocketUpgradeRequest:(HttpRequest *)request {
    NSString *upgrade = [[request headerForKey:@"Upgrade"] lowercaseString];
    NSString *connection = [[request headerForKey:@"Connection"] lowercaseString];

    return [upgrade isEqualToString:@"websocket"] &&
           [connection containsString:@"upgrade"] &&
           [request method] == HttpMethodGET &&
           [self isSubscriptionPath:[request path]];
}

- (NSString *)subscriptionPathPrefix {
    return @"/xrpc/";
}

- (BOOL)isSubscriptionPath:(NSString *)path {
    return [path hasPrefix:[self subscriptionPathPrefix]];
}

@end
