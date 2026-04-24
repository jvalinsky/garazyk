/*!
 @file HttpProtocolDriver.m

 @abstract Implementation of HttpProtocolDriver.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "HttpProtocolDriver.h"
#import "HttpProtocolSession.h"
#import "Http1Parser.h"
#import "HttpRequest.h"

@interface HttpProtocolDriver ()
@property (nonatomic, strong) HttpProtocolSession *session;
@end

@implementation HttpProtocolDriver

- (instancetype)init {
    self = [super init];
    if (self) {
        _session = [[HttpProtocolSession alloc] init];
    }
    return self;
}

- (NSArray<NSNumber *> *)feedData:(NSData *)data {
    NSArray<NSNumber *> *sessionEvents = [self.session feedData:data];
    
    NSMutableArray<NSNumber *> *protocolEvents = [NSMutableArray array];
    for (NSNumber *eventNum in sessionEvents) {
        HttpSessionEvent sessionEvent = (HttpSessionEvent)[eventNum integerValue];
        switch (sessionEvent) {
            case HttpSessionEventRequestReady:
                [protocolEvents addObject:@(HttpProtocolEventRequestReady)];
                break;
            case HttpSessionEventError:
                [protocolEvents addObject:@(HttpProtocolEventProtocolError)];
                break;
            case HttpSessionEventUpgrade:
                [protocolEvents addObject:@(HttpProtocolEventUpgradeRequested)];
                break;
            case HttpSessionEventClose:
                [protocolEvents addObject:@(HttpProtocolEventConnectionClose)];
                break;
        }
    }
    
    return protocolEvents;
}

- (nullable HttpRequest *)nextDispatchableRequest {
    return [self.session nextRequestToDispatch];
}

- (nullable HttpRequest *)currentUpgradeRequest {
    return [self.session currentUpgradeRequest];
}

- (nullable NSError *)currentParseError {
    Http1ParserError *parserError = [self.session currentParseError];
    if (!parserError) return nil;

    return [NSError errorWithDomain:@"HttpProtocol"
                               code:(NSInteger)parserError.statusCode
                           userInfo:@{
                               NSLocalizedDescriptionKey: parserError.message ?: @"Parse error",
                               @"errorCode": parserError.errorCode ?: @"ProtocolError"
                           }];
}

- (void)setRemoteAddressForRequests:(nullable NSString *)remoteAddress {
    [self.session setRemoteAddressIfNeeded:remoteAddress];
}

- (BOOL)shouldContinueReading:(NSTimeInterval)headerStartTime
                outputQueueSize:(NSUInteger)outputQueueSize
                   headerTimeout:(NSTimeInterval)headerTimeout
                             now:(NSTimeInterval)now {
    // Check if protocol allows reading (pipelining policy)
    if (![self.session shouldReadMoreData]) {
        return NO;
    }

    // Check header timeout
    if (now - headerStartTime > headerTimeout) {
        return NO;
    }

    // Check output queue backpressure (if queue is full, don't read)
    // High water mark is 10MB
    if (outputQueueSize > 10 * 1024 * 1024) {
        return NO;
    }

    return YES;
}

- (NSUInteger)pendingRequestCount {
    return [self.session pendingDispatchCount];
}

@end
