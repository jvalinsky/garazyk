// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayIngressAdmission.h"
#import "Sync/Relay/RelayIngressConfiguration.h"
#import "Sync/Relay/RelayMetrics.h"

NSString * const RelayIngressAdmissionErrorDomain = @"com.atproto.relay.ingress.admission";

static void *RelayIngressAdmissionQueueKey = &RelayIngressAdmissionQueueKey;

@interface ATProtoRelayIngressAdmissionToken ()
@property (nonatomic, assign, readwrite) uint64_t encodedBytes;
@property (nonatomic, strong, readwrite) NSDate *acceptedAt;
@property (nonatomic, copy, readwrite) NSString *upstreamURL;
@property (nonatomic, assign, readwrite) int64_t sequence;
@property (nonatomic, assign, readwrite) BOOL released;
- (instancetype)initWithEncodedBytes:(uint64_t)bytes
                          upstreamURL:(NSString *)upstreamURL
                             sequence:(int64_t)sequence NS_DESIGNATED_INITIALIZER;
@end

@implementation ATProtoRelayIngressAdmissionToken

- (instancetype)initWithEncodedBytes:(uint64_t)bytes
                          upstreamURL:(NSString *)upstreamURL
                             sequence:(int64_t)sequence {
    self = [super init];
    if (self) {
        _encodedBytes = bytes;
        _acceptedAt = [NSDate date];
        _upstreamURL = [upstreamURL copy];
        _sequence = sequence;
    }
    return self;
}

@end

@interface ATProtoRelayIngressAdmission ()
@property (nonatomic, strong) ATProtoRelayIngressConfiguration *configuration;
@property (nonatomic, weak, nullable) ATProtoRelayMetrics *metrics;
@end

@implementation ATProtoRelayIngressAdmission {
    dispatch_queue_t _admissionQueue;
    dispatch_queue_t _watermarkQueue;
    NSUInteger _accountedEventCount;
    uint64_t _accountedByteCount;
    NSUInteger _peakAccountedEvents;
    uint64_t _peakAccountedBytes;
    NSDate *_oldestAcceptedAt;
    BOOL _highWatermarkActive;
    uint64_t _admittedTotal;
    uint64_t _rejectedTotal;
    uint64_t _cancelledTotal;
}

- (instancetype)initWithConfiguration:(ATProtoRelayIngressConfiguration *)configuration
                              metrics:(ATProtoRelayMetrics *)metrics {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _metrics = metrics;
        _admissionQueue = dispatch_queue_create("com.atproto.relay.ingress.admission",
                                                DISPATCH_QUEUE_SERIAL);
        _watermarkQueue = dispatch_queue_create("com.atproto.relay.ingress.watermark",
                                                DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_admissionQueue,
                                    RelayIngressAdmissionQueueKey,
                                    (__bridge void *)self,
                                    NULL);
    }
    return self;
}

- (void)performOnAdmissionQueue:(dispatch_block_t)block {
    if (dispatch_get_specific(RelayIngressAdmissionQueueKey) == (__bridge void *)self) {
        block();
    } else {
        dispatch_sync(_admissionQueue, block);
    }
}

- (void)updatePeaksLocked {
    if (_accountedEventCount > _peakAccountedEvents) {
        _peakAccountedEvents = _accountedEventCount;
    }
    if (_accountedByteCount > _peakAccountedBytes) {
        _peakAccountedBytes = _accountedByteCount;
    }
}

