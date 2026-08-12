// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Thread-safe monotonic counters for the Mikrus link-index service. */
@interface GZMikrusMetrics : NSObject

/// Ingest counters
- (void)recordIngestEvent;
- (void)recordIngestCommit;
- (void)recordIngestDelete;
- (void)recordIngestOp;
- (void)recordIngestIdentity;
- (void)recordRecordIndexed;
- (void)recordRecordDeleted;
- (void)recordIngestError;

/// Query counters
- (void)recordQueryBacklink;
- (void)recordQueryManyToMany;
- (void)recordQueryIdentity;
- (void)recordQueryRecord;

/// Rate limiting
- (void)recordRateLimitReject;

- (NSDictionary<NSString *, id> *)snapshotDictionary;

@end

NS_ASSUME_NONNULL_END
