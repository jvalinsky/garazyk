// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayIngressAdmission.h"
#import "Sync/Relay/RelayIngressConfiguration.h"
#import "Sync/Relay/RelayIngressPipeline.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Firehose/Firehose.h"

@interface RelayIngressAdmissionTests : XCTestCase
@end

@implementation RelayIngressAdmissionTests

- (ATProtoRelayIngressConfiguration *)tinyConfiguration {
    return [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:4
                                                               maxByteCount:256
                                                         lowEventWatermark:1
                                                           lowByteWatermark:64
                                                        highEventWatermark:2
                                                          highByteWatermark:160
                                                                 shardCount:2
                                                      boundedIngressEnabled:YES
                                                                      error:NULL];
}

- (void)testConfigurationRejectsInvalidWatermarks {
    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:10
                                                            maxByteCount:100
                                                      lowEventWatermark:10
                                                        lowByteWatermark:50
                                                       highEventWatermark:9
                                                         highByteWatermark:75
                                                              shardCount:2
                                                   boundedIngressEnabled:YES
                                                                   error:&error];
    XCTAssertNil(config);
    XCTAssertNotNil(error);
}

- (void)testAdmitAndReleaseReturnsToZero {
    ATProtoRelayIngressAdmission *admission =
        [[ATProtoRelayIngressAdmission alloc] initWithConfiguration:[self tinyConfiguration]
                                                          metrics:[ATProtoRelayMetrics sharedMetrics]];
    NSError *error = nil;
    ATProtoRelayIngressAdmissionToken *token =
        [admission admitEncodedBytes:32 upstreamURL:@"https://pds.example" sequence:1 error:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);
    XCTAssertEqual(admission.currentEventCount, 1);
    XCTAssertEqual(admission.currentByteCount, 32);

    XCTAssertTrue([admission releaseToken:token reason:RelayIngressReleaseReasonProcessed error:&error]);
    XCTAssertNil(error);
    [admission waitForDrainForTesting];
    XCTAssertEqual(admission.currentEventCount, 0);
    XCTAssertEqual(admission.currentByteCount, 0);
}

- (void)testHighWatermarkRejectsAdditionalAdmission {
    ATProtoRelayIngressConfiguration *config = [self tinyConfiguration];
    ATProtoRelayIngressAdmission *admission =
        [[ATProtoRelayIngressAdmission alloc] initWithConfiguration:config
                                                          metrics:[ATProtoRelayMetrics sharedMetrics]];
    NSMutableArray<ATProtoRelayIngressAdmissionToken *> *tokens = [NSMutableArray array];
    for (NSUInteger index = 0; index < config.maxEventCount; index++) {
        ATProtoRelayIngressAdmissionToken *token =
            [admission admitEncodedBytes:16 upstreamURL:@"https://pds.example" sequence:(int64_t)index error:nil];
        XCTAssertNotNil(token);
        [tokens addObject:token];
    }
    NSError *rejectError = nil;
    ATProtoRelayIngressAdmissionToken *rejected =
        [admission admitEncodedBytes:16 upstreamURL:@"https://pds.example" sequence:99 error:&rejectError];
    XCTAssertNil(rejected);
    XCTAssertEqual(rejectError.code, RelayIngressAdmissionErrorCodeRejected);
    XCTAssertTrue(admission.isAboveHighWatermark);

    for (ATProtoRelayIngressAdmissionToken *token in tokens) {
        XCTAssertTrue([admission releaseToken:token reason:RelayIngressReleaseReasonProcessed error:nil]);
    }
    [admission waitForDrainForTesting];
    XCTAssertEqual(admission.currentEventCount, 0);
}

