// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Mikrus/MikrusMetrics.h"

@interface GZMikrusMetrics () {
@package
    dispatch_queue_t _queue;
    int64_t _ingestEvents, _ingestCommits, _ingestDeletes, _ingestOps, _ingestIdentities;
    int64_t _recordsIndexed, _recordsDeleted, _ingestErrors;
    int64_t _queriesBacklink, _queriesManyToMany, _queriesIdentity, _queriesRecord;
    int64_t _rateLimitRejects;
    NSTimeInterval _startTime;
}
@end

@implementation GZMikrusMetrics

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("blue.microcosm.mikrus.metrics", DISPATCH_QUEUE_SERIAL);
        _startTime = [NSDate timeIntervalSinceReferenceDate];
    }
    return self;
}

- (void)recordIngestEvent   { dispatch_sync(_queue, ^{ ++_ingestEvents;    }); }
- (void)recordIngestCommit  { dispatch_sync(_queue, ^{ ++_ingestCommits;   }); }
- (void)recordIngestDelete  { dispatch_sync(_queue, ^{ ++_ingestDeletes;   }); }
- (void)recordIngestOp      { dispatch_sync(_queue, ^{ ++_ingestOps;       }); }
- (void)recordIngestIdentity{ dispatch_sync(_queue, ^{ ++_ingestIdentities;}); }
- (void)recordRecordIndexed { dispatch_sync(_queue, ^{ ++_recordsIndexed;  }); }
- (void)recordRecordDeleted { dispatch_sync(_queue, ^{ ++_recordsDeleted;  }); }
- (void)recordIngestError   { dispatch_sync(_queue, ^{ ++_ingestErrors;    }); }

- (void)recordQueryBacklink  { dispatch_sync(_queue, ^{ ++_queriesBacklink;   }); }
- (void)recordQueryManyToMany{ dispatch_sync(_queue, ^{ ++_queriesManyToMany; }); }
- (void)recordQueryIdentity  { dispatch_sync(_queue, ^{ ++_queriesIdentity;   }); }
- (void)recordQueryRecord    { dispatch_sync(_queue, ^{ ++_queriesRecord;     }); }

- (void)recordRateLimitReject{ dispatch_sync(_queue, ^{ ++_rateLimitRejects; }); }

- (NSDictionary<NSString *, id> *)snapshotDictionary {
    __block NSDictionary *result = nil;
    dispatch_sync(_queue, ^{
        result = @{
            @"uptimeSeconds": @((int64_t)([NSDate timeIntervalSinceReferenceDate] - self->_startTime)),
            @"ingest": @{
                @"events": @(self->_ingestEvents),
                @"commits": @(self->_ingestCommits),
                @"deletes": @(self->_ingestDeletes),
                @"ops": @(self->_ingestOps),
                @"identities": @(self->_ingestIdentities),
                @"recordsIndexed": @(self->_recordsIndexed),
                @"recordsDeleted": @(self->_recordsDeleted),
                @"errors": @(self->_ingestErrors),
            },
            @"queries": @{
                @"backlink": @(self->_queriesBacklink),
                @"manyToMany": @(self->_queriesManyToMany),
                @"identity": @(self->_queriesIdentity),
                @"record": @(self->_queriesRecord),
            },
            @"rateLimitRejects": @(self->_rateLimitRejects),
        };
    });
    return result;
}

@end
