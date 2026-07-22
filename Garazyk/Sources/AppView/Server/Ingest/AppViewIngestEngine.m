// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewIngestEngine.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Ingest/AppViewIngestEngine.h"

#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "Debug/GZLogger.h"
#import "Sync/Relay/RelayClient.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/CID.h"
#import "Core/DID.h"
#import "Core/NSDictionary+CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoDagCBOR.h"
#import "Repository/CAR.h"
#import "Repository/STAR.h"
#import "Compat/PDSTypes.h"

// ---------------------------------------------------------------------------
// AppViewIngestEvent
// ---------------------------------------------------------------------------

@implementation AppViewIngestEvent
@end

// ---------------------------------------------------------------------------
// CID Link Resolution
// ---------------------------------------------------------------------------

/**
 Recursively resolve CID links in decoded IPLD objects.
 When DAG-CBOR decoding produces CID objects (from tag 42), they need to be
 resolved by looking up the referenced blocks in the CAR and decoding them.
 */
static id ResolveCIDLinksInObject(id object, CARReader *reader, NSMutableSet *visitedCIDs, int depth) {
    // Prevent infinite loops and excessive recursion
    if (depth > 10 || !reader) {
        return object;
    }

    if ([object isKindOfClass:[CID class]]) {
        CID *cid = (CID *)object;
        NSString *cidString = cid.stringValue;

        // Prevent cycles
        if ([visitedCIDs containsObject:cidString]) {
            GZ_LOG_DEBUG(@"[AppView Ingest] CID cycle at depth %d: %@", depth, cidString);
            return object;
        }
        [visitedCIDs addObject:cidString];

        // Look up the block and decode it
        CARBlock *block = [reader blockWithCID:cid];
        if (block) {
            NSError *decodeErr = nil;
            id decoded = [ATProtoDagCBOR decodeDataAsJSON:block.data error:&decodeErr];
            if (!decoded) {
                decoded = [ATProtoDagCBOR decodeData:block.data error:&decodeErr];
            }
            if (decoded) {
                GZ_LOG_DEBUG(@"[AppView Ingest] Resolved CID link at depth %d, got type %@, keys=%@",
                             depth, NSStringFromClass([decoded class]),
                             [decoded isKindOfClass:[NSDictionary class]] ? [(NSDictionary *)decoded allKeys] : @"N/A");
                return ResolveCIDLinksInObject(decoded, reader, visitedCIDs, depth + 1);
            } else {
                GZ_LOG_DEBUG(@"[AppView Ingest] Failed to decode CID link %@: %@", cidString, decodeErr.localizedDescription);
            }
        } else {
            GZ_LOG_DEBUG(@"[AppView Ingest] CID link not found in CAR: %@", cidString);
        }
        return object;

    } else if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        NSMutableDictionary *resolved = [NSMutableDictionary dictionaryWithCapacity:dict.count];
        for (id key in dict) {
            id value = dict[key];
            resolved[key] = ResolveCIDLinksInObject(value, reader, visitedCIDs, depth + 1);
        }
        return resolved;

    } else if ([object isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)object;
        NSMutableArray *resolved = [NSMutableArray arrayWithCapacity:array.count];
        for (id item in array) {
            [resolved addObject:ResolveCIDLinksInObject(item, reader, visitedCIDs, depth + 1)];
        }
        return resolved;
    }

    return object;
}

// ---------------------------------------------------------------------------
// Per-relay connection state
// ---------------------------------------------------------------------------

@interface AppViewRelayConnection : NSObject <RelayClientDelegate>

@property (nonatomic, strong) RelayClient *client;
@property (nonatomic, copy)   NSString *relayURL;
@property (nonatomic, assign) int64_t lastCheckpointSeq;
@property (nonatomic, assign) int64_t currentSeq;
@property (nonatomic, weak)   id owner;  // AppViewIngestEngine (weak to avoid cycles)

- (instancetype)initWithRelayURL:(NSString *)url
                     startingSeq:(int64_t)startingSeq
                           owner:(id)owner;

@end

@implementation AppViewRelayConnection

- (instancetype)initWithRelayURL:(NSString *)url
                     startingSeq:(int64_t)startingSeq
                           owner:(id)owner {
    self = [super init];
    if (!self) return nil;
    _relayURL = [url copy];
    _currentSeq = startingSeq;
    _lastCheckpointSeq = startingSeq;
    _owner = owner;

    NSURL *nsurl = [NSURL URLWithString:url];
    _client = [[RelayClient alloc] initWithServerURL:nsurl];
    _client.delegate = self;

    if (startingSeq > 0) {
        [_client storeCursor:startingSeq forRepo:@"global"];
    }

    return self;
}