- (void)testHighByteWatermarkFiresWithHeadroomBelowMaxEvenWhenEventExceedsResidualCapacity {
    // Regression test for finding F3: evaluateWatermarksLocked used to compare accounted bytes
    // against maxByteCount (the same field admitEncodedBytes: uses for its hard-cap rejection)
    // instead of a distinct highByteWatermark. That meant the byte high watermark could only
    // become true at the exact max boundary -- and if an incoming event's size exceeded the
    // residual headroom below max, admitEncodedBytes: rejected it outright before accountedBytes
    // ever reached that boundary, so the pause signal never fired. With a genuinely distinct
    // high watermark sitting below max, pause must fire well before the hard cap engages, even
    // for oversized events.
    NSError *configError = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:100
                                                            maxByteCount:1000
                                                      lowEventWatermark:1
                                                        lowByteWatermark:200
                                                       highEventWatermark:50
                                                         highByteWatermark:700
                                                              shardCount:2
                                                   boundedIngressEnabled:YES
                                                                   error:&configError];
    XCTAssertNotNil(config);
    XCTAssertNil(configError);

    // The event size (350) is deliberately larger than the gap between the high watermark and
    // the hard cap (1000 - 700 = 300 residual headroom), reproducing the exact shape of the bug:
    // once accounted bytes reach the high watermark, one more event of this size cannot be
    // admitted without breaching maxByteCount.
    const uint64_t eventBytes = 350;
    XCTAssertGreaterThan(eventBytes, config.maxByteCount - config.highByteWatermark);

    XCTestExpectation *pause =
        [self expectationWithDescription:@"high watermark fires with headroom still below max"];
    ATProtoRelayIngressAdmission *admission =
        [[ATProtoRelayIngressAdmission alloc] initWithConfiguration:config
                                                            metrics:[[ATProtoRelayMetrics alloc] init]];
    admission.onHighWatermark = ^{ [pause fulfill]; };

    NSError *error = nil;
    ATProtoRelayIngressAdmissionToken *first =
        [admission admitEncodedBytes:eventBytes upstreamURL:@"https://pds.example" sequence:1 error:&error];
    XCTAssertNotNil(first);
    XCTAssertNil(error);
    XCTAssertFalse(admission.isAboveHighWatermark);

    ATProtoRelayIngressAdmissionToken *second =
        [admission admitEncodedBytes:eventBytes upstreamURL:@"https://pds.example" sequence:2 error:&error];
    XCTAssertNotNil(second);
    XCTAssertNil(error);

    [self waitForExpectations:@[pause] timeout:2.0];
    XCTAssertTrue(admission.isAboveHighWatermark);
    XCTAssertEqual(admission.currentByteCount, 2 * eventBytes);
    // Real headroom remains below the hard cap when the pause fires -- this is the bug fix.
    XCTAssertLessThan(admission.currentByteCount, config.maxByteCount);
    XCTAssertGreaterThan(config.maxByteCount - admission.currentByteCount, (uint64_t)0);

    // A third, same-sized event would breach the hard cap and is correctly rejected -- but that
    // rejection is now genuinely exceptional: the pause signal already fired 300 bytes of
    // headroom earlier, giving RelayClient.pauseReading a chance to stop the upstream first.
    NSError *rejectError = nil;
    ATProtoRelayIngressAdmissionToken *rejected =
        [admission admitEncodedBytes:eventBytes upstreamURL:@"https://pds.example" sequence:3 error:&rejectError];
    XCTAssertNil(rejected);
    XCTAssertEqual(rejectError.code, RelayIngressAdmissionErrorCodeRejected);

    XCTAssertTrue([admission releaseToken:first reason:RelayIngressReleaseReasonProcessed error:nil]);
    XCTAssertTrue([admission releaseToken:second reason:RelayIngressReleaseReasonProcessed error:nil]);
    [admission waitForDrainForTesting];
}

- (void)testDoubleReleaseIsRejected {
    ATProtoRelayIngressAdmission *admission =
        [[ATProtoRelayIngressAdmission alloc] initWithConfiguration:[self tinyConfiguration]
                                                          metrics:[ATProtoRelayMetrics sharedMetrics]];
    ATProtoRelayIngressAdmissionToken *token =
        [admission admitEncodedBytes:32 upstreamURL:@"https://pds.example" sequence:1 error:nil];
    XCTAssertTrue([admission releaseToken:token reason:RelayIngressReleaseReasonProcessed error:nil]);
    NSError *doubleReleaseError = nil;
    XCTAssertFalse([admission releaseToken:token reason:RelayIngressReleaseReasonProcessed error:&doubleReleaseError]);
    XCTAssertEqual(doubleReleaseError.code, RelayIngressAdmissionErrorCodeDoubleRelease);
}

