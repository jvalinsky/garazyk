/*!
 @file AppViewBackfillWorker.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Backfill/AppViewBackfillWorker.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Indexers/AppViewIndexer.h"
#import "Repository/CAR.h"
#import "Repository/MST.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"

@interface AppViewBackfillWorker ()
@property (nonatomic, copy)   NSString *did;
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) NSArray<id<AppViewIndexer>> *indexers;
@end

@implementation AppViewBackfillWorker {
    NSString *_plcURL;
}

NSString * const AppViewBackfillWorkerErrorDomain = @"com.atproto.appview.backfill";

- (instancetype)initWithDID:(NSString *)did
                    database:(AppViewDatabase *)database
                    indexers:(NSArray<id<AppViewIndexer>> *)indexers
                    plcURL:(NSString *)plcURL {
    self = [super init];
    if (self) {
        _did       = [did copy];
        _database  = database;
        _indexers  = [indexers copy];
        _plcURL    = [plcURL copy];
    }
    return self;
}

// ---------------------------------------------------------------------------

- (void)start {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self _run];
    });
}

// ---------------------------------------------------------------------------

- (void)_run {
    NSString *did = _did;
    PDS_LOG_INFO(@"[AppView BackfillWorker] Starting backfill for %@", did);

    // Load current sync state to get lastRev for incremental fetch
    NSError *stateErr = nil;
    AppViewRepoSyncState *state = [_database loadRepoSyncStateForDID:did error:&stateErr];
    NSString *sinceRev = state.lastRev; // nil for fresh backfill

    // Resolve PDS endpoint for this DID via com.atproto.identity.resolveHandle /
    // DID document `pds` service endpoint.
    NSString *pdsEndpoint = [self _resolvePDSEndpointForDID:did];
    if (!pdsEndpoint) {
        [self _failWithMessage:@"Could not resolve PDS endpoint" statusCode:0];
        return;
    }

    // Build the getRepo URL
    NSString *urlStr = [NSString stringWithFormat:@"%@/xrpc/com.atproto.sync.getRepo?did=%@",
                        pdsEndpoint,
                        [did stringByAddingPercentEncodingWithAllowedCharacters:
                            [NSCharacterSet URLQueryAllowedCharacterSet]]];
    if (sinceRev.length > 0) {
        urlStr = [urlStr stringByAppendingFormat:@"&since=%@",
                  [sinceRev stringByAddingPercentEncodingWithAllowedCharacters:
                      [NSCharacterSet URLQueryAllowedCharacterSet]]];
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.timeoutInterval = 120.0;
    [req setValue:@"application/vnd.ipld.car" forHTTPHeaderField:@"Accept"];
    [req setValue:@"garazyk-appview/1.0" forHTTPHeaderField:@"User-Agent"];

    // Synchronous fetch via NSURLSession (we're already on a background queue)
    __block NSHTTPURLResponse *httpResp = nil;
    __block NSError *fetchErr = nil;
    __block NSData *carData = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req
                                           completionHandler:^(NSData *data,
                                                                NSURLResponse *resp,
                                                                NSError *err) {
        carData   = data;
        httpResp  = (NSHTTPURLResponse *)resp;
        fetchErr  = err;
        dispatch_semaphore_signal(sema);
    }];
    [task resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

    if (fetchErr) {
        [self _failWithError:fetchErr rateLimitedUntil:nil];
        return;
    }

    NSInteger statusCode = httpResp.statusCode;

    if (statusCode == 429) {
        // Parse Retry-After header
        NSDate *retryAfter = nil;
        NSString *retryAfterHeader = httpResp.allHeaderFields[@"Retry-After"];
        if (retryAfterHeader) {
            NSTimeInterval interval = [retryAfterHeader doubleValue];
            if (interval > 0) retryAfter = [NSDate dateWithTimeIntervalSinceNow:interval];
        }
        if (!retryAfter) retryAfter = [NSDate dateWithTimeIntervalSinceNow:60.0];

        NSError *err = [NSError errorWithDomain:AppViewBackfillWorkerErrorDomain
                                           code:429
                                       userInfo:@{NSLocalizedDescriptionKey: @"Rate limited"}];
        [_database recordBackfillError:did message:@"HTTP 429 rate limited" error:nil];
        [_delegate worker:self didFailForDID:did error:err rateLimitedUntil:retryAfter];
        return;
    }

    if (statusCode < 200 || statusCode >= 300) {
        [self _failWithMessage:[NSString stringWithFormat:@"HTTP %ld", (long)statusCode]
                    statusCode:statusCode];
        return;
    }

    if (!carData || carData.length == 0) {
        [self _failWithMessage:@"Empty CAR response" statusCode:statusCode];
        return;
    }

    // Parse and index the CAR
    NSError *parseErr = nil;
    NSString *lastRev = [self _parseCARAndIndex:carData forDID:did error:&parseErr];

    if (parseErr) {
        [self _failWithError:parseErr rateLimitedUntil:nil];
        return;
    }

    PDS_LOG_INFO(@"[AppView BackfillWorker] Completed backfill for %@ (rev=%@)", did, lastRev);
    [_delegate worker:self didCompleteForDID:did lastRev:lastRev ?: @""];
}

// ---------------------------------------------------------------------------
// PDS host resolution
// ---------------------------------------------------------------------------

- (nullable NSString *)_resolvePDSEndpointForDID:(NSString *)did {
    // Check for environment override (Docker bridge networking, local testing)
    NSString *envOverride = [[NSProcessInfo processInfo] environment][@"APPVIEW_PDS_URL"];
    if (envOverride.length > 0) {
        PDS_LOG_DEBUG(@"[AppView BackfillWorker] Using APPVIEW_PDS_URL override: %@", envOverride);
        return envOverride;
    }

    // did:web — host is in the DID itself
    if ([did hasPrefix:@"did:web:"]) {
        NSString *host = [did substringFromIndex:8];
        host = [host stringByRemovingPercentEncoding] ?: host;
        // Check if it's localhost or local network, use http
        if ([host hasPrefix:@"127."] || [host hasPrefix:@"localhost"] || [host hasPrefix:@"192.168."] || [host hasPrefix:@"10."]) {
            return [NSString stringWithFormat:@"http://%@", host];
        }
        return [NSString stringWithFormat:@"https://%@", host];
    }

    // did:plc — fetch from configured PLC directory
    NSString *baseURL = _plcURL ?: @"https://plc.directory";
    NSString *plcURL = [NSString stringWithFormat:@"%@/%@", baseURL,
                        [did stringByAddingPercentEncodingWithAllowedCharacters:
                            [NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:plcURL]];
    req.timeoutInterval = 10.0;

    __block NSHTTPURLResponse *resp = nil;
    __block NSError *err = nil;
    __block NSData *data = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                     completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        data = d; resp = (NSHTTPURLResponse *)r; err = e;
        dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    if (err || resp.statusCode != 200 || !data) return nil;

    NSError *jsonErr = nil;
    NSDictionary *doc = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
    if (!doc) return nil;

    // Extract handle (alsoKnownAs)
    NSArray *akas = doc[@"alsoKnownAs"];
    for (NSString *aka in akas) {
        if ([aka hasPrefix:@"at://"]) {
            NSString *handle = [aka substringFromIndex:5];
            [_database saveHandle:handle did:did error:nil];
            PDS_LOG_INFO(@"[AppView BackfillWorker] Discovered handle mapping during backfill: %@ -> %@", handle, did);
            break;
        }
    }

    // Extract pds service endpoint from DID document
    NSArray *services = doc[@"service"];
    for (NSDictionary *svc in services) {
        NSString *type = svc[@"type"];
        NSString *endpoint = svc[@"serviceEndpoint"];
        if ([type isEqualToString:@"AtprotoPersonalDataServer"] && endpoint.length > 0) {
            return endpoint;
        }
    }

    return nil;
}

// ---------------------------------------------------------------------------
// CAR parsing and indexing
// ---------------------------------------------------------------------------

- (nullable NSString *)_parseCARAndIndex:(NSData *)carData
                                  forDID:(NSString *)did
                                   error:(NSError **)error {
    // File-based debug logging
    static NSString *debugLogPath = @"/tmp/debug-logs/backfill.log";
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/tmp/debug-logs" withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *logMsg = [NSString stringWithFormat:@"[%@] PARSE START did=%@ len=%lu\n",
                     [NSDate date], did, (unsigned long)carData.length];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:debugLogPath];
    if (!fh) {
        [[NSData data] writeToFile:debugLogPath atomically:YES];
        fh = [NSFileHandle fileHandleForWritingAtPath:debugLogPath];
    }
    [fh writeData:[logMsg dataUsingEncoding:NSUTF8StringEncoding]];
    [fh synchronizeFile];
    [fh closeFile];

    PDS_LOG_DEBUG(@"[AppView BackfillWorker] _parseCARAndIndex called for %@", did);
    PDS_LOG_DEBUG(@"[AppView BackfillWorker] CAR data length: %lu", (unsigned long)carData.length);

    CARReader *reader = [CARReader readFromData:carData error:error];
    if (!reader) {
        PDS_LOG_ERROR(@"[AppView BackfillWorker] Failed to read CAR: %@", *error);
        return nil;
    }

    PDS_LOG_DEBUG(@"[AppView BackfillWorker] CARReader success: blocks=%lu rootCID=%@",
              (unsigned long)reader.blocks.count, reader.rootCID);

    NSString *lastRev = nil;
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *snapshotRecords = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *snapshotBlocks = [NSMutableArray array];

    for (CARBlock *block in reader.blocks) {
        if (!block.cid.bytes || !block.data) continue;
        [snapshotBlocks addObject:@{
            @"cid_data": block.cid.bytes,
            @"block_data": block.data,
            @"content_type": @"application/cbor"
        }];
    }

    // Find and parse the data MST from commit object
    NSArray<MSTEntry *> *entries = nil;
    CID *dataMSTCID = nil;

    if (reader.rootCID) {
        CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
        if (commitBlock) {
            PDS_LOG_INFO(@"[AppView BackfillWorker] Decoding commit block (%lu bytes)",
                      (unsigned long)commitBlock.data.length);
            id commitObj = [ATProtoDagCBOR decodeData:commitBlock.data error:nil];
            if ([commitObj isKindOfClass:[NSDictionary class]]) {
                NSDictionary *commitDict = (NSDictionary *)commitObj;

                // Extract revision
                lastRev = commitDict[@"rev"];
                PDS_LOG_INFO(@"[AppView BackfillWorker] Found commit revision: %@", lastRev);

                // Extract data CID - this is the actual data MST
                id dataField = commitDict[@"data"];
                if ([dataField isKindOfClass:[CID class]]) {
                    dataMSTCID = (CID *)dataField;
                    PDS_LOG_INFO(@"[AppView BackfillWorker] Found data MST CID (CID type): %@", dataMSTCID);
                } else if ([dataField isKindOfClass:[NSData class]]) {
                    dataMSTCID = [CID cidFromBytes:dataField];
                    PDS_LOG_INFO(@"[AppView BackfillWorker] Found data MST CID (NSData type): %@", dataMSTCID);
                } else if ([dataField isKindOfClass:[NSString class]]) {
                    dataMSTCID = [CID cidFromString:dataField];
                    PDS_LOG_INFO(@"[AppView BackfillWorker] Found data MST CID (NSString type): %@", dataMSTCID);
                } else if (dataField) {
                    PDS_LOG_WARN(@"[AppView BackfillWorker] data field is unexpected type: %@", NSStringFromClass([dataField class]));
                }
            }
        }
    }

    // Now load the data MST using its CID
    if (dataMSTCID) {
        CARBlock *dataMSTBlock = [reader blockWithCID:dataMSTCID];
        if (dataMSTBlock) {
            PDS_LOG_INFO(@"[AppView BackfillWorker] Trying to deserialize data MST...");
            MST *dataMST = [MST deserializeFromCBOR:dataMSTBlock.data];
            if (dataMST && dataMST.root) {
                entries = [dataMST allEntries];
                PDS_LOG_INFO(@"[AppView BackfillWorker] Parsed data MST with %lu entries",
                          (unsigned long)entries.count);
            } else {
                PDS_LOG_WARN(@"[AppView BackfillWorker] Data MST deserialize failed");
                entries = [self _parseCBOREntriesFromBlock:dataMSTBlock.data];
            }
        } else {
            PDS_LOG_WARN(@"[AppView BackfillWorker] Could not find data MST block for CID: %@", dataMSTCID);
        }
    } else {
        PDS_LOG_WARN(@"[AppView BackfillWorker] No data CID found in commit");
    }

    // Index entries
    if (entries.count > 0) {
        for (MSTEntry *entry in entries) {
            CID *valueCID = entry.valueCID;
            if (!valueCID) continue;

            // Key format: "collection/!rkey" or "collection!rkey"
            NSString *fullKey = entry.key;
            if (!fullKey.length) continue;

            NSString *collection = fullKey;
            NSString *rkey = nil;
            NSRange delimRange = [fullKey rangeOfString:@"/"];
            if (delimRange.location == NSNotFound) {
                delimRange = [fullKey rangeOfString:@"!"];
            }
            if (delimRange.location != NSNotFound) {
                collection = [fullKey substringToIndex:delimRange.location];
                rkey = [fullKey substringFromIndex:delimRange.location + 1];
            }

            // Skip internal keys (not a record collection)
            if ([collection hasPrefix:@"_"] || [collection hasPrefix:@"#"]) continue;

            CARBlock *block = [reader blockWithCID:valueCID];
            if (!block) {
                PDS_LOG_WARN(@"[AppView BackfillWorker] Missing block for CID %@ in %@",
                          valueCID, did);
                continue;
            }

            NSError *decodeError = nil;
            id decoded = [ATProtoDagCBOR decodeData:block.data error:&decodeError];
            if ([decoded isKindOfClass:[NSDictionary class]]) {
                NSDictionary *record = (NSDictionary *)decoded;
                // Ensure $type is set from the collection key if not already present
                NSMutableDictionary *mutableRecord = [record mutableCopy];
                if (!mutableRecord[@"$type"]) {
                    mutableRecord[@"$type"] = collection;
                }
                [records addObject:@{
                    @"record": mutableRecord.count > 0 ? [mutableRecord copy] : record,
                    @"cid": valueCID.stringValue,
                    @"collection": collection,
                    @"rkey": rkey ?: @""
                }];

                NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey ?: @""];
                NSString *jsonValue = nil;
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:mutableRecord.count > 0 ? [mutableRecord copy] : record
                                                                    options:0
                                                                      error:nil];
                if (jsonData) {
                    jsonValue = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                }
                NSMutableDictionary *snapshotRecord = [@{
                    @"uri": uri,
                    @"collection": collection,
                    @"rkey": rkey ?: @"",
                    @"cid": valueCID.stringValue ?: @""
                } mutableCopy];
                if (jsonValue) snapshotRecord[@"value"] = jsonValue;
                [snapshotRecords addObject:[snapshotRecord copy]];
            }
        }
    }

    PDS_LOG_INFO(@"[AppView BackfillWorker] Found %lu records in CAR for %@", (unsigned long)records.count, did);
    NSError *snapshotError = nil;
    if (![_database saveRepoSnapshotForDID:did
                                   lastRev:lastRev ?: @""
                                   records:snapshotRecords
                                    blocks:snapshotBlocks
                                     error:&snapshotError]) {
        if (error) *error = snapshotError;
        return nil;
    }

    for (NSDictionary *item in records) {
        NSDictionary *record = item[@"record"];
        NSString *cid = item[@"cid"];
        NSString *collection = item[@"collection"];
        NSString *rkey = item[@"rkey"] ?: @"";
        
        PDS_LOG_DEBUG(@"[AppView BackfillWorker] Calling indexers for collection=%@", collection);
        BOOL wasIndexed = NO;
        for (id<AppViewIndexer> indexer in _indexers) {
            if ([indexer canIndexCollection:collection]) {
                NSError *indexErr = nil;
                BOOL ok = [indexer indexRecord:record
                                          did:did
                                   collection:collection
                                         rkey:rkey
                                          cid:cid
                                        error:&indexErr];
                wasIndexed = YES;
                if (!ok && indexErr) {
                    PDS_LOG_DEBUG(@"[AppView BackfillWorker] Dead-letter %@ for %@: %@",
                                  collection, did, indexErr.localizedDescription);
                    NSData *raw = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil]
                                  ?: [NSData data];
                    [_database recordDeadLetterEvent:collection
                                                seq:0
                                                did:did
                                                 rev:lastRev
                                                 cid:cid
                                           rawRecord:raw
                                     validationError:indexErr.localizedDescription ?: @"unknown"
                                               error:nil];
                }
                break;
            }
        }
        if (!wasIndexed) {
            PDS_LOG_DEBUG(@"[AppView BackfillWorker] No specialized indexer for %@; generic snapshot already stored", collection);
        }
    }

    return lastRev;
}

// ---------------------------------------------------------------------------
// Fallback CBOR parsing for older CAR formats
// ---------------------------------------------------------------------------

- (NSArray<MSTEntry *> *)_parseCBOREntriesFromBlock:(NSData *)data {
    NSMutableArray<MSTEntry *> *entries = [NSMutableArray array];
    NSError *error = nil;
    id cbor = [ATProtoDagCBOR decodeData:data error:&error];
    if (![cbor isKindOfClass:[NSDictionary class]]) return entries;

    NSDictionary *dict = (NSDictionary *)cbor;

    // Try to get entries from various CBOR structures
    id entriesData = dict[@"entries"] ?: dict[@"recordContents"] ?: dict[@"data"];
    if ([entriesData isKindOfClass:[NSDictionary class]]) {
        NSDictionary *entriesDict = (NSDictionary *)entriesData;
        for (NSString *key in entriesDict) {
            id value = entriesDict[key];
            if ([value isKindOfClass:[NSData class]]) {
                NSData *valueData = (NSData *)value;
                CID *cid = [CID cidFromBytes:valueData];
                if (cid) {
                    MSTEntry *entry = [MSTEntry entryWithKey:key valueCID:cid];
                    [entries addObject:entry];
                }
            }
        }
    }

    return entries;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

- (void)_failWithError:(NSError *)error rateLimitedUntil:(nullable NSDate *)rateLimitedUntil {
    PDS_LOG_WARN(@"[AppView BackfillWorker] Backfill failed for %@: %@", _did, error.localizedDescription);
    [_database recordBackfillError:_did message:error.localizedDescription error:nil];
    [_delegate worker:self didFailForDID:_did error:error rateLimitedUntil:rateLimitedUntil];
}

- (void)_failWithMessage:(NSString *)message statusCode:(NSInteger)statusCode {
    NSError *err = [NSError errorWithDomain:AppViewBackfillWorkerErrorDomain
                                       code:statusCode
                                   userInfo:@{NSLocalizedDescriptionKey: message}];
    [self _failWithError:err rateLimitedUntil:nil];
}

@end