- (void)evaluateWatermarksLocked {
    BOOL aboveHigh = _accountedEventCount >= self.configuration.highEventWatermark ||
        _accountedByteCount >= self.configuration.highByteWatermark;
    BOOL belowLow = _accountedEventCount <= self.configuration.lowEventWatermark &&
        _accountedByteCount <= self.configuration.lowByteWatermark;

    if (aboveHigh && !_highWatermarkActive) {
        _highWatermarkActive = YES;
        RelayIngressWatermarkHandler handler = [self.onHighWatermark copy];
        if (handler) {
            dispatch_async(_watermarkQueue, handler);
        }
        [self.metrics recordIngressHighWatermark];
    } else if (belowLow && _highWatermarkActive) {
        _highWatermarkActive = NO;
        RelayIngressWatermarkHandler handler = [self.onLowWatermark copy];
        if (handler) {
            dispatch_async(_watermarkQueue, handler);
        }
        [self.metrics recordIngressLowWatermark];
    }

    // Push current oldest-age metric
    NSTimeInterval ageMs = 0;
    if (_oldestAcceptedAt) {
        ageMs = [[NSDate date] timeIntervalSinceDate:_oldestAcceptedAt] * 1000.0;
    }
    [self.metrics recordIngressOldestAgeMs:ageMs];
}

- (nullable ATProtoRelayIngressAdmissionToken *)admitEncodedBytes:(uint64_t)bytes
                                                       upstreamURL:(NSString *)upstreamURL
                                                          sequence:(int64_t)sequence
                                                             error:(NSError * _Nullable * _Nullable)error {
    if (bytes == 0) {
        bytes = 1;
    }
    __block ATProtoRelayIngressAdmissionToken *token = nil;
    __block NSError *localError = nil;
    [self performOnAdmissionQueue:^{
        if (_accountedEventCount >= self.configuration.maxEventCount ||
            _accountedByteCount + bytes > self.configuration.maxByteCount) {
            _rejectedTotal++;
            [self.metrics recordIngressRejected:@"backlog-full"];
            localError = [NSError errorWithDomain:RelayIngressAdmissionErrorDomain
                                             code:RelayIngressAdmissionErrorCodeRejected
                                         userInfo:@{NSLocalizedDescriptionKey: @"Ingress backlog at high watermark"}];
            return;
        }

        token = [[ATProtoRelayIngressAdmissionToken alloc] initWithEncodedBytes:bytes
                                                                    upstreamURL:upstreamURL ?: @""
                                                                       sequence:sequence];

        _accountedEventCount++;
        _accountedByteCount += bytes;
        _admittedTotal++;
        if (!_oldestAcceptedAt) {
            _oldestAcceptedAt = token.acceptedAt;
        }
        [self updatePeaksLocked];
        [self.metrics recordIngressAdmittedBytes:bytes];
        [self evaluateWatermarksLocked];
    }];
    if (error) {
        *error = localError;
    }
    return token;
}

- (BOOL)releaseToken:(ATProtoRelayIngressAdmissionToken *)token
              reason:(RelayIngressReleaseReason)reason
               error:(NSError * _Nullable * _Nullable)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    [self performOnAdmissionQueue:^{
        if (!token || token.released) {
            [self.metrics recordIngressAccountingFailure:@"double-release"];
            localError = [NSError errorWithDomain:RelayIngressAdmissionErrorDomain
                                             code:RelayIngressAdmissionErrorCodeDoubleRelease
                                         userInfo:@{NSLocalizedDescriptionKey: @"Ingress token released twice"}];
            return;
        }
        if (_accountedEventCount == 0 ||
            _accountedByteCount < token.encodedBytes) {
            [self.metrics recordIngressAccountingFailure:@"underflow"];
            localError = [NSError errorWithDomain:RelayIngressAdmissionErrorDomain
                                             code:RelayIngressAdmissionErrorCodeUnderflow
                                         userInfo:@{NSLocalizedDescriptionKey: @"Ingress accounting underflow"}];
            return;
        }

        token.released = YES;
        _accountedEventCount--;
        _accountedByteCount -= token.encodedBytes;
        if (_accountedEventCount == 0) {
            _oldestAcceptedAt = nil;
        }
        switch (reason) {
            case RelayIngressReleaseReasonProcessed:
                [self.metrics recordIngressReleasedBytes:token.encodedBytes
                                                  reason:reason];
                break;
            case RelayIngressReleaseReasonRejected:
            case RelayIngressReleaseReasonDecodeFailure:
                [self.metrics recordIngressReleasedBytes:token.encodedBytes reason:reason];
                [self.metrics recordIngressRejected:reason == RelayIngressReleaseReasonDecodeFailure ?
                 @"decode-failure" : @"validation-rejected"];
                break;
            case RelayIngressReleaseReasonCancelled:
            case RelayIngressReleaseReasonDisconnect:
            case RelayIngressReleaseReasonShutdown:
                _cancelledTotal++;
                [self.metrics recordIngressReleasedBytes:token.encodedBytes reason:reason];
                break;
        }
        [self evaluateWatermarksLocked];
        success = YES;
    }];
    if (error) {
        *error = localError;
    }
    return success;
}