- (void)testPipelinePreservesSameDIDOrdering {
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:32
                                                            maxByteCount:4096
                                                      lowEventWatermark:16
                                                        lowByteWatermark:2048
                                                       highEventWatermark:24
                                                         highByteWatermark:3072
                                                              shardCount:4
                                                   boundedIngressEnabled:YES
                                                                   error:NULL];
    dispatch_semaphore_t processed = dispatch_semaphore_create(0);
    __block NSMutableArray<NSNumber *> *order = [NSMutableArray array];
    ATProtoRelayIngressPipeline *pipeline =
        [[ATProtoRelayIngressPipeline alloc] initWithConfiguration:config
                                                           metrics:[ATProtoRelayMetrics sharedMetrics]
                                                      processBlock:^(id event,
                                                                     NSString *upstreamURL,
                                                                     int64_t sequence,
                                                                     RelayIngressProcessCompletion completion) {
            (void)event;
            (void)upstreamURL;
            @synchronized (order) {
                [order addObject:@(sequence)];
            }
            completion(RelayIngressReleaseReasonProcessed);
            dispatch_semaphore_signal(processed);
        }];

    for (int64_t seq = 1; seq <= 5; seq++) {
        ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:@"did:plc:alice"];
        event.seq = seq;
        event.wireFrameLength = 64;
        XCTAssertTrue([pipeline submitEvent:event
                               encodedBytes:64
                                orderingKey:@"did:plc:alice"
                               fromUpstream:@"https://pds.example"
                                   sequence:seq
                                      error:nil]);
    }

    for (int64_t seq = 1; seq <= 5; seq++) {
        (void)dispatch_semaphore_wait(processed, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
    }
    [pipeline waitForDrainForTesting];

    NSArray<NSNumber *> *snapshot = nil;
    @synchronized (order) {
        snapshot = [order copy];
    }
    XCTAssertEqualObjects(snapshot, (@[@1, @2, @3, @4, @5]));
}

#pragma mark - Stress case 7: same DID alternates across two upstreams

// Stress case 7 (phase prompt): same-DID ordering is a same-*shard*
// guarantee -- shardIndexForOrderingKey: hashes the ordering key (the
// repo/DID), independent of which upstream submitted the event -- so this
// must hold structurally even when consecutive events for one DID arrive
// interleaved from two different upstreams, exactly as would happen if a
// repo migrated PDS mid-stream or two relays both forwarded the same
// account's commits. Same shape as testPipelinePreservesSameDIDOrdering
// above, but upstreamURL alternates per submission while orderingKey stays
// fixed at the shared DID.
- (void)testPipelinePreservesSameDIDOrderingAcrossAlternatingUpstreams {
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:32
                                                            maxByteCount:4096
                                                      lowEventWatermark:16
                                                        lowByteWatermark:2048
                                                       highEventWatermark:24
                                                         highByteWatermark:3072
                                                              shardCount:4
                                                   boundedIngressEnabled:YES
                                                                   error:NULL];
    dispatch_semaphore_t processed = dispatch_semaphore_create(0);
    __block NSMutableArray<NSNumber *> *order = [NSMutableArray array];
    __block NSMutableArray<NSString *> *upstreamOrder = [NSMutableArray array];
    ATProtoRelayIngressPipeline *pipeline =
        [[ATProtoRelayIngressPipeline alloc] initWithConfiguration:config
                                                           metrics:[ATProtoRelayMetrics sharedMetrics]
                                                      processBlock:^(id event,
                                                                     NSString *upstreamURL,
                                                                     int64_t sequence,
                                                                     RelayIngressProcessCompletion completion) {
            (void)event;
            @synchronized (order) {
                [order addObject:@(sequence)];
                [upstreamOrder addObject:upstreamURL];
            }
            completion(RelayIngressReleaseReasonProcessed);
            dispatch_semaphore_signal(processed);
        }];

    NSString *did = @"did:plc:alternating";
    NSArray<NSString *> *upstreams = @[@"https://pds-a.example", @"https://pds-b.example"];
    for (int64_t seq = 1; seq <= 6; seq++) {
        NSString *upstreamURL = upstreams[(NSUInteger)((seq - 1) % 2)];
        ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:did];
        event.seq = seq;
        event.wireFrameLength = 64;
        XCTAssertTrue([pipeline submitEvent:event
                               encodedBytes:64
                                orderingKey:did
                               fromUpstream:upstreamURL
                                   sequence:seq
                                      error:nil]);
    }

    for (int64_t seq = 1; seq <= 6; seq++) {
        (void)dispatch_semaphore_wait(processed, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
    }
    [pipeline waitForDrainForTesting];

    NSArray<NSNumber *> *sequenceSnapshot = nil;
    NSArray<NSString *> *upstreamSnapshot = nil;
    @synchronized (order) {
        sequenceSnapshot = [order copy];
        upstreamSnapshot = [upstreamOrder copy];
    }
    XCTAssertEqualObjects(sequenceSnapshot, (@[@1, @2, @3, @4, @5, @6]));
    XCTAssertEqualObjects(upstreamSnapshot,
                          (@[upstreams[0], upstreams[1], upstreams[0], upstreams[1], upstreams[0], upstreams[1]]));
    XCTAssertEqual(pipeline.admission.currentEventCount, 0);
    XCTAssertEqual(pipeline.admission.currentByteCount, (uint64_t)0);
}