#pragma mark - RelayClientDelegate

- (void)relayClient:(RelayClient *)client didReceiveCommitEvent:(FirehoseCommitEvent *)event {
    AppViewIngestEngine *engine = self.owner;
    if (!engine) return;
    [engine _handleCommitEvent:event fromRelay:self.relayURL];
    self.currentSeq = event.seq;
}

- (void)relayClient:(RelayClient *)client didReceiveIdentityEvent:(FirehoseIdentityEvent *)event {
    AppViewIngestEngine *engine = self.owner;
    if (!engine) return;
    [engine _handleIdentityEvent:event fromRelay:self.relayURL];
    self.currentSeq = event.seq;
}

- (void)relayClient:(RelayClient *)client didReceiveAccountEvent:(FirehoseAccountEvent *)event {
    AppViewIngestEngine *engine = self.owner;
    if (!engine) return;
    [engine _handleAccountEvent:event fromRelay:self.relayURL];
    self.currentSeq = event.seq;
}

- (void)relayClientDidConnect:(RelayClient *)client {
    AppViewIngestEngine *engine = self.owner;
    if (!engine) return;
    GZ_LOG_INFO(@"[AppView Ingest] Connected to relay %@", self.relayURL);
    [engine _relayConnection:self didConnectAtSeq:self.currentSeq];
}

- (void)relayClient:(RelayClient *)client didDisconnectWithError:(nullable NSError *)error {
    if (error) {
        GZ_LOG_WARN(@"[AppView Ingest] Disconnected from relay %@: %@",
                     self.relayURL, error.localizedDescription);
    } else {
        GZ_LOG_INFO(@"[AppView Ingest] Disconnected from relay %@ (clean)", self.relayURL);
    }
}

- (void)relayClient:(RelayClient *)client didReceiveErrorEvent:(FirehoseErrorEvent *)event {
    GZ_LOG_WARN(@"[AppView Ingest] Relay %@ sent error %@: %@",
                 self.relayURL,
                 event.error ?: @"unknown",
                 event.message ?: @"");
}

- (void)relayClient:(RelayClient *)client didReceiveCursor:(int64_t)cursor {
    self.currentSeq = cursor;
}

@end

// ---------------------------------------------------------------------------
// AppViewIngestEngine
// ---------------------------------------------------------------------------

@interface AppViewIngestEngine ()
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) NSArray<NSString *> *relayURLs;
@property (nonatomic, strong) NSMutableArray<AppViewRelayConnection *> *connections;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t eventQueue;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t checkpointQueue;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t processingQueue;
@property (nonatomic, strong) NSLock *stateLock;
@property (nonatomic, strong) NSTimer *checkpointTimer;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lagByRelay;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *backpressureStateByRelay;
@property (nonatomic, assign) int64_t highestSeenSeq;
@property (nonatomic, assign) int64_t eventsSinceLastFlush;

- (void)_persistDirtyRepairMarkerForDID:(NSString *)did
                                    seq:(int64_t)seq
                                    rev:(nullable NSString *)rev
                                    cid:(nullable NSString *)cid
                               relayURL:(NSString *)relayURL
                                 reason:(NSString *)reason;
@end

@implementation AppViewIngestEngine

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                       relayURLs:(NSArray<NSString *> *)relayURLs {
    self = [super init];
    if (!self) return nil;
    _database              = database;
    _relayURLs             = [relayURLs copy];
    _connections           = [NSMutableArray array];
    _stateLock             = [[NSLock alloc] init];
    _checkpointIntervalMs  = 5000;
    _isRunning             = NO;
    _lagByRelay            = [NSMutableDictionary dictionary];
    _backpressureStateByRelay = [NSMutableDictionary dictionary];
    _eventQueue            = dispatch_queue_create("dev.garazyk.appview.ingest.events",
                                                   DISPATCH_QUEUE_SERIAL);
    _checkpointQueue       = dispatch_queue_create("dev.garazyk.appview.ingest.checkpoint",
                                                   DISPATCH_QUEUE_SERIAL);
    // Serial processing queue to ensure in-order record materialization and database consistency.
    // Using a concurrent queue caused race conditions on repo rev checks and out-of-order writes.
    _processingQueue      = dispatch_queue_create("dev.garazyk.appview.ingest.processing",
                                                   DISPATCH_QUEUE_SERIAL);
    _relayHeartbeatTimeout = 10.0;
    // Allow environment override for backpressure threshold (default 5000, was 50000)
    {
        const char *envThreshold = getenv("APPVIEW_BACKPRESSURE_THRESHOLD");
        if (envThreshold) {
            _maxLagForBackpressure = atoll(envThreshold);
        } else {
            _maxLagForBackpressure = 5000;
        }
    }
    _highestSeenSeq        = 0;
    return self;
}

