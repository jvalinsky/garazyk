// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpConnectionIOCoordinator.m

 @abstract Coordinates low-level HTTP connection I/O sequencing and buffer handoff.

 @discussion Orchestrates read/write coordination between connection drivers and protocol/session components, including ordering and lifecycle transitions for connection I/O events.
 */

#import "HttpConnectionIOCoordinator.h"
#import "Network/HttpProtocolDriver.h"
#import "Network/HttpResponseSender.h"
#import "Network/HttpRequest.h"
#import "Network/ATProtoNetworkTransport.h"
#import "Compat/PDSTypes.h"

@interface HttpConnectionIOCoordinator ()
@property (nonatomic, strong) id<ATProtoNetworkConnection> connection;
@property (nonatomic, strong) HttpProtocolDriver *driver;
@property (nonatomic, strong) HttpResponseSender *sender;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t coordinationQueue;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, assign) BOOL readScheduled;
@property (nonatomic, assign) BOOL isClosed;
@property (nonatomic, assign) NSTimeInterval headerStartTime;
@property (nonatomic, assign) BOOL isReadingRequestBody;
@property (nonatomic, assign) NSUInteger headerTerminatorMatchLength;
@property (nonatomic, assign) NSTimeInterval idleHeaderTimeout;
@property (nonatomic, assign) NSTimeInterval aggregateHeaderTimeout;
@property (nonatomic, assign) NSUInteger idleDeadlineGeneration;
@property (nonatomic, assign) NSUInteger aggregateDeadlineGeneration;
@property (nonatomic, assign) BOOL didEmitTerminalTimeout;
@end

static const NSTimeInterval kDefaultHttpHeaderIdleTimeout = 30.0;
static const NSTimeInterval kDefaultHttpHeaderAggregateTimeout = 30.0;
static NSString * const kHttpConnectionIOCoordinatorErrorDomain = @"HttpConnectionIOCoordinator";
static const NSInteger kHttpConnectionIOCoordinatorHeaderTimeoutError = 1;

@implementation HttpConnectionIOCoordinator

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithConnection:(id<ATProtoNetworkConnection>)connection
                           protocol:(HttpProtocolDriver *)driver
                       responseSender:(HttpResponseSender *)sender {
    return [self initWithConnection:connection
                           protocol:driver
                     responseSender:sender
                  idleHeaderTimeout:kDefaultHttpHeaderIdleTimeout
             aggregateHeaderTimeout:kDefaultHttpHeaderAggregateTimeout];
}

