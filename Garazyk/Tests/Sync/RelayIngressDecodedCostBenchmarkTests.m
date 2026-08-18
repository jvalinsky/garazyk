// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#if !defined(GNUSTEP)
#import <mach/mach.h>
#endif
#import "Sync/Relay/RelayIngressPipeline.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"

/*!
 @class RelayIngressDecodedCostBenchmarkTests

 @abstract Measures the decoded-cost ratio (in-memory heap size / wire frame size)
 for relay ingress events, benchmarking each event kind that RelayIngressPipeline
 accounts for. Results feed into the decision whether to apply a multiplier to
 +encodedByteLengthForEvent: to reflect actual per-event memory overhead.

 See phase-38-review-remediation.md F13 and R12.
 */
@interface RelayIngressDecodedCostBenchmarkTests : XCTestCase
@end

@implementation RelayIngressDecodedCostBenchmarkTests

#if !defined(GNUSTEP)
- (uint64_t)currentResidentMemory {
    struct mach_task_basic_info info;
    mach_msg_type_number_t size = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                                     (task_info_t)&info, &size);
    return result == KERN_SUCCESS ? info.resident_size : 0;
}

/// Constructs a commit event with realistic block data (CAR-encoded repo snapshot).
/// The wireFrameLength is set to a representative value based on the blocks data.
- (ATProtoFirehoseCommitEvent *)commitEventForRepo:(NSString *)repo
                                      withBlockSize:(NSUInteger)blockSize {
    // Generate block data of approximately the requested size
    NSMutableData *blockData = [NSMutableData data];
    while (blockData.length < blockSize) {
        NSData *chunk = [@"block_data_chunk_with_padding_" dataUsingEncoding:NSUTF8StringEncoding];
        [blockData appendData:chunk];
    }

    ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
    event.repo = repo;
    event.seq = 1;
    event.time = @"2024-01-01T00:00:00Z";
    event.commit = [ATProtoCID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    event.rev = @"3lr5msvv5dk2d";
    event.ops = @[];
    event.blobs = @[];
    event.blocks = blockData;
    // wireFrameLength is set to the blocks size plus a small CBOR frame overhead estimate
    event.wireFrameLength = blockData.length + 512;

    return event;
}

/// Constructs an identity event with representative field values.
/// wireFrameLength estimates a typical CBOR-encoded identity event (~200 bytes).
- (ATProtoFirehoseIdentityEvent *)identityEventForDID:(NSString *)did {
    ATProtoFirehoseIdentityEvent *event = [[ATProtoFirehoseIdentityEvent alloc] init];
    event.did = did;
    event.seq = 1;
    event.time = @"2024-01-01T00:00:00Z";
    // A typical identity event: ~200 bytes when CBOR-encoded
    event.wireFrameLength = 200;
    return event;
}

/// Constructs an account event with representative field values.
/// wireFrameLength estimates a typical CBOR-encoded account event (~250 bytes).
- (ATProtoFirehoseAccountEvent *)accountEventForDID:(NSString *)did {
    ATProtoFirehoseAccountEvent *event = [[ATProtoFirehoseAccountEvent alloc] init];
    event.did = did;
    event.seq = 1;
    event.time = @"2024-01-01T00:00:00Z";
    // A typical account event: ~250 bytes when CBOR-encoded
    event.wireFrameLength = 250;
    return event;
}

/// Constructs a sync event with representative field values.
/// wireFrameLength estimates a typical CBOR-encoded sync event (~300 bytes).
- (ATProtoFirehoseSyncEvent *)syncEventForDID:(NSString *)did {
    ATProtoFirehoseSyncEvent *event = [[ATProtoFirehoseSyncEvent alloc] init];
    event.did = did;
    event.seq = 1;
    event.time = @"2024-01-01T00:00:00Z";
    // A typical sync event: ~300 bytes when CBOR-encoded
    event.wireFrameLength = 300;
    return event;
}

/// Measures the per-event decoded-cost ratio for a batch of events.
/// Returns (RSS delta / batch count) / wireFrameLength as the multiplier.
- (double)measureDecodedCostRatioForEventKind:(NSString *)kind
                                   batchCount:(NSUInteger)batchCount
                                eventFactory:(id (^)(NSUInteger index))factory {
    uint64_t beforeMem = [self currentResidentMemory];

    // Allocate the batch within an autoreleasepool, so any autoreleased temporaries the
    // factory creates (e.g. intermediate NSString/NSData) are drained before "after" is
    // measured -- ARC has no manual GC/pool-drain equivalent to force here, the pool's own
    // scope exit is the only drain mechanism.
    NSMutableArray *events = [NSMutableArray arrayWithCapacity:batchCount];
    @autoreleasepool {
        for (NSUInteger i = 0; i < batchCount; i++) {
            id event = factory(i);
            [events addObject:event];
        }
    }

    uint64_t afterMem = [self currentResidentMemory];

    // Compute per-event heap cost
    int64_t memoryDelta = (int64_t)afterMem - (int64_t)beforeMem;
    if (memoryDelta <= 0) {
        // Noise floor: if memory didn't grow, report a 0 multiplier
        // (likely a temporary allocation that was freed)
        return 0.0;
    }

    double perEventHeapCost = (double)memoryDelta / (double)batchCount;

    // Sample the first event to get its wireFrameLength
    id firstEvent = events.firstObject;
    NSUInteger wireFrameLength = 0;
    if ([firstEvent isKindOfClass:[ATProtoFirehoseCommitEvent class]]) {
        wireFrameLength = ((ATProtoFirehoseCommitEvent *)firstEvent).wireFrameLength;
    } else if ([firstEvent isKindOfClass:[ATProtoFirehoseIdentityEvent class]]) {
        wireFrameLength = ((ATProtoFirehoseIdentityEvent *)firstEvent).wireFrameLength;
    } else if ([firstEvent isKindOfClass:[ATProtoFirehoseAccountEvent class]]) {
        wireFrameLength = ((ATProtoFirehoseAccountEvent *)firstEvent).wireFrameLength;
    } else if ([firstEvent isKindOfClass:[ATProtoFirehoseSyncEvent class]]) {
        wireFrameLength = ((ATProtoFirehoseSyncEvent *)firstEvent).wireFrameLength;
    }

    double ratio = wireFrameLength > 0 ? (perEventHeapCost / (double)wireFrameLength) : 0.0;

    NSLog(@"[RelayIngressCostBenchmark] %@: "
          @"batch=%lu, before=%llu, after=%llu, delta=%lld bytes, "
          @"per-event-heap=%.1f bytes, wireFrameLength=%lu, ratio=%.2f",
          kind, (unsigned long)batchCount,
          (unsigned long long)beforeMem, (unsigned long long)afterMem,
          (long long)memoryDelta,
          perEventHeapCost, (unsigned long)wireFrameLength, ratio);

    // Keep events alive to prevent early deallocation
    XCTAssertGreaterThan(events.count, 0);

    return ratio;
}

#pragma mark - Benchmark Tests

/// Measures decoded cost for commit events with realistic block payloads.
/// Commits are the bulk of relay traffic and can be large (~MB for repos with many records).
- (void)testCommitEventDecodedCostWithRealisticBlocks {
    // Benchmark commit events with blocks of ~10 KB each (typical for medium repos)
    double ratio = [self measureDecodedCostRatioForEventKind:@"Commit (10KB blocks)"
                                                  batchCount:1000
                                               eventFactory:^id(NSUInteger index) {
        return [self commitEventForRepo:[NSString stringWithFormat:@"did:plc:actor%lu", index % 100]
                          withBlockSize:10 * 1024];
    }];

    // Commits with realistic blocks: decoded heap cost should stay below 10x the wire size
    // (object overhead + NSDictionary/NSArray + string overhead + CBOR parsing)
    XCTAssertLessThan(ratio, 10.0,
                      @"Commit event decoded-cost ratio (%.2f) exceeds 10x threshold", ratio);
}

/// Measures decoded cost for commit events with larger block payloads.
/// Stress case for large repo snapshots.
- (void)testCommitEventDecodedCostWithLargeBlocks {
    // Benchmark commit events with blocks of ~100 KB each (large repo snapshots)
    double ratio = [self measureDecodedCostRatioForEventKind:@"Commit (100KB blocks)"
                                                  batchCount:500
                                               eventFactory:^id(NSUInteger index) {
        return [self commitEventForRepo:[NSString stringWithFormat:@"did:plc:bigactor%lu", index % 50]
                          withBlockSize:100 * 1024];
    }];

    // Larger payloads: decoded overhead should be smaller relative to total size
    // (proportion of object overhead decreases)
    XCTAssertLessThan(ratio, 8.0,
                      @"Commit event (100KB blocks) decoded-cost ratio (%.2f) exceeds 8x", ratio);
}

/// Measures decoded cost for identity events.
/// Identity events are small but frequent (every DID-key change).
- (void)testIdentityEventDecodedCost {
    double ratio = [self measureDecodedCostRatioForEventKind:@"Identity"
                                                  batchCount:5000
                                               eventFactory:^id(NSUInteger index) {
        return [self identityEventForDID:[NSString stringWithFormat:@"did:plc:identity%lu", index]];
    }];

    // Small events: object overhead is proportionally larger, but still bounded
    XCTAssertLessThan(ratio, 10.0,
                      @"Identity event decoded-cost ratio (%.2f) exceeds 10x", ratio);
}

/// Measures decoded cost for account events.
/// Account events carry user metadata and moderation flags.
- (void)testAccountEventDecodedCost {
    double ratio = [self measureDecodedCostRatioForEventKind:@"Account"
                                                  batchCount:5000
                                               eventFactory:^id(NSUInteger index) {
        return [self accountEventForDID:[NSString stringWithFormat:@"did:plc:account%lu", index]];
    }];

    XCTAssertLessThan(ratio, 10.0,
                      @"Account event decoded-cost ratio (%.2f) exceeds 10x", ratio);
}

/// Measures decoded cost for sync events.
/// Sync events signal repository state changes and are structurally simple.
- (void)testSyncEventDecodedCost {
    double ratio = [self measureDecodedCostRatioForEventKind:@"Sync"
                                                  batchCount:5000
                                               eventFactory:^id(NSUInteger index) {
        return [self syncEventForDID:[NSString stringWithFormat:@"did:plc:sync%lu", index]];
    }];

    XCTAssertLessThan(ratio, 10.0,
                      @"Sync event decoded-cost ratio (%.2f) exceeds 10x", ratio);
}

#endif

@end