- (void)start {
    [_stateLock lock];
    if (_isRunning) {
        [_stateLock unlock];
        return;
    }
    _isRunning = YES;
    [_stateLock unlock];

    for (NSString *relayURL in _relayURLs) {
        NSError *err = nil;
        AppViewCheckpoint *checkpoint = [_database loadCheckpointForRelayURL:relayURL error:&err];
        int64_t startSeq = checkpoint ? checkpoint.seq : 0;
        [_database markDurableCursor:startSeq forRelayURL:relayURL];
        GZ_LOG_INFO(@"[AppView Ingest] Starting relay %@ from seq %lld", relayURL, (long long)startSeq);

        AppViewRelayConnection *conn = [[AppViewRelayConnection alloc]
            initWithRelayURL:relayURL startingSeq:startSeq owner:self];
        // Apply heartbeat timeout for dead-peer detection
        conn.client.firehose.heartbeatTimeout = self.relayHeartbeatTimeout;
        
        [_stateLock lock];
        [_connections addObject:conn];
        [_stateLock unlock];
        
        [conn.client connect];
    }

    // Periodic checkpoint flush
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimeInterval interval = self.checkpointIntervalMs / 1000.0;
        self.checkpointTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                               target:self
                                                             selector:@selector(_timerFired)
                                                             userInfo:nil
                                                              repeats:YES];
    });
}

- (void)stop {
    [_stateLock lock];
    _isRunning = NO;
    NSArray *connsToStop = [_connections copy];
    [_connections removeAllObjects];
    [_stateLock unlock];

    [_checkpointTimer invalidate];
    _checkpointTimer = nil;

    for (AppViewRelayConnection *conn in connsToStop) {
        [conn.client disconnect];
    }
    [self flushCheckpoints];
}

- (void)_flushCheckpointsOnQueue {
    [_stateLock lock];
    NSArray *activeConnections = [self.connections copy];
    [_stateLock unlock];

    for (AppViewRelayConnection *conn in activeConnections) {
        int64_t durableSeq = [self.database durableCursorForRelayURL:conn.relayURL];
        if (durableSeq <= conn.lastCheckpointSeq) continue;
        AppViewCheckpoint *cp = [[AppViewCheckpoint alloc]
            initWithRelayURL:conn.relayURL seq:durableSeq];
        NSError *err = nil;
        if (![self.database saveCheckpoint:cp error:&err]) {
            GZ_LOG_WARN(@"[AppView Ingest] Failed to save checkpoint for %@: %@",
                         conn.relayURL, err.localizedDescription);
        } else {
            conn.lastCheckpointSeq = durableSeq;
        }

        // Check if we can resume a paused relay (hysteresis: resume
        // when lag drops below half the backpressure threshold).
        int64_t lag = _highestSeenSeq - conn.lastCheckpointSeq;
        
        [_stateLock lock];
        BOOL isPaused = [self.backpressureStateByRelay[conn.relayURL] integerValue] == 1;
        [_stateLock unlock];

        if (lag < self.maxLagForBackpressure / 2 && isPaused) {
            [conn.client resumeReading];
            [_stateLock lock];
            self.backpressureStateByRelay[conn.relayURL] = @0;
            [_stateLock unlock];
            GZ_LOG_INFO(@"[AppView Ingest] Backpressure: RESUMING relay %@ (lag=%lld)",
                         conn.relayURL, (long long)lag);
        }
    }
}

- (void)flushCheckpoints {
    dispatch_sync(_checkpointQueue, ^{
        [self _flushCheckpointsOnQueue];
    });
}

// Returns YES if backpressure is active (lag exceeds threshold)
- (BOOL)_shouldApplyBackpressure:(int64_t)incomingSeq fromRelay:(NSString *)relayURL {
    [_stateLock lock];
    if (incomingSeq > _highestSeenSeq) {
        _highestSeenSeq = incomingSeq;
    }
    [_stateLock unlock];

    // Use the durable cursor (in-memory, updated on every processed event)
    // instead of lastCheckpointSeq (only updated on periodic flush).
    // This gives a real-time lag measurement instead of one that's up to
    // checkpointIntervalMs seconds stale.
    int64_t durableSeq = [_database durableCursorForRelayURL:relayURL];

    int64_t lag = _highestSeenSeq - durableSeq;
    if (lag > self.maxLagForBackpressure) {
        GZ_LOG_WARN(@"[AppView Ingest] Backpressure: lag=%lld exceeds threshold=%lld for %@",
                     (long long)lag, (long long)self.maxLagForBackpressure, relayURL);
        return YES;
    }
    return NO;
}