- (instancetype)initWithConnection:(id<ATProtoNetworkConnection>)connection
                           protocol:(HttpProtocolDriver *)driver
                     responseSender:(HttpResponseSender *)sender
                  idleHeaderTimeout:(NSTimeInterval)idleHeaderTimeout
             aggregateHeaderTimeout:(NSTimeInterval)aggregateHeaderTimeout {
    self = [super init];
    if (self) {
        _connection = connection;
        _driver = driver;
        _sender = sender;
        _isPaused = NO;
        _readScheduled = NO;
        _isClosed = NO;
        _headerStartTime = 0;
        _isReadingRequestBody = NO;
        _headerTerminatorMatchLength = 0;
        _idleHeaderTimeout = idleHeaderTimeout > 0 ? idleHeaderTimeout : kDefaultHttpHeaderIdleTimeout;
        _aggregateHeaderTimeout = aggregateHeaderTimeout > 0 ? aggregateHeaderTimeout : kDefaultHttpHeaderAggregateTimeout;
        _idleDeadlineGeneration = 0;
        _aggregateDeadlineGeneration = 0;
        _didEmitTerminalTimeout = NO;

        NSString *queueName = [NSString stringWithFormat:@"com.atproto.http.io-coordinator.%p", self];
        _coordinationQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    dispatch_async(self.coordinationQueue, ^{
        [self scheduleRead];
    });
}

- (void)pause {
    dispatch_async(self.coordinationQueue, ^{
        self.isPaused = YES;
    });
}

- (void)resume {
    dispatch_async(self.coordinationQueue, ^{
        self.isPaused = NO;
        if (!self.readScheduled && !self.isClosed) {
            [self scheduleRead];
        }
    });
}

- (void)close {
    dispatch_async(self.coordinationQueue, ^{
        [self closeOnCoordinationQueue];
    });
}

- (void)scheduleRead {
    if (self.readScheduled || self.isPaused || self.isClosed) {
        return;
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if ([self aggregateHeaderDeadlineExpiredAtTime:now]) {
        [self terminateForHeaderTimeoutWithDescription:@"HTTP header deadline exceeded"];
        return;
    }

    NSUInteger queueSize = self.outputQueueSizeProvider ? self.outputQueueSizeProvider() : 0;
    if (![self.driver shouldContinueReading:self.headerStartTime
                               outputQueueSize:queueSize
                                  headerTimeout:self.aggregateHeaderTimeout
                                            now:now]) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)),
                       self.coordinationQueue, ^{
            [weakSelf scheduleRead];
        });
        return;
    }

    self.readScheduled = YES;
    [self armIdleHeaderDeadline];

    __weak typeof(self) weakSelf = self;
    [self.connection receiveWithMinimumLength:1
                                  maximumLength:UINT32_MAX
                                     completion:^(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error) {
        [weakSelf handleReceiveData:data isComplete:isComplete error:error];
    }];
}

- (void)handleReceiveData:(NSData *)data isComplete:(BOOL)isComplete error:(NSError *)error {
    dispatch_async(self.coordinationQueue, ^{
        if (self.isClosed) {
            return;
        }

        self.readScheduled = NO;
        [self invalidateIdleHeaderDeadline];

        if (error) {
            if (self.errorHandler) {
                self.errorHandler(error);
            }
            return;
        }

        if (data && data.length > 0) {
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            if (!self.isReadingRequestBody && self.headerStartTime <= 0) {
                [self beginAggregateHeaderDeadlineAtTime:now];
            }

            if ([self aggregateHeaderDeadlineExpiredAtTime:now]) {
                [self terminateForHeaderTimeoutWithDescription:@"HTTP header deadline exceeded"];
                return;
            }

            if (!self.isReadingRequestBody && [self observeHeaderTerminatorInData:data]) {
                [self finishHeaderAndBeginBody];
            }

            NSArray<NSNumber *> *events = [self.driver feedData:data];
            [self processProtocolEvents:events];
        }

        if (isComplete) {
            [self close];
            return;
        }

        if (!self.isPaused && !self.isClosed) {
            [self scheduleRead];
        }
    });
}

- (void)armIdleHeaderDeadline {
    self.idleDeadlineGeneration += 1;
    NSUInteger generation = self.idleDeadlineGeneration;
    NSTimeInterval timeout = self.idleHeaderTimeout;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                   self.coordinationQueue, ^{
        HttpConnectionIOCoordinator *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.isClosed || !strongSelf.readScheduled ||
            strongSelf.idleDeadlineGeneration != generation) {
            return;
        }
        [strongSelf terminateForHeaderTimeoutWithDescription:@"HTTP header idle deadline exceeded"];
    });
}

- (void)invalidateIdleHeaderDeadline {
    self.idleDeadlineGeneration += 1;
}

- (void)beginAggregateHeaderDeadlineAtTime:(NSTimeInterval)time {
    self.headerStartTime = time;
    self.headerTerminatorMatchLength = 0;
    self.aggregateDeadlineGeneration += 1;
    NSUInteger generation = self.aggregateDeadlineGeneration;
    NSTimeInterval timeout = self.aggregateHeaderTimeout;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                   self.coordinationQueue, ^{
        HttpConnectionIOCoordinator *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.isClosed || strongSelf.headerStartTime <= 0 ||
            strongSelf.aggregateDeadlineGeneration != generation) {
            return;
        }
        [strongSelf terminateForHeaderTimeoutWithDescription:@"HTTP header deadline exceeded"];
    });
}

