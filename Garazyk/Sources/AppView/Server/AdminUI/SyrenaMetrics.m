// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppView/Server/AdminUI/SyrenaMetrics.h"
#import "Compat/PDSTypes.h"

@interface GZSyrenaMetrics ()
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@property (nonatomic, assign) int64_t ingestEvents;
@property (nonatomic, assign) int64_t ingestCommits;
@property (nonatomic, assign) int64_t ingestOps;
@property (nonatomic, assign) int64_t ingestDeletes;
@property (nonatomic, assign) int64_t ingestIdentities;
@property (nonatomic, assign) int64_t ingestErrors;
@property (nonatomic, assign) int64_t backfillCompleted;
@property (nonatomic, assign) int64_t backfillFailed;
@property (nonatomic, assign) int64_t backfillEnqueued;
@property (nonatomic, assign) int64_t queryBacklink;
@property (nonatomic, assign) int64_t queryManyToMany;
@property (nonatomic, assign) int64_t queryIdentity;
@property (nonatomic, assign) int64_t queryRecord;
@property (nonatomic, assign) int64_t queryOther;
@property (nonatomic, assign) int64_t queryErrors;
@property (nonatomic, assign) int64_t rateLimitRejects;
@end

@implementation GZSyrenaMetrics

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.garazyk.syrena.metrics", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Ingest

- (void)recordIngestEvent       { dispatch_async(self.queue, ^{ self.ingestEvents++; }); }
- (void)recordIngestCommit      { dispatch_async(self.queue, ^{ self.ingestCommits++; }); }
- (void)recordIngestOp          { dispatch_async(self.queue, ^{ self.ingestOps++; }); }
- (void)recordIngestDelete      { dispatch_async(self.queue, ^{ self.ingestDeletes++; }); }
- (void)recordIngestIdentity    { dispatch_async(self.queue, ^{ self.ingestIdentities++; }); }
- (void)recordIngestError       { dispatch_async(self.queue, ^{ self.ingestErrors++; }); }

#pragma mark - Backfill

- (void)recordBackfillCompleted { dispatch_async(self.queue, ^{ self.backfillCompleted++; }); }
- (void)recordBackfillFailed    { dispatch_async(self.queue, ^{ self.backfillFailed++; }); }
- (void)recordBackfillEnqueued:(NSUInteger)count { dispatch_async(self.queue, ^{ self.backfillEnqueued += (int64_t)count; }); }

#pragma mark - Query

- (void)recordQuery:(NSString *)family {
    dispatch_async(self.queue, ^{
        if ([family isEqualToString:@"backlink"])          self.queryBacklink++;
        else if ([family isEqualToString:@"manyToMany"])   self.queryManyToMany++;
        else if ([family isEqualToString:@"identity"])     self.queryIdentity++;
        else if ([family isEqualToString:@"record"])       self.queryRecord++;
        else                                               self.queryOther++;
    });
}

- (void)recordQueryError { dispatch_async(self.queue, ^{ self.queryErrors++; }); }

#pragma mark - Rate-limit

- (void)recordRateLimitReject { dispatch_async(self.queue, ^{ self.rateLimitRejects++; }); }

#pragma mark - Snapshot

- (NSDictionary<NSString *, id> *)snapshotDictionary {
    __block NSDictionary *snap;
    dispatch_sync(self.queue, ^{
        int64_t totalQueries = self.queryBacklink + self.queryManyToMany + self.queryIdentity + self.queryRecord + self.queryOther;
        snap = @{
            @"ingest": @{
                @"events":     @(self.ingestEvents),
                @"commits":    @(self.ingestCommits),
                @"ops":        @(self.ingestOps),
                @"deletes":    @(self.ingestDeletes),
                @"identities": @(self.ingestIdentities),
                @"errors":     @(self.ingestErrors),
            },
            @"backfill": @{
                @"completed": @(self.backfillCompleted),
                @"failed":    @(self.backfillFailed),
                @"enqueued":  @(self.backfillEnqueued),
            },
            @"queries": @{
                @"backlink":    @(self.queryBacklink),
                @"manyToMany":  @(self.queryManyToMany),
                @"identity":    @(self.queryIdentity),
                @"record":      @(self.queryRecord),
                @"other":       @(self.queryOther),
                @"total":       @(totalQueries),
                @"errors":      @(self.queryErrors),
            },
            @"rateLimitRejects": @(self.rateLimitRejects),
        };
    });
    return snap;
}

@end