- (nullable AppViewRelayConnection *)_connectionForRelayURL:(NSString *)relayURL {
    [_stateLock lock];
    AppViewRelayConnection *found = nil;
    for (AppViewRelayConnection *conn in _connections) {
        if ([conn.relayURL isEqualToString:relayURL]) {
            found = conn;
            break;
        }
    }
    [_stateLock unlock];
    return found;
}

- (void)_timerFired {
    [self flushCheckpoints];
}

// ---------------------------------------------------------------------------
// Event handlers (called from RelayClient delegate — already on a BG thread)
// ---------------------------------------------------------------------------

- (void)_handleCommitEvent:(FirehoseCommitEvent *)event fromRelay:(NSString *)relayURL {
    @autoreleasepool {
    NSString *did = event.repo;
    NSString *rev = event.rev;
    NSString *cid = event.commit ? [event.commit stringValue] : nil;
    int64_t seq   = event.seq;

    NSTimeInterval fastPathStart = [[NSDate date] timeIntervalSinceReferenceDate];

    // Idempotency check (fast, on relay thread)
    if ([_database hasEventWithDID:did rev:rev cid:cid]) {
        GZ_LOG_DEBUG(@"[AppView Ingest] Skipping duplicate event did=%@ rev=%@", did, rev);
        [_database markDurableCursor:seq forRelayURL:relayURL];
        return;
    }

    // Backpressure: pause the relay instead of dropping events.
    // TCP backpressure propagates to the relay, which slows or stops sending.
    if ([self _shouldApplyBackpressure:seq fromRelay:relayURL]) {
        AppViewRelayConnection *conn = [self _connectionForRelayURL:relayURL];
        if (conn && !conn.client.isReadingPaused) {
            [conn.client pauseReading];
            [_stateLock lock];
            self.backpressureStateByRelay[relayURL] = @1;
            int64_t lag = _highestSeenSeq - conn.lastCheckpointSeq;
            [_stateLock unlock];
            GZ_LOG_WARN(@"[AppView Ingest] Backpressure: PAUSING relay %@ (lag=%lld)",
                         relayURL, (long long)lag);
        }
        // Still persist the repair marker — it will be processed
        // when we resume and catch up via the repair worker.
        [self _persistDirtyRepairMarkerForDID:did seq:seq rev:rev cid:cid relayURL:relayURL reason:@"backpressure"];
        return;
    }

    // Persist the event envelope durably (fast, on relay thread)
    // FIXME: replace with actual envelope from FirehoseCommitEvent; dummy is a placeholder
    NSData *dummy = [NSData data]; // raw envelope not available from FirehoseCommitEvent directly
    NSError *storeError = nil;
    if (![_database appendStoredEventWithType:@"live_commit"
                                          seq:seq
                                          did:did
                                          rev:rev
                                          cid:cid
                                  rawEnvelope:dummy
                                        error:&storeError]) {
        GZ_LOG_WARN(@"[AppView Ingest] Failed to durably append commit seq=%lld: %@",
                     (long long)seq, storeError.localizedDescription);
        return;
    }
    [_database logEvent:seq did:did rev:rev cid:cid rawEnvelope:dummy error:nil];

    NSTimeInterval fastPathElapsed = [[NSDate date] timeIntervalSinceReferenceDate] - fastPathStart;
    GZ_LOG_DEBUG(@"[AppView Ingest] Fast path for seq=%lld did=%@ took %.3fms",
                  (long long)seq, did, fastPathElapsed * 1000.0);

    // Dispatch heavy processing to the serial processing queue.
    // This decouples the relay callback thread from the CPU-intensive
    // CAR parsing, record materialization, and database writes.
    dispatch_async(_processingQueue, ^{
        @try {
            [self _processCommitEvent:event fromRelay:relayURL];
        } @catch (NSException *exception) {
            GZ_LOG_ERROR(@"[AppView Ingest] Uncaught exception processing seq=%lld: %@ — %@",
                          (long long)event.seq, exception.name, exception.reason);
        }
    });
    } // @autoreleasepool
}

