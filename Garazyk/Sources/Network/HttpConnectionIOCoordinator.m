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
#import "Network/PDSNetworkTransport.h"
#import "Compat/PDSTypes.h"

@interface HttpConnectionIOCoordinator ()
@property (nonatomic, strong) id<PDSNetworkConnection> connection;
@property (nonatomic, strong) HttpProtocolDriver *driver;
@property (nonatomic, strong) HttpResponseSender *sender;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t coordinationQueue;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, assign) BOOL readScheduled;
@property (nonatomic, assign) BOOL isClosed;
@property (nonatomic, assign) NSTimeInterval headerStartTime;
@end

static const NSTimeInterval kHttpHeaderTimeout = 30.0;

@implementation HttpConnectionIOCoordinator

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithConnection:(id<PDSNetworkConnection>)connection
                           protocol:(HttpProtocolDriver *)driver
                       responseSender:(HttpResponseSender *)sender {
    self = [super init];
    if (self) {
        _connection = connection;
        _driver = driver;
        _sender = sender;
        _isPaused = NO;
        _readScheduled = NO;
        _isClosed = NO;
        _headerStartTime = [NSDate timeIntervalSinceReferenceDate];

        NSString *queueName = [NSString stringWithFormat:@"com.pds.http.io-coordinator.%p", self];
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
        self.isClosed = YES;
        self.readScheduled = NO;
    });
}

- (void)scheduleRead {
    if (self.readScheduled || self.isPaused || self.isClosed) {
        return;
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.headerStartTime > kHttpHeaderTimeout) {
        if (self.errorHandler) {
            self.errorHandler([NSError errorWithDomain:@"HttpConnectionIOCoordinator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Read timeout"}]);
        }
        [self close];
        return;
    }

    NSUInteger queueSize = self.outputQueueSizeProvider ? self.outputQueueSizeProvider() : 0;
    if (![self.driver shouldContinueReading:self.headerStartTime
                               outputQueueSize:queueSize
                                  headerTimeout:kHttpHeaderTimeout
                                            now:now]) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)),
                       self.coordinationQueue, ^{
            [weakSelf scheduleRead];
        });
        return;
    }

    self.readScheduled = YES;

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
        self.headerStartTime = [NSDate timeIntervalSinceReferenceDate];

        if (error) {
            if (self.errorHandler) {
                self.errorHandler(error);
            }
            return;
        }

        if (data && data.length > 0) {
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

- (void)processProtocolEvents:(NSArray<NSNumber *> *)events {
    for (NSNumber *eventNum in events) {
        HttpProtocolEvent event = (HttpProtocolEvent)[eventNum integerValue];

        switch (event) {
            case HttpProtocolEventRequestReady: {
                HttpRequest *request = [self.driver nextDispatchableRequest];
                if (request && self.requestReadyHandler) {
                    self.requestReadyHandler(request);
                }
                break;
            }

            case HttpProtocolEventUpgradeRequested: {
                HttpRequest *upgradeRequest = [self.driver currentUpgradeRequest];
                if (upgradeRequest && self.upgradeHandler) {
                    self.upgradeHandler(upgradeRequest);
                }
                self.isPaused = YES;
                break;
            }

            case HttpProtocolEventProtocolError: {
                NSError *error = [self.driver currentParseError];
                if (self.errorHandler) {
                    self.errorHandler(error ?: [NSError errorWithDomain:@"HttpProtocol" code:-1 userInfo:nil]);
                }
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