- (NSUInteger)currentEventCount {
    __block NSUInteger value = 0;
    [self performOnAdmissionQueue:^{ value = _accountedEventCount; }];
    return value;
}

- (uint64_t)currentByteCount {
    __block uint64_t value = 0;
    [self performOnAdmissionQueue:^{ value = _accountedByteCount; }];
    return value;
}

- (NSUInteger)peakEventCount {
    __block NSUInteger value = 0;
    [self performOnAdmissionQueue:^{ value = _peakAccountedEvents; }];
    return value;
}

- (uint64_t)peakByteCount {
    __block uint64_t value = 0;
    [self performOnAdmissionQueue:^{ value = _peakAccountedBytes; }];
    return value;
}

- (NSTimeInterval)oldestAcceptedAge {
    __block NSTimeInterval age = 0;
    [self performOnAdmissionQueue:^{
        if (_oldestAcceptedAt) {
            age = [[NSDate date] timeIntervalSinceDate:_oldestAcceptedAt];
        }
    }];
    return age;
}

- (BOOL)isAboveHighWatermark {
    __block BOOL value = NO;
    [self performOnAdmissionQueue:^{ value = _highWatermarkActive; }];
    return value;
}

- (BOOL)isBelowLowWatermark {
    __block BOOL value = NO;
    [self performOnAdmissionQueue:^{
        value = !_highWatermarkActive &&
            _accountedEventCount <= self.configuration.lowEventWatermark &&
            _accountedByteCount <= self.configuration.lowByteWatermark;
    }];
    return value;
}

- (NSDictionary<NSString *, NSNumber *> *)snapshotDictionary {
    __block NSDictionary<NSString *, NSNumber *> *snapshot = nil;
    [self performOnAdmissionQueue:^{
        snapshot = @{
            @"max_event_count": @(self.configuration.maxEventCount),
            @"max_byte_count": @(self.configuration.maxByteCount),
            @"low_event_watermark": @(self.configuration.lowEventWatermark),
            @"low_byte_watermark": @(self.configuration.lowByteWatermark),
            @"high_event_watermark": @(self.configuration.highEventWatermark),
            @"high_byte_watermark": @(self.configuration.highByteWatermark),
            @"current_event_count": @(_accountedEventCount),
            @"current_byte_count": @(_accountedByteCount),
            @"peak_event_count": @(_peakAccountedEvents),
            @"peak_byte_count": @(_peakAccountedBytes),
            @"admitted_total": @(_admittedTotal),
            @"rejected_total": @(_rejectedTotal),
            @"cancelled_total": @(_cancelledTotal),
            @"high_watermark_active": @(_highWatermarkActive),
            @"oldest_age_ms": @((NSUInteger)(_oldestAcceptedAt ?
                [[NSDate date] timeIntervalSinceDate:_oldestAcceptedAt] * 1000.0 : 0.0)),
        };
    }];
    return snapshot;
}

- (void)waitForDrainForTesting {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        if ([self currentEventCount] == 0 && [self currentByteCount] == 0) {
            return;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

@end