- (void)_processCommitEvent:(FirehoseCommitEvent *)event fromRelay:(NSString *)relayURL {
    @autoreleasepool {
    NSTimeInterval processStart = [[NSDate date] timeIntervalSinceReferenceDate];
    NSString *did = event.repo;
    NSString *rev = event.rev;
    NSString *cid = event.commit ? [event.commit stringValue] : nil;
    int64_t seq   = event.seq;
    // FIXME: replace with actual envelope from FirehoseCommitEvent; dummy is a placeholder
    NSData *dummy = [NSData data];

    NSError *err = nil;
    AppViewRepoSyncState *syncState = [_database loadRepoSyncStateForDID:did error:&err];
    if (syncState && syncState.status == AppViewRepoSyncStatusSynced &&
        [event.since isKindOfClass:[NSString class]] && event.since.length > 0 &&
        [syncState.lastRev isKindOfClass:[NSString class]] && syncState.lastRev.length > 0 &&
        ![event.since isEqualToString:syncState.lastRev]) {
        GZ_LOG_WARN(@"[AppView Ingest] Gap for %@: event.since=%@ stored=%@", did, event.since, syncState.lastRev);
        [self _persistDirtyRepairMarkerForDID:did seq:seq rev:rev cid:cid relayURL:relayURL reason:@"continuity_gap"];
        id<AppViewIngestEngineDelegate> delegate = self.delegate;
        if (delegate && [delegate respondsToSelector:@selector(ingestEngine:didDetectGapForDID:atSeq:)]) {
            dispatch_async(_eventQueue, ^{
                [delegate ingestEngine:self didDetectGapForDID:did atSeq:seq];
            });
        }
        return;
    }

    // Materialize blocks and records
    CARReader *reader = nil;
    if (event.blocks) {
        NSError *carErr = nil;
        if (STARDetectFormatFromData(event.blocks)) {
            // STAR format — convert to CAR for downstream processing
            NSData *carData = [STARConverter carDataFromSTARData:event.blocks error:&carErr];
            if (carData) {
                reader = [CARReader readFromData:carData error:&carErr];
            }
        } else {
            reader = [CARReader readFromData:event.blocks error:&carErr];
        }
        if (!reader) {
            GZ_LOG_WARN(@"[AppView Ingest] Failed to parse blocks for seq %lld: %@", (long long)seq, carErr.localizedDescription);
            [self _persistDirtyRepairMarkerForDID:did seq:seq rev:rev cid:cid relayURL:relayURL reason:@"car_parse_failed"];
            return;
        }
    }

    // Pre-parse all records from CAR blocks before persisting.
    // This avoids holding the database lock while doing CPU-intensive CBOR decoding.
    NSMutableArray<NSDictionary *> *enrichedOps = [NSMutableArray array];
    NSMutableArray *blocksToSave = [NSMutableArray array]; // Collect blocks for persist

    if (reader) {
        for (CARBlock *block in reader.blocks) {
            [blocksToSave addObject:block];
        }
    }

    for (NSDictionary *op in event.ops) {
        NSString *action = op[@"action"];
        NSString *path = op[@"path"];
        NSString *uri = [NSString stringWithFormat:@"at://%@/%@", did, path];

        // cid may be a CID object (from CBOR tag 42 decode), NSString, or NSNull
        id rawCID = op[@"cid"];
        NSString *cidStr = [op cidStringForKey:@"cid"];
        CID *opCID = [op cidObjectForKey:@"cid"];
        
        GZ_LOG_DEBUG(@"[AppView Ingest] op path=%@ cid_type=%@ cid_val=%@", path, NSStringFromClass([rawCID class]), rawCID);

        NSMutableDictionary *enrichedOp = [op mutableCopy];
        
        if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
            NSArray *parts = [path componentsSeparatedByString:@"/"];
            NSString *collection = parts.count > 0 ? parts[0] : @"unknown";
            NSString *rkey = parts.count > 1 ? parts[1] : @"unknown";
            
            // Extract record data from CAR blocks
            // Try by CID first, then fall back to path matching if CID is missing
            NSDictionary *record = op[@"record"];
            if (!record && reader && opCID) {
                CARBlock *block = [reader blockWithCID:opCID];
                if (block) {
                    id decoded = [ATProtoCBORSerialization JSONObjectWithData:block.data error:nil];
                    if (!decoded) {
                        decoded = [ATProtoDagCBOR decodeData:block.data error:nil];
                    }
                    // Resolve any CID links in the decoded object
                    if (decoded) {
                        decoded = ResolveCIDLinksInObject(decoded, reader, [NSMutableSet set], 0);
                        if ([decoded isKindOfClass:[NSDictionary class]]) {
                            record = (NSDictionary *)decoded;
                            enrichedOp[@"record"] = record;
                            GZ_LOG_DEBUG(@"[AppView Ingest] Decoded record from CID block: keys=%@", record.allKeys);
                        }
                    }
                }
            }
            // If still no record, try path-based matching in CAR blocks
            if (!record && reader) {
                for (CARBlock *block in reader.blocks) {
                    NSError *decodeErr = nil;
                    id decoded = [ATProtoCBORSerialization JSONObjectWithData:block.data error:nil];

                    // Try DAG-CBOR if regular CBOR fails
                    if (!decoded) {
                        decoded = [ATProtoDagCBOR decodeDataAsJSON:block.data error:&decodeErr];
                    }

                    if (decoded && [decoded isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *dictDecoded = (NSDictionary *)decoded;
                        // Check if this is a valid record entry
                        NSString *recordType = dictDecoded[@"$type"];
                        // Look for actual record fields beyond just having content
                        BOOL hasRecordFields = recordType || dictDecoded[@"text"] || dictDecoded[@"value"] ||
                                              dictDecoded[@"subject"] || dictDecoded[@"created"];

                        if (hasRecordFields) {
                            // Resolve any CID links in the record
                            record = (NSDictionary *)ResolveCIDLinksInObject(dictDecoded, reader, [NSMutableSet set], 0);
                            enrichedOp[@"record"] = record;
                            GZ_LOG_DEBUG(@"[AppView Ingest] Found record in CAR block: keys=%@", record.allKeys);

                            if (!cidStr) {
                                CID *computedCID = [CID cidWithDigest:[CID sha256Digest:block.data] codec:0x71];
                                if (computedCID) {
                                    enrichedOp[@"cid"] = computedCID.stringValue;
                                    cidStr = computedCID.stringValue;
                                    opCID = computedCID;
                                }
                            }
                            // Exit loop on first valid record
                            break;
                        }
                    } else if (decodeErr) {
                        GZ_LOG_DEBUG(@"[AppView Ingest] Failed to decode CAR block: %@", decodeErr.localizedDescription);
                    }
                }
            }

// Extract subject DID if applicable (e.g. follow target)
            // Use enrichedOp record if available, fall back to op record
            NSDictionary *recordForSubject = enrichedOp[@"record"] ?: op[@"record"];
            GZ_LOG_DEBUG(@"[AppView Ingest] Subject extraction: enrichedOp.record keys=%@", recordForSubject.allKeys);
            NSString *subjectDid = nil;
            if (recordForSubject && [recordForSubject isKindOfClass:[NSDictionary class]]) {
                id subject = recordForSubject[@"subject"];
                if ([subject isKindOfClass:[NSString class]]) {
                    if ([subject hasPrefix:@"did:"]) {
                        subjectDid = subject;
                    } else if ([subject hasPrefix:@"at://"]) {
                        NSArray *uriParts = [subject componentsSeparatedByString:@"/"];
                        if (uriParts.count > 2) subjectDid = uriParts[2];
                    }
                } else if ([subject isKindOfClass:[NSDictionary class]]) {
                    // Handle StrongRef (uri) or RepoRef (did)
                    id uriVal = subject[@"uri"];
                    if ([uriVal isKindOfClass:[NSString class]] && [uriVal hasPrefix:@"at://"]) {
                        NSArray *uriParts = [uriVal componentsSeparatedByString:@"/"];
                        if (uriParts.count > 2) subjectDid = uriParts[2];
                    } else {
                        id didVal = subject[@"did"];
                        if ([didVal isKindOfClass:[NSString class]] && [didVal hasPrefix:@"did:"]) {
                            subjectDid = didVal;
                        }
                    }
                }
            }

            GZ_LOG_DEBUG(@"[AppView Ingest] Materializing record: %@ cid=%@ subject=%@", uri, cidStr, subjectDid);

            NSError *recordError = nil;
            if (![_database saveRecordWithURI:uri
                                         did:did
                                  collection:collection
                                        rkey:rkey
                                         cid:cidStr ?: @""
                                      handle:nil
                                       value:nil
                                  subjectDid:subjectDid
                                       error:&recordError]) {
                GZ_LOG_WARN(@"[AppView Ingest] Failed to store record %@ seq=%lld: %@",
                             uri, (long long)seq, recordError.localizedDescription);
                [self _persistDirtyRepairMarkerForDID:did seq:seq rev:rev cid:cid relayURL:relayURL reason:@"record_store_failed"];
                return;
            }
        } else if ([action isEqualToString:@"delete"]) {
            NSError *deleteError = nil;
            if (![_database executeParameterizedUpdate:@"DELETE FROM records WHERE uri = ?" params:@[uri] error:&deleteError]) {
                GZ_LOG_WARN(@"[AppView Ingest] Failed to delete record %@ seq=%lld: %@",
                             uri, (long long)seq, deleteError.localizedDescription);
                [self _persistDirtyRepairMarkerForDID:did seq:seq rev:rev cid:cid relayURL:relayURL reason:@"record_delete_failed"];
                return;
            }
        }

        [enrichedOps addObject:[enrichedOp copy]];
    }

    // Persist blocks (each call dispatches to the database queue internally).
    for (CARBlock *block in blocksToSave) {
        if (!block.cid || !block.cid.bytes || !block.data) {
            GZ_LOG_WARN(@"[AppView Ingest] Skipping block with nil cid/data for %@ seq=%lld",
                         did, (long long)seq);
            continue;
        }
        NSError *blockError = nil;
        if (![_database saveBlockWithCid:block.cid.bytes
                                 repoDid:did
                               blockData:block.data
                              contentType:nil
                                    error:&blockError]) {
            GZ_LOG_WARN(@"[AppView Ingest] Failed to store block for %@ seq=%lld: %@",
                         did, (long long)seq, blockError.localizedDescription);
            [self _persistDirtyRepairMarkerForDID:did seq:seq rev:rev cid:cid relayURL:relayURL reason:@"block_store_failed"];
            return;
        }
    }

    // Build ingest event with enriched ops (containing records)
    AppViewIngestEvent *ingestEvent = [[AppViewIngestEvent alloc] init];
    ingestEvent.seq        = seq;
    ingestEvent.relayURL   = relayURL;
    ingestEvent.did        = did;
    ingestEvent.rev        = rev;
    ingestEvent.cid        = cid;
    ingestEvent.eventType  = @"#commit";
    ingestEvent.ops        = [enrichedOps copy];
    ingestEvent.rawEnvelope = dummy;
    ingestEvent.receivedAt  = [NSDate date];

    // Check repo sync status — buffer if backfill in-flight
    if (syncState && syncState.status == AppViewRepoSyncStatusProcessing) {
        // Buffer the delta; it will be replayed after backfill completes
        AppViewPendingDelta *delta = [[AppViewPendingDelta alloc]
            initWithDID:did seq:seq commitCID:cid ?: @"" rev:rev ?: @"" rawEnvelope:dummy];
        [_database enqueuePendingDelta:delta error:nil];
        GZ_LOG_DEBUG(@"[AppView Ingest] Buffered delta for in-flight backfill: did=%@", did);
        [_database markDurableCursor:seq forRelayURL:relayURL];
        return;
    }

    // Dispatch to delegate
    id<AppViewIngestEngineDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(ingestEngine:didReceiveCommit:)]) {
        dispatch_async(_eventQueue, ^{
            [delegate ingestEngine:self didReceiveCommit:ingestEvent];
        });
    }

    // Advance the per-repo live cursor only after the commit has been materialized.
    // Without this, a later event cannot detect a missing intermediate commit via
    // event.since, and the AppView can report zero global lag while records are absent.
    if (rev.length > 0) {
        AppViewRepoSyncState *newState = syncState ? [syncState copy] : [[AppViewRepoSyncState alloc] initWithDID:did];
        newState.status = AppViewRepoSyncStatusSynced;
        newState.lastRev = rev;
        newState.lastError = nil;
        newState.errorCount = 0;
        NSError *stateError = nil;
        if (![_database upsertRepoSyncState:newState error:&stateError]) {
            GZ_LOG_WARN(@"[AppView Ingest] Failed to advance repo sync state for %@ seq=%lld: %@",
                         did, (long long)seq, stateError.localizedDescription);
            [self _persistDirtyRepairMarkerForDID:did seq:seq rev:rev cid:cid relayURL:relayURL reason:@"sync_state_update_failed"];
            return;
        }
    }

    [_database markDurableCursor:seq forRelayURL:relayURL];

    // Event-driven checkpoint: flush immediately when lag is significant
    // (every 100 events) to keep the durable cursor advancing even under
    // heavy load when the timer-based flush hasn't fired yet.
    _eventsSinceLastFlush++;
    if (_eventsSinceLastFlush >= 100) {
        _eventsSinceLastFlush = 0;
        dispatch_async(_checkpointQueue, ^{
            [self _flushCheckpointsOnQueue];
        });
    }

    NSTimeInterval processElapsed = [[NSDate date] timeIntervalSinceReferenceDate] - processStart;
    GZ_LOG_DEBUG(@"[AppView Ingest] Processed seq=%lld did=%@ blocks=%lu records=%lu took %.1fms",
                  (long long)seq, did,
                  (unsigned long)blocksToSave.count,
                  (unsigned long)enrichedOps.count,
                  processElapsed * 1000.0);

    } // @autoreleasepool
}