- (void)testPipelineAllowsConcurrentDistinctDIDs {
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:32
                                                            maxByteCount:4096
                                                      lowEventWatermark:16
                                                        lowByteWatermark:2048
                                                       highEventWatermark:24
                                                         highByteWatermark:3072
                                                              shardCount:4
                                                   boundedIngressEnabled:YES
                                                                   error:NULL];
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    dispatch_semaphore_t entered = dispatch_semaphore_create(0);
    ATProtoRelayIngressPipeline *pipeline =
        [[ATProtoRelayIngressPipeline alloc] initWithConfiguration:config
                                                           metrics:[[ATProtoRelayMetrics alloc] init]
                                                      processBlock:^(id event,
                                                                     NSString *upstreamURL,
                                                                     int64_t sequence,
                                                                     RelayIngressProcessCompletion completion) {
            (void)event;
            (void)upstreamURL;
            (void)sequence;
            dispatch_semaphore_signal(entered);
            dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
            completion(RelayIngressReleaseReasonProcessed);
        }];
    for (int64_t seq = 1; seq <= 2; seq++) {
        // "did:plc:one"/"did:plc:two" collide under NSString.hash % shardCount:4 on this
        // runtime (both land on shard 1), which serializes them onto the same shard queue and
        // deadlocks this test against its own two-slot "entered" semaphore. "alpha"/"beta" land
        // on shards 3 and 0 respectively -- verified distinct, not just assumed.
        NSString *did = seq == 1 ? @"did:plc:alpha" : @"did:plc:beta";
        ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:did];
        event.seq = seq;
        event.wireFrameLength = 16;
        XCTAssertTrue([pipeline submitEvent:event
                               encodedBytes:16
                                orderingKey:did
                               fromUpstream:@"https://pds.example"
                                   sequence:seq
                                      error:nil]);
    }
    XCTAssertEqual(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0);
    XCTAssertEqual(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0);
    dispatch_semaphore_signal(gate);
    dispatch_semaphore_signal(gate);
    [pipeline waitForDrainForTesting];
    XCTAssertEqual(pipeline.admission.currentEventCount, 0);
}

- (void)testPipelineShutdownDrainsAccounting {
    ATProtoRelayIngressConfiguration *config = [self tinyConfiguration];
    dispatch_semaphore_t started = dispatch_semaphore_create(0);
    dispatch_semaphore_t allowFinish = dispatch_semaphore_create(0);
    dispatch_semaphore_t shutdownDone = dispatch_semaphore_create(0);
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];
    ATProtoRelayIngressPipeline *pipeline =
        [[ATProtoRelayIngressPipeline alloc] initWithConfiguration:config
                                                           metrics:metrics
                                                      processBlock:^(id event,
                                                                     NSString *upstreamURL,
                                                                     int64_t sequence,
                                                                     RelayIngressProcessCompletion completion) {
            (void)event;
            (void)upstreamURL;
            (void)sequence;
            dispatch_semaphore_signal(started);
            dispatch_semaphore_wait(allowFinish, DISPATCH_TIME_FOREVER);
            completion(RelayIngressReleaseReasonProcessed);
        }];
    ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:@"did:plc:bob"];
    event.seq = 1;
    event.wireFrameLength = 32;
    XCTAssertTrue([pipeline submitEvent:event
                           encodedBytes:32
                            orderingKey:@"did:plc:bob"
                           fromUpstream:@"https://pds.example"
                               sequence:1
                                  error:nil]);
    XCTAssertEqual(dispatch_semaphore_wait(started, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0);

    __block BOOL shutdownDrained = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [pipeline shutdownWithCompletion:^(BOOL drained) {
            shutdownDrained = drained;
            dispatch_semaphore_signal(shutdownDone);
        }];
    });
    dispatch_semaphore_signal(allowFinish);
    XCTAssertEqual(dispatch_semaphore_wait(shutdownDone, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0);
    XCTAssertTrue(shutdownDrained);
    XCTAssertEqual(pipeline.admission.currentEventCount, 0);
    XCTAssertEqual(pipeline.admission.currentByteCount, 0);
}