- (void)completeCurrentHeader {
    self.isReadingRequestBody = NO;
    self.headerStartTime = 0;
    self.headerTerminatorMatchLength = 0;
    self.aggregateDeadlineGeneration += 1;
}

- (void)finishHeaderAndBeginBody {
    self.isReadingRequestBody = YES;
    self.headerStartTime = 0;
    self.headerTerminatorMatchLength = 0;
    self.aggregateDeadlineGeneration += 1;
}

- (BOOL)observeHeaderTerminatorInData:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    for (NSUInteger index = 0; index < data.length; index += 1) {
        uint8_t byte = bytes[index];
        switch (self.headerTerminatorMatchLength) {
            case 0:
                self.headerTerminatorMatchLength = byte == '\r' ? 1 : 0;
                break;
            case 1:
                self.headerTerminatorMatchLength = byte == '\n' ? 2 : (byte == '\r' ? 1 : 0);
                break;
            case 2:
                self.headerTerminatorMatchLength = byte == '\r' ? 3 : 0;
                break;
            case 3:
                if (byte == '\n') {
                    return YES;
                }
                self.headerTerminatorMatchLength = byte == '\r' ? 1 : 0;
                break;
            default:
                self.headerTerminatorMatchLength = 0;
                break;
        }
    }
    return NO;
}

- (BOOL)aggregateHeaderDeadlineExpiredAtTime:(NSTimeInterval)now {
    return self.headerStartTime > 0 &&
           now - self.headerStartTime >= self.aggregateHeaderTimeout;
}

- (void)terminateForHeaderTimeoutWithDescription:(NSString *)description {
    if (self.isClosed || self.didEmitTerminalTimeout) {
        return;
    }

    self.didEmitTerminalTimeout = YES;
    if (self.errorHandler) {
        self.errorHandler([NSError errorWithDomain:kHttpConnectionIOCoordinatorErrorDomain
                                               code:kHttpConnectionIOCoordinatorHeaderTimeoutError
                                           userInfo:@{NSLocalizedDescriptionKey: description}]);
    }
    [self closeOnCoordinationQueue];
}

- (void)closeOnCoordinationQueue {
    if (self.isClosed) {
        return;
    }

    self.isClosed = YES;
    self.readScheduled = NO;
    [self invalidateIdleHeaderDeadline];
    [self completeCurrentHeader];
    [self.connection cancel];
}

- (void)processProtocolEvents:(NSArray<NSNumber *> *)events {
    for (NSNumber *eventNum in events) {
        HttpProtocolEvent event = (HttpProtocolEvent)[eventNum integerValue];

        switch (event) {
            case HttpProtocolEventRequestReady: {
                HttpRequest *request = [self.driver nextDispatchableRequest];
                if (request && self.requestReadyHandler) {
                    self.requestReadyHandler(request);
                }
                [self completeCurrentHeader];
                break;
            }

            case HttpProtocolEventUpgradeRequested: {
                HttpRequest *upgradeRequest = [self.driver currentUpgradeRequest];
                if (upgradeRequest && self.upgradeHandler) {
                    self.upgradeHandler(upgradeRequest);
                }
                self.isPaused = YES;
                [self completeCurrentHeader];
                break;
            }

            case HttpProtocolEventProtocolError: {
                NSError *error = [self.driver currentParseError];
                if (self.errorHandler) {
                    self.errorHandler(error ?: [NSError errorWithDomain:@"HttpProtocol" code:-1 userInfo:nil]);
                }
                [self completeCurrentHeader];
                break;
            }

            case HttpProtocolEventConnectionClose: {
                [self close];
                break;
            }
        }
    }
}

@end