- (void)_handleIdentityEvent:(FirehoseIdentityEvent *)event fromRelay:(NSString *)relayURL {
    @autoreleasepool {
    // FIXME: replace with actual envelope from FirehoseIdentityEvent; dummy is a placeholder
    NSData *dummy = [NSData data];
    NSError *storeError = nil;
    if (![_database appendStoredEventWithType:@"identity"
                                          seq:event.seq
                                          did:event.did
                                          rev:nil
                                          cid:nil
                                  rawEnvelope:dummy
                                        error:&storeError]) {
        GZ_LOG_WARN(@"[AppView Ingest] Failed to durably append identity seq=%lld: %@",
                     (long long)event.seq, storeError.localizedDescription);
        return;
    }
    [_database logEvent:event.seq did:event.did rev:nil cid:nil rawEnvelope:dummy error:nil];

    if (event.handle) {
        [_database saveHandle:event.handle did:event.did error:nil];
        GZ_LOG_INFO(@"[AppView Ingest] Updated handle mapping: %@ -> %@", event.handle, event.did);
    }
    [[DIDResolver sharedResolver] invalidateDID:event.did];

    AppViewIngestEvent *ingestEvent = [[AppViewIngestEvent alloc] init];
    ingestEvent.seq        = event.seq;
    ingestEvent.relayURL   = relayURL;
    ingestEvent.did        = event.did;
    ingestEvent.eventType  = @"#identity";
    ingestEvent.rawEnvelope = dummy;
    ingestEvent.receivedAt  = [NSDate date];

    id<AppViewIngestEngineDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(ingestEngine:didReceiveIdentityChange:)]) {
        dispatch_async(_eventQueue, ^{
            [delegate ingestEngine:self didReceiveIdentityChange:ingestEvent];
        });
    }
    [_database markDurableCursor:event.seq forRelayURL:relayURL];
    } // @autoreleasepool
}