// Regression test for R9/F14: shutdownWithCompletion: used to call
// -waitForDrainForTesting (a 5s busy-wait) and then unconditionally invoke
// completion() regardless of whether the drain actually finished, so a
// caller could not distinguish a clean shutdown from one that timed out
// with work still in flight. This drives a work item whose completion never
// fires, so the drain is guaranteed to hit the timeout, and asserts the
// completion block reports drained==NO rather than silently succeeding.
- (void)testPipelineShutdownReportsTimeoutWhenWorkNeverCompletes {
    ATProtoRelayIngressConfiguration *config = [self tinyConfiguration];
    dispatch_semaphore_t started = dispatch_semaphore_create(0);
    dispatch_semaphore_t shutdownDone = dispatch_semaphore_create(0);
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];
    ATProtoRelayIngressPipeline *pipeline =
        [[ATProtoRelayIngressPipeline alloc] initWithConfiguration:config
                                                           metrics:metrics
                                                      processBlock:^(id event,
                                                                     NSString *upstreamURL,
                                                                     int64_t sequence,
                                                                     RelayIngressProcessCompletion completion) {
            (void)event;
            (void)upstreamURL;
            (void)sequence;
            (void)completion;
            // Deliberately never calls completion(), so the work item never
            // leaves the drain group and shutdown must time out.
            dispatch_semaphore_signal(started);
        }];
    ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:@"did:plc:stuck"];
    event.seq = 1;
    event.wireFrameLength = 32;
    XCTAssertTrue([pipeline submitEvent:event
                           encodedBytes:32
                            orderingKey:@"did:plc:stuck"
                           fromUpstream:@"https://pds.example"
                               sequence:1
                                  error:nil]);
    XCTAssertEqual(dispatch_semaphore_wait(started, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0);

    __block BOOL shutdownDrained = YES;
    NSDate *shutdownStartedAt = [NSDate date];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [pipeline shutdownWithCompletion:^(BOOL drained) {
            shutdownDrained = drained;
            dispatch_semaphore_signal(shutdownDone);
        }];
    });
    // The drain bound is 5s; give it generous headroom here.
    XCTAssertEqual(dispatch_semaphore_wait(shutdownDone, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC))), 0);
    XCTAssertFalse(shutdownDrained);
    XCTAssertGreaterThanOrEqual([[NSDate date] timeIntervalSinceDate:shutdownStartedAt], 4.5);
}

#pragma mark - Stress case 5: shutdown with every shard occupied and queued

// Finds one ordering key per shard index, by replicating the exact routing
// RelayIngressPipeline itself uses (shardIndexForOrderingKey: is
// orderingKey.hash % shardCount) against candidate DID strings until every
// shard 0..shardCount-1 has a covering key. Deterministic within a single
// test run/process since NSString.hash is stable for the lifetime of the
// run; only the specific keys discovered are unspecified, not the guarantee
// that all shards get covered.
- (NSArray<NSString *> *)orderingKeysCoveringEachShard:(NSUInteger)shardCount {
    NSMutableDictionary<NSNumber *, NSString *> *byShard = [NSMutableDictionary dictionary];
    NSUInteger candidate = 0;
    while (byShard.count < shardCount) {
        NSString *did = [NSString stringWithFormat:@"did:plc:shard-cover-%lu", (unsigned long)candidate];
        NSUInteger shardIndex = ((NSUInteger)did.hash) % shardCount;
        if (!byShard[@(shardIndex)]) {
            byShard[@(shardIndex)] = did;
        }
        candidate++;
        XCTAssertLessThan(candidate, (NSUInteger)100000, @"could not find ordering keys covering every shard");
    }
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:shardCount];
    for (NSUInteger shard = 0; shard < shardCount; shard++) {
        [result addObject:byShard[@(shard)]];
    }
    return result;
}

