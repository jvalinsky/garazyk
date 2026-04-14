/*!
 @file RelayMetrics.h

 @abstract Metrics collection for ATProto Relay (Sync v1.1)

 @discussion
    RelayMetrics tracks:
    - Upstream connections (PDS subscriptions)
    - Downstream connections (consumer subscriptions)
    - Events received, validated, forwarded, dropped
    - Validation failures by type
    - Sequence numbers and cursors

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@interface RelayMetrics : NSObject

+ (instancetype)sharedMetrics;

- (void)recordUpstreamConnected;
- (void)recordUpstreamDisconnected;
- (void)recordDownstreamConnected;
- (void)recordDownstreamDisconnected;

- (void)recordEventReceived;
- (void)recordEventValidated;
- (void)recordEventInvalidated:(NSString *)reason;
- (void)recordEventForwarded;
- (void)recordEventDropped;

- (void)recordMSTValidationSuccess;
- (void)recordMSTValidationFailure;
- (void)recordSignatureValidationSuccess;
- (void)recordSignatureValidationFailure;

- (void)recordSequence:(int64_t)seq;
- (void)setCurrentSequence:(int64_t)seq;

- (void)recordBackfillDuration:(NSTimeInterval)durationMs;
- (void)recordReconnectionCount;

- (NSString *)renderPrometheusMetrics;

/*!
 @method snapshotDictionary

 @abstract Returns a dictionary snapshot of all metrics for JSON API.

 @return Dictionary with all current metric values.
 */
- (NSDictionary *)snapshotDictionary;

@property (nonatomic, readonly) int64_t upstreamConnections;
@property (nonatomic, readonly) int64_t downstreamConnections;
@property (nonatomic, readonly) int64_t eventsReceived;
@property (nonatomic, readonly) int64_t eventsValidated;
@property (nonatomic, readonly) int64_t eventsInvalidated;
@property (nonatomic, readonly) int64_t eventsForwarded;
@property (nonatomic, readonly) int64_t eventsDropped;
@property (nonatomic, readonly) int64_t mstValidationSuccess;
@property (nonatomic, readonly) int64_t mstValidationFailure;
@property (nonatomic, readonly) int64_t signatureValidationSuccess;
@property (nonatomic, readonly) int64_t signatureValidationFailure;
@property (nonatomic, readonly) int64_t currentSequence;
@property (nonatomic, readonly) int64_t reconnectionCount;

@end

NS_ASSUME_NONNULL_END