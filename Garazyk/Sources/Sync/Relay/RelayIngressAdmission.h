// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayIngressAdmission.h

 @abstract Single global admission controller for relay ingress backlog.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@class ATProtoRelayIngressAdmission;
@class ATProtoRelayIngressConfiguration;
@class ATProtoRelayMetrics;

extern NSString * const RelayIngressAdmissionErrorDomain;

typedef NS_ENUM(NSInteger, RelayIngressAdmissionErrorCode) {
    RelayIngressAdmissionErrorCodeRejected = 1,
    RelayIngressAdmissionErrorCodeDoubleRelease = 2,
    RelayIngressAdmissionErrorCodeUnderflow = 3,
};

typedef NS_ENUM(NSInteger, RelayIngressReleaseReason) {
    RelayIngressReleaseReasonProcessed = 0,
    RelayIngressReleaseReasonRejected,
    RelayIngressReleaseReasonCancelled,
    RelayIngressReleaseReasonDecodeFailure,
    RelayIngressReleaseReasonDisconnect,
    RelayIngressReleaseReasonShutdown,
};

typedef void (^RelayIngressWatermarkHandler)(void);

/**
 * @abstract Ownership token released exactly once after admission.
 */
@interface ATProtoRelayIngressAdmissionToken : NSObject
@property (nonatomic, assign, readonly) uint64_t encodedBytes;
@property (nonatomic, strong, readonly) NSDate *acceptedAt;
@property (nonatomic, copy, readonly) NSString *upstreamURL;
@property (nonatomic, assign, readonly) int64_t sequence;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/**
 * @abstract Queue-confined byte/count admission with high/low watermarks.
 */
@interface ATProtoRelayIngressAdmission : NSObject

@property (nonatomic, copy, nullable) RelayIngressWatermarkHandler onHighWatermark;
@property (nonatomic, copy, nullable) RelayIngressWatermarkHandler onLowWatermark;

- (instancetype)initWithConfiguration:(ATProtoRelayIngressConfiguration *)configuration
                              metrics:(nullable ATProtoRelayMetrics *)metrics NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * @abstract Reserves encoded bytes in the global backlog.
 */
- (nullable ATProtoRelayIngressAdmissionToken *)admitEncodedBytes:(uint64_t)bytes
                                                       upstreamURL:(NSString *)upstreamURL
                                                          sequence:(int64_t)sequence
                                                             error:(NSError * _Nullable * _Nullable)error;

/**
 * @abstract Releases a previously admitted token exactly once.
 */
- (BOOL)releaseToken:(ATProtoRelayIngressAdmissionToken *)token
              reason:(RelayIngressReleaseReason)reason
               error:(NSError * _Nullable * _Nullable)error;

- (NSUInteger)currentEventCount;
- (uint64_t)currentByteCount;
- (NSUInteger)peakEventCount;
- (uint64_t)peakByteCount;
- (NSTimeInterval)oldestAcceptedAge;
- (BOOL)isAboveHighWatermark;
- (BOOL)isBelowLowWatermark;

- (NSDictionary<NSString *, NSNumber *> *)snapshotDictionary;

/** Blocks until all admitted tokens are released. For tests only. */
- (void)waitForDrainForTesting;

@end

NS_ASSUME_NONNULL_END