// Stress case 5 (phase prompt), literal reading: "shutdown with every shard
// occupied and queued". testPipelineShutdownDrainsAccounting and
// testPipelineShutdownReportsTimeoutWhenWorkNeverCompletes above both block
// a single work item on a single shard -- the drain mechanism itself
// (_drainGroup/pendingWorkItems in RelayIngressPipeline) is shard-agnostic,
// since every shard's -dispatchWorkItem:toShard: enters/leaves the exact
// same dispatch_group, so a single blocked item already exercises the same
// group-wait/timeout code path multiple items across multiple shards would.
// That makes the existing single-shard tests an adequate proxy for the
// *mechanism*. This test goes further anyway and satisfies the case's
// literal wording directly: it genuinely occupies every configured shard
// simultaneously (one distinct ordering key per shard, so
// shardIndexForOrderingKey: routes each to a different shard queue) and
// confirms shutdown still drains all of them cleanly to zero outstanding
// accounting once every shard's blocked item is released.
- (void)testPipelineShutdownDrainsEveryOccupiedShard {
    const NSUInteger shardCount = 4;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:32
                                                            maxByteCount:4096
                                                      lowEventWatermark:16
                                                        lowByteWatermark:2048
                                                       highEventWatermark:24
                                                         highByteWatermark:3072
                                                              shardCount:shardCount
                                                   boundedIngressEnabled:YES
                                                                   error:NULL];
    NSArray<NSString *> *orderingKeys = [self orderingKeysCoveringEachShard:shardCount];

    dispatch_semaphore_t started = dispatch_semaphore_create(0);
    dispatch_semaphore_t allowFinish = dispatch_semaphore_create(0);
    dispatch_queue_t countingQueue =
        dispatch_queue_create("com.atproto.test.relay.shardsaturation.count", DISPATCH_QUEUE_SERIAL);
    __block NSUInteger startedCount = 0;
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];
    ATProtoRelayIngressPipeline *pipeline =
        [[ATProtoRelayIngressPipeline alloc] initWithConfiguration:config
                                                           metrics:metrics
                                                      processBlock:^(id event,
                                                                     NSString *upstreamURL,
                                                                     int64_t sequence,
                                                                     RelayIngressProcessCompletion completion) {
            (void)event;
            (void)upstreamURL;
            (void)sequence;
            dispatch_sync(countingQueue, ^{ startedCount++; });
            dispatch_semaphore_signal(started);
            dispatch_semaphore_wait(allowFinish, DISPATCH_TIME_FOREVER);
            completion(RelayIngressReleaseReasonProcessed);
        }];

    for (NSUInteger shard = 0; shard < shardCount; shard++) {
        ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:orderingKeys[shard]];
        event.seq = (int64_t)shard + 1;
        event.wireFrameLength = 32;
        XCTAssertTrue([pipeline submitEvent:event
                               encodedBytes:32
                                orderingKey:orderingKeys[shard]
                               fromUpstream:@"https://pds.example"
                                   sequence:(int64_t)shard + 1
                                      error:nil]);
    }

    // Every shard's serial worker is now blocked inside processBlock: wait
    // for all shardCount of them to have actually started before shutting
    // down, proving every shard is genuinely occupied simultaneously rather
    // than merely admitted-but-still-queued behind one busy shard.
    for (NSUInteger shard = 0; shard < shardCount; shard++) {
        XCTAssertEqual(dispatch_semaphore_wait(started, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0);
    }
    __block NSUInteger observedStarted = 0;
    dispatch_sync(countingQueue, ^{ observedStarted = startedCount; });
    XCTAssertEqual(observedStarted, shardCount);
    XCTAssertEqual(pipeline.admission.currentEventCount, shardCount);

    dispatch_semaphore_t shutdownDone = dispatch_semaphore_create(0);
    __block BOOL shutdownDrained = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [pipeline shutdownWithCompletion:^(BOOL drained) {
            shutdownDrained = drained;
            dispatch_semaphore_signal(shutdownDone);
        }];
    });

    // Release every shard's blocked item so the drain can proceed.
    for (NSUInteger shard = 0; shard < shardCount; shard++) {
        dispatch_semaphore_signal(allowFinish);
    }

    XCTAssertEqual(dispatch_semaphore_wait(shutdownDone, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC))), 0);
    XCTAssertTrue(shutdownDrained);
    XCTAssertEqual(pipeline.admission.currentEventCount, (NSUInteger)0);
    XCTAssertEqual(pipeline.admission.currentByteCount, (uint64_t)0);
}

#pragma mark - F10: noteUpstreamDisconnected: releases in-flight tokens

