/*!
 @file AppViewIngestEngine.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Ingest/AppViewIngestEngine.h"

#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "Debug/PDSLogger.h"
#import "Sync/Relay/RelayClient.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/CID.h"
#import "Core/NSDictionary+CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoDagCBOR.h"
#import "Repository/CAR.h"

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
            PDS_LOG_DEBUG(@"[AppView Ingest] CID cycle at depth %d: %@", depth, cidString);
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
                PDS_LOG_DEBUG(@"[AppView Ingest] Resolved CID link at depth %d, got type %@, keys=%@",
                             depth, NSStringFromClass([decoded class]),
                             [decoded isKindOfClass:[NSDictionary class]] ? [(NSDictionary *)decoded allKeys] : @"N/A");
                return ResolveCIDLinksInObject(decoded, reader, visitedCIDs, depth + 1);
            } else {
                PDS_LOG_DEBUG(@"[AppView Ingest] Failed to decode CID link %@: %@", cidString, decodeErr.localizedDescription);
            }
        } else {
            PDS_LOG_DEBUG(@"[AppView Ingest] CID link not found in CAR: %@", cidString);
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

- (void)relayClientDidConnect:(RelayClient *)client {
    AppViewIngestEngine *engine = self.owner;
    if (!engine) return;
    PDS_LOG_INFO(@"[AppView Ingest] Connected to relay %@", self.relayURL);
    [engine _relayConnection:self didConnectAtSeq:self.currentSeq];
}

- (void)relayClient:(RelayClient *)client didDisconnectWithError:(nullable NSError *)error {
    if (error) {
        PDS_LOG_WARN(@"[AppView Ingest] Disconnected from relay %@: %@",
                     self.relayURL, error.localizedDescription);
    } else {
        PDS_LOG_INFO(@"[AppView Ingest] Disconnected from relay %@ (clean)", self.relayURL);
    }
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
@property (nonatomic, strong) dispatch_queue_t eventQueue;
@property (nonatomic, strong) dispatch_queue_t checkpointQueue;
@property (nonatomic, strong) NSTimer *checkpointTimer;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lagByRelay;
@property (nonatomic, assign) int64_t highestSeenSeq;
@end

@implementation AppViewIngestEngine

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                       relayURLs:(NSArray<NSString *> *)relayURLs {
    self = [super init];
    if (!self) return nil;
    _database              = database;
    _relayURLs             = [relayURLs copy];
    _connections           = [NSMutableArray array];
    _checkpointIntervalMs  = 5000;
    _isRunning             = NO;
    _lagByRelay            = [NSMutableDictionary dictionary];
    _eventQueue            = dispatch_queue_create("dev.garazyk.appview.ingest.events",
                                                   DISPATCH_QUEUE_SERIAL);
    _checkpointQueue       = dispatch_queue_create("dev.garazyk.appview.ingest.checkpoint",
                                                   DISPATCH_QUEUE_SERIAL);
    _relayHeartbeatTimeout = 10.0;
    _maxLagForBackpressure = 50000;
    _highestSeenSeq        = 0;
    return self;
}

- (void)start {
    if (_isRunning) return;
    _isRunning = YES;

    for (NSString *relayURL in _relayURLs) {
        NSError *err = nil;
        AppViewCheckpoint *checkpoint = [_database loadCheckpointForRelayURL:relayURL error:&err];
        int64_t startSeq = checkpoint ? checkpoint.seq : 0;
        PDS_LOG_INFO(@"[AppView Ingest] Starting relay %@ from seq %lld", relayURL, (long long)startSeq);

        AppViewRelayConnection *conn = [[AppViewRelayConnection alloc]
            initWithRelayURL:relayURL startingSeq:startSeq owner:self];
        // Apply heartbeat timeout for dead-peer detection
        conn.client.firehose.heartbeatTimeout = self.relayHeartbeatTimeout;
        [_connections addObject:conn];
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
    _isRunning = NO;

    [_checkpointTimer invalidate];
    _checkpointTimer = nil;

    for (AppViewRelayConnection *conn in _connections) {
        [conn.client disconnect];
    }
    [self flushCheckpoints];
    [_connections removeAllObjects];
}

- (void)flushCheckpoints {
    dispatch_sync(_checkpointQueue, ^{
        for (AppViewRelayConnection *conn in self.connections) {
            if (conn.currentSeq <= conn.lastCheckpointSeq) continue;
            AppViewCheckpoint *cp = [[AppViewCheckpoint alloc]
                initWithRelayURL:conn.relayURL seq:conn.currentSeq];
            NSError *err = nil;
            if (![self.database saveCheckpoint:cp error:&err]) {
                PDS_LOG_WARN(@"[AppView Ingest] Failed to save checkpoint for %@: %@",
                             conn.relayURL, err.localizedDescription);
            } else {
                conn.lastCheckpointSeq = conn.currentSeq;
            }
        }
    });
}

// Returns YES if backpressure is active (lag exceeds threshold)
- (BOOL)_shouldApplyBackpressure:(int64_t)incomingSeq fromRelay:(NSString *)relayURL {
    if (incomingSeq > _highestSeenSeq) {
        _highestSeenSeq = incomingSeq;
    }
    int64_t lag = _highestSeenSeq - self.lastCheckpointSeq;
    if (lag > self.maxLagForBackpressure) {
        PDS_LOG_WARN(@"[AppView Ingest] Backpressure: lag=%lld exceeds threshold=%lld for %@",
                     (long long)lag, (long long)self.maxLagForBackpressure, relayURL);
        return YES;
    }
    return NO;
}

- (void)_timerFired {
    [self flushCheckpoints];
}

// ---------------------------------------------------------------------------
// Event handlers (called from RelayClient delegate — already on a BG thread)
// ---------------------------------------------------------------------------

- (void)_handleCommitEvent:(FirehoseCommitEvent *)event fromRelay:(NSString *)relayURL {
    NSString *did = event.repo;
    NSString *rev = event.rev;
    NSString *cid = event.commit ? [event.commit stringValue] : nil;
    int64_t seq   = event.seq;

    // Idempotency check
    if ([_database hasEventWithDID:did rev:rev cid:cid]) {
        PDS_LOG_DEBUG(@"[AppView Ingest] Skipping duplicate event did=%@ rev=%@", did, rev);
        return;
    }

    // Backpressure check: drop events if lag exceeds threshold
    if ([self _shouldApplyBackpressure:seq fromRelay:relayURL]) {
        PDS_LOG_WARN(@"[AppView Ingest] Backpressure active, skipping event seq=%lld from %@", (long long)seq, relayURL);
        return;
    }

    // Log raw event (best-effort; ignore failure — we already checked for dup)
    NSData *dummy = [NSData data]; // raw envelope not available from FirehoseCommitEvent directly
    [_database logEvent:seq did:did rev:rev cid:cid rawEnvelope:dummy error:nil];

    // Materialize blocks and records
    CARReader *reader = nil;
    if (event.blocks) {
        NSError *carErr = nil;
        reader = [CARReader readFromData:event.blocks error:&carErr];
        if (reader) {
            for (CARBlock *block in reader.blocks) {
                [_database saveBlockWithCid:block.cid.bytes
                                   repoDid:did
                                 blockData:block.data
                                contentType:nil
                                      error:nil];
            }
        } else {
            PDS_LOG_WARN(@"[AppView Ingest] Failed to parse CAR blocks for seq %lld: %@", (long long)seq, carErr.localizedDescription);
        }
    }

    NSMutableArray<NSDictionary *> *enrichedOps = [NSMutableArray array];

    for (NSDictionary *op in event.ops) {
        NSString *action = op[@"action"];
        NSString *path = op[@"path"];
        NSString *uri = [NSString stringWithFormat:@"at://%@/%@", did, path];

        // cid may be a CID object (from CBOR tag 42 decode), NSString, or NSNull
        id rawCID = op[@"cid"];
        NSString *cidStr = [op cidStringForKey:@"cid"];
        CID *opCID = [op cidObjectForKey:@"cid"];
        
        PDS_LOG_DEBUG(@"[AppView Ingest] op path=%@ cid_type=%@ cid_val=%@", path, NSStringFromClass([rawCID class]), rawCID);

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
                            PDS_LOG_DEBUG(@"[AppView Ingest] Decoded record from CID block: keys=%@", record.allKeys);
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
                            PDS_LOG_DEBUG(@"[AppView Ingest] Found record in CAR block: keys=%@", record.allKeys);

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
                        PDS_LOG_DEBUG(@"[AppView Ingest] Failed to decode CAR block: %@", decodeErr.localizedDescription);
                    }
                }
            }

// Extract subject DID if applicable (e.g. follow target)
            // Use enrichedOp record if available, fall back to op record
            NSDictionary *recordForSubject = enrichedOp[@"record"] ?: op[@"record"];
            PDS_LOG_DEBUG(@"[AppView Ingest] Subject extraction: enrichedOp.record keys=%@", recordForSubject.allKeys);
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
                    NSString *uri = subject[@"uri"];
                    if ([uri hasPrefix:@"at://"]) {
                        NSArray *uriParts = [uri componentsSeparatedByString:@"/"];
                        if (uriParts.count > 2) subjectDid = uriParts[2];
                    } else {
                        NSString *didVal = subject[@"did"];
                        if ([didVal hasPrefix:@"did:"]) {
                            subjectDid = didVal;
                        }
                    }
                }
            }

            PDS_LOG_DEBUG(@"[AppView Ingest] Materializing record: %@ cid=%@ subject=%@", uri, cidStr, subjectDid);

            [_database saveRecordWithURI:uri
                                    did:did
                             collection:collection
                                   rkey:rkey
                                    cid:cidStr
                                 handle:nil // Will be populated by indexers if needed
                                  value:nil // value field in records table is optional/nullable
                             subjectDid:subjectDid
                                   error:nil];
        } else if ([action isEqualToString:@"delete"]) {
            [_database executeParameterizedUpdate:@"DELETE FROM records WHERE uri = ?" params:@[uri] error:nil];
        }
        
        [enrichedOps addObject:[enrichedOp copy]];
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
    NSError *err = nil;
    AppViewRepoSyncState *syncState = [_database loadRepoSyncStateForDID:did error:&err];

    if (syncState && syncState.status == AppViewRepoSyncStatusProcessing) {
        // Buffer the delta; it will be replayed after backfill completes
        AppViewPendingDelta *delta = [[AppViewPendingDelta alloc]
            initWithDID:did seq:seq commitCID:cid ?: @"" rev:rev ?: @"" rawEnvelope:dummy];
        [_database enqueuePendingDelta:delta error:nil];
        PDS_LOG_DEBUG(@"[AppView Ingest] Buffered delta for in-flight backfill: did=%@", did);
        return;
    }

    // Dispatch to delegate
    id<AppViewIngestEngineDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(ingestEngine:didReceiveCommit:)]) {
        dispatch_async(_eventQueue, ^{
            [delegate ingestEngine:self didReceiveCommit:ingestEvent];
        });
    }

    // Auto-register unknown repos in pending state for backfill
    if (!syncState) {
        AppViewRepoSyncState *newState = [[AppViewRepoSyncState alloc] initWithDID:did];
        [_database upsertRepoSyncState:newState error:nil];
    }
}

- (void)_handleIdentityEvent:(FirehoseIdentityEvent *)event fromRelay:(NSString *)relayURL {
    NSData *dummy = [NSData data];
    [_database logEvent:event.seq did:event.did rev:nil cid:nil rawEnvelope:dummy error:nil];

    if (event.handle) {
        [_database saveHandle:event.handle did:event.did error:nil];
        PDS_LOG_INFO(@"[AppView Ingest] Updated handle mapping: %@ -> %@", event.handle, event.did);
    }

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