- (void)_handleAccountEvent:(FirehoseAccountEvent *)event fromRelay:(NSString *)relayURL {
    @autoreleasepool {
    NSData *dummy = [NSData data];
    NSError *storeError = nil;
    if (![_database appendStoredEventWithType:@"account"
                                          seq:event.seq
                                          did:event.did
                                          rev:nil
                                          cid:nil
                                  rawEnvelope:dummy
                                        error:&storeError]) {
        GZ_LOG_WARN(@"[AppView Ingest] Failed to durably append account seq=%lld: %@",
                     (long long)event.seq, storeError.localizedDescription);
        return;
    }
    [_database logEvent:event.seq did:event.did rev:nil cid:nil rawEnvelope:dummy error:nil];

    GZ_LOG_INFO(@"[AppView Ingest] Account event: did=%@ active=%d status=%@ seq=%lld",
                 event.did, event.active, event.status ?: @"(none)", (long long)event.seq);

    AppViewIngestEvent *ingestEvent = [[AppViewIngestEvent alloc] init];
    ingestEvent.seq        = event.seq;
    ingestEvent.relayURL   = relayURL;
    ingestEvent.did        = event.did;
    ingestEvent.eventType  = @"#account";
    ingestEvent.rawEnvelope = dummy;
    ingestEvent.receivedAt  = [NSDate date];

    id<AppViewIngestEngineDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(ingestEngine:didReceiveAccountEvent:)]) {
        dispatch_async(_eventQueue, ^{
            [delegate ingestEngine:self didReceiveAccountEvent:ingestEvent];
        });
    }
    [_database markDurableCursor:event.seq forRelayURL:relayURL];
    } // @autoreleasepool
}