// Regression test for F10: -noteUpstreamDisconnected: used to be a no-op, so
// events already admitted (holding admission backlog capacity) but not yet
// processed by their shard queue sat there consuming that capacity until the
// shard queue naturally got around to them -- wasted capacity for an
// upstream that is already gone, since a reconnected upstream redelivers
// from its last *processed* cursor anyway (ADR 0039 section 3). This drives
// a deliberately slow/blocking processBlock so the event is still in flight
// when -noteUpstreamDisconnected: is called, and asserts the admission
// accounting drops to zero *before* the gate is released -- proving the
// disconnect path releases promptly rather than waiting for the shard
// queue's own completion. It then releases the gate and confirms the
// pipeline still drains cleanly, proving the shard queue's later,
// now-redundant release call double-releases harmlessly instead of
// corrupting accounting or crashing.
- (void)testNoteUpstreamDisconnectedReleasesInFlightTokensPromptly {
    ATProtoRelayIngressConfiguration *config = [self tinyConfiguration];
    NSString *upstreamURL = @"https://pds.example";
    dispatch_semaphore_t started = dispatch_semaphore_create(0);
    dispatch_semaphore_t allowFinish = dispatch_semaphore_create(0);
    ATProtoRelayMetrics *metrics = [[ATProtoRelayMetrics alloc] init];
    ATProtoRelayIngressPipeline *pipeline =
        [[ATProtoRelayIngressPipeline alloc] initWithConfiguration:config
                                                           metrics:metrics
                                                      processBlock:^(id event,
                                                                     NSString *eventUpstreamURL,
                                                                     int64_t sequence,
                                                                     RelayIngressProcessCompletion completion) {
            (void)event;
            (void)eventUpstreamURL;
            (void)sequence;
            dispatch_semaphore_signal(started);
            dispatch_semaphore_wait(allowFinish, DISPATCH_TIME_FOREVER);
            completion(RelayIngressReleaseReasonProcessed);
        }];

    ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:@"did:plc:disconnect"];
    event.seq = 1;
    event.wireFrameLength = 32;
    XCTAssertTrue([pipeline submitEvent:event
                           encodedBytes:32
                            orderingKey:@"did:plc:disconnect"
                           fromUpstream:upstreamURL
                               sequence:1
                                  error:nil]);
    XCTAssertGreaterThan(pipeline.admission.currentByteCount, (uint64_t)0);
    XCTAssertEqual(pipeline.admission.currentEventCount, (NSUInteger)1);

    // Wait for the shard queue to actually pick the item up (it is now
    // blocked on allowFinish), so the disconnect below races a genuinely
    // still-in-flight token rather than one that already released.
    XCTAssertEqual(dispatch_semaphore_wait(started, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0);

    [pipeline noteUpstreamDisconnected:upstreamURL];

    // -noteUpstreamDisconnected: is fire-and-forget onto the pipeline's
    // control queue; poll briefly for accounting to drop to zero. This must
    // happen *before* allowFinish is signalled below.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (pipeline.admission.currentByteCount != 0 &&
           [[NSDate date] compare:deadline] == NSOrderedAscending) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    XCTAssertEqual(pipeline.admission.currentByteCount, (uint64_t)0);
    XCTAssertEqual(pipeline.admission.currentEventCount, (NSUInteger)0);

    // Release the gate so the shard queue's own (now-redundant) release call
    // runs. It must double-release harmlessly rather than crash, corrupt
    // accounting, or prevent a clean drain.
    dispatch_semaphore_signal(allowFinish);

    dispatch_semaphore_t shutdownDone = dispatch_semaphore_create(0);
    __block BOOL shutdownDrained = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [pipeline shutdownWithCompletion:^(BOOL drained) {
            shutdownDrained = drained;
            dispatch_semaphore_signal(shutdownDone);
        }];
    });
    XCTAssertEqual(dispatch_semaphore_wait(shutdownDone, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC))), 0);
    XCTAssertTrue(shutdownDrained);
    XCTAssertEqual(pipeline.admission.currentEventCount, (NSUInteger)0);
    XCTAssertEqual(pipeline.admission.currentByteCount, (uint64_t)0);
}

- (void)testDecodeFailureReleasesAccounting {
    ATProtoRelayIngressConfiguration *config = [self tinyConfiguration];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    ATProtoRelayIngressPipeline *pipeline =
        [[ATProtoRelayIngressPipeline alloc] initWithConfiguration:config
                                                           metrics:[[ATProtoRelayMetrics alloc] init]
                                                      processBlock:^(id event,
                                                                     NSString *upstreamURL,
                                                                     int64_t sequence,
                                                                     RelayIngressProcessCompletion completion) {
            (void)event;
            (void)upstreamURL;
            (void)sequence;
            completion(RelayIngressReleaseReasonDecodeFailure);
            dispatch_semaphore_signal(done);
        }];
    ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:@"did:plc:carol"];
    event.seq = 7;
    event.wireFrameLength = 40;
    XCTAssertTrue([pipeline submitEvent:event
                           encodedBytes:40
                            orderingKey:@"did:plc:carol"
                           fromUpstream:@"https://pds.example"
                               sequence:7
                                  error:nil]);
    XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0);
    [pipeline waitForDrainForTesting];
    XCTAssertEqual(pipeline.admission.currentEventCount, 0);
    XCTAssertEqual(pipeline.admission.currentByteCount, 0);
    XCTAssertEqual(pipeline.lastProcessedSequence, 7);
}