- (void)_persistDirtyRepairMarkerForDID:(NSString *)did
                                    seq:(int64_t)seq
                                    rev:(nullable NSString *)rev
                                    cid:(nullable NSString *)cid
                               relayURL:(NSString *)relayURL
                                 reason:(NSString *)reason {
    [_database markRepoDirty:did error:nil];
    NSData *raw = [reason dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSError *markerError = nil;
    if ([_database appendStoredEventWithType:@"dirty_repair"
                                         seq:seq
                                         did:did
                                         rev:rev
                                         cid:cid
                                 rawEnvelope:raw
                                       error:&markerError]) {
        [_database markDurableCursor:seq forRelayURL:relayURL];
    } else {
        GZ_LOG_WARN(@"[AppView Ingest] Failed to persist dirty marker for %@ seq=%lld: %@",
                     did, (long long)seq, markerError.localizedDescription);
    }
}

- (void)_relayConnection:(AppViewRelayConnection *)conn didConnectAtSeq:(int64_t)seq {
    id<AppViewIngestEngineDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(ingestEngine:didReconnectToRelay:atSeq:)]) {
        dispatch_async(_eventQueue, ^{
            [delegate ingestEngine:self didReconnectToRelay:conn.relayURL atSeq:seq];
        });
    }
}

@end