- (void)testWatermarkCallbacksPauseAndResume {
    ATProtoRelayIngressConfiguration *config = [self tinyConfiguration];
    XCTestExpectation *pause = [self expectationWithDescription:@"pause"];
    XCTestExpectation *resume = [self expectationWithDescription:@"resume"];
    ATProtoRelayIngressAdmission *admission =
        [[ATProtoRelayIngressAdmission alloc] initWithConfiguration:config
                                                            metrics:[[ATProtoRelayMetrics alloc] init]];
    admission.onHighWatermark = ^{ [pause fulfill]; };
    admission.onLowWatermark = ^{ [resume fulfill]; };

    NSMutableArray<ATProtoRelayIngressAdmissionToken *> *tokens = [NSMutableArray array];
    for (NSUInteger index = 0; index < config.maxEventCount; index++) {
        ATProtoRelayIngressAdmissionToken *token =
            [admission admitEncodedBytes:16 upstreamURL:@"https://pds.example" sequence:(int64_t)index error:nil];
        XCTAssertNotNil(token);
        [tokens addObject:token];
    }
    XCTAssertTrue(admission.isAboveHighWatermark);
    for (ATProtoRelayIngressAdmissionToken *token in tokens) {
        XCTAssertTrue([admission releaseToken:token reason:RelayIngressReleaseReasonProcessed error:nil]);
    }
    [self waitForExpectations:@[pause, resume] timeout:2.0];
    XCTAssertEqual(admission.currentEventCount, 0);
}

- (void)testWatermarkHandlersFireInOrderAcrossRapidTransitions {
    ATProtoRelayIngressConfiguration *config = [self tinyConfiguration];
    ATProtoRelayIngressAdmission *admission =
        [[ATProtoRelayIngressAdmission alloc] initWithConfiguration:config
                                                            metrics:[[ATProtoRelayMetrics alloc] init]];

    __block NSMutableArray<NSString *> *recordedOrder = [NSMutableArray array];
    dispatch_semaphore_t handlerFired = dispatch_semaphore_create(0);

    admission.onHighWatermark = ^{
        @synchronized (recordedOrder) {
            [recordedOrder addObject:@"high"];
        }
        dispatch_semaphore_signal(handlerFired);
    };
    admission.onLowWatermark = ^{
        @synchronized (recordedOrder) {
            [recordedOrder addObject:@"low"];
        }
        dispatch_semaphore_signal(handlerFired);
    };

    // Drive several rapid high -> low transitions back to back, with no
    // pause between cycles, so the watermark handlers are dispatched in
    // quick succession. If they were delivered on a concurrent queue
    // (rather than a dedicated serial queue), a "low" dispatch could race
    // ahead of an earlier "high" dispatch and invoke resume logic before
    // the corresponding pause logic ran.
    const NSUInteger cycles = 5;
    for (NSUInteger cycle = 0; cycle < cycles; cycle++) {
        NSMutableArray<ATProtoRelayIngressAdmissionToken *> *tokens = [NSMutableArray array];
        for (NSUInteger index = 0; index < config.maxEventCount; index++) {
            ATProtoRelayIngressAdmissionToken *token =
                [admission admitEncodedBytes:16
                                  upstreamURL:@"https://pds.example"
                                     sequence:(int64_t)(cycle * config.maxEventCount + index)
                                        error:nil];
            XCTAssertNotNil(token);
            [tokens addObject:token];
        }
        XCTAssertTrue(admission.isAboveHighWatermark);
        for (ATProtoRelayIngressAdmissionToken *token in tokens) {
            XCTAssertTrue([admission releaseToken:token reason:RelayIngressReleaseReasonProcessed error:nil]);
        }
    }

    for (NSUInteger expected = 0; expected < cycles * 2; expected++) {
        XCTAssertEqual(dispatch_semaphore_wait(handlerFired, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0,
                        @"Timed out waiting for watermark handler %lu", (unsigned long)expected);
    }

    NSArray<NSString *> *snapshot = nil;
    @synchronized (recordedOrder) {
        snapshot = [recordedOrder copy];
    }

    XCTAssertEqual(snapshot.count, cycles * 2);
    for (NSUInteger cycle = 0; cycle < cycles; cycle++) {
        if (cycle * 2 + 1 >= snapshot.count) {
            break;
        }
        XCTAssertEqualObjects(snapshot[cycle * 2], @"high",
                               @"Expected high watermark before low watermark in cycle %lu", (unsigned long)cycle);
        XCTAssertEqualObjects(snapshot[cycle * 2 + 1], @"low",
                               @"Expected low watermark after high watermark in cycle %lu", (unsigned long)cycle);
    }
    [admission waitForDrainForTesting];
}

@end
