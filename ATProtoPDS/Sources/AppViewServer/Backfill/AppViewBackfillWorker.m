/*!
 @file AppViewBackfillWorker.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppViewServer/Backfill/AppViewBackfillWorker.h"
#import "AppViewServer/AppViewDatabase.h"
#import "AppViewServer/AppViewTypes.h"
#import "AppViewServer/Indexers/AppViewIndexer.h"
#import "Debug/PDSLogger.h"

#import <Foundation/Foundation.h>

NSString * const AppViewBackfillWorkerErrorDomain = @"AppViewBackfillWorkerErrorDomain";

@interface AppViewBackfillWorker ()
@property (nonatomic, copy)   NSString *did;
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) NSArray<id<AppViewIndexer>> *indexers;
@end

@implementation AppViewBackfillWorker

- (instancetype)initWithDID:(NSString *)did
                   database:(AppViewDatabase *)database
                   indexers:(NSArray<id<AppViewIndexer>> *)indexers {
    self = [super init];
    if (!self) return nil;
    _did      = [did copy];
    _database = database;
    _indexers = [indexers copy];
    return self;
}

- (void)start {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
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

    // Resolve PDS host for this DID via com.atproto.identity.resolveHandle /
    // DID document `pds` service endpoint.
    NSString *pdsHost = [self _resolvePDSHostForDID:did];
    if (!pdsHost) {
        [self _failWithMessage:@"Could not resolve PDS host" statusCode:0];
        return;
    }

    // Build the getRepo URL
    NSString *urlStr = [NSString stringWithFormat:@"https://%@/xrpc/com.atproto.sync.getRepo?did=%@",
                        pdsHost,
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

    // Success: mark synced
    [_database markRepoSynced:did lastRev:lastRev ?: @"" error:nil];
    PDS_LOG_INFO(@"[AppView BackfillWorker] Completed backfill for %@ (rev=%@)", did, lastRev);
    [_delegate worker:self didCompleteForDID:did lastRev:lastRev ?: @""];
}

// ---------------------------------------------------------------------------
// PDS host resolution
// ---------------------------------------------------------------------------

- (nullable NSString *)_resolvePDSHostForDID:(NSString *)did {
    // did:web — host is in the DID itself
    if ([did hasPrefix:@"did:web:"]) {
        return [did substringFromIndex:8];
    }

    // did:plc — fetch from plc.directory
    NSString *plcURL = [NSString stringWithFormat:@"https://plc.directory/%@",
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

    // Extract pds service endpoint from DID document
    NSArray *services = doc[@"service"];
    for (NSDictionary *svc in services) {
        NSString *type = svc[@"type"];
        NSString *endpoint = svc[@"serviceEndpoint"];
        if ([type isEqualToString:@"AtprotoPersonalDataServer"] && endpoint.length > 0) {
            NSURL *epURL = [NSURL URLWithString:endpoint];
            return epURL.host;
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
    // A minimal CAR v1 parser.
    // CAR format: uvarint(header_len) | CBOR(header) | blocks...
    // Each block: uvarint(block_len) | CID | bytes
    //
    // For AppView backfill we need to find app.bsky.* lexicon records in the blocks.
    // We use basic heuristics since we don't have a full IPLD codec here:
    // look for CBOR-encoded dictionaries with a "$type" key.

    const uint8_t *bytes = (const uint8_t *)carData.bytes;
    NSUInteger len = carData.length;
    NSUInteger pos = 0;

    // Skip header (uvarint length + header bytes)
    uint64_t headerLen = 0;
    int bytesRead = [self _readUvarint:bytes + pos remaining:len - pos value:&headerLen];
    if (bytesRead <= 0) {
        if (error) *error = [NSError errorWithDomain:AppViewBackfillWorkerErrorDomain
                                                code:-1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid CAR header"}];
        return nil;
    }
    pos += bytesRead + headerLen;

    // Parse header CBOR to find roots (we skip this for now — just advance past it)
    // header was already skipped above

    NSString *lastRev = nil;
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];

    // Iterate blocks
    while (pos < len) {
        // uvarint block length
        uint64_t blockLen = 0;
        int nb = [self _readUvarint:bytes + pos remaining:len - pos value:&blockLen];
        if (nb <= 0 || blockLen == 0) break;
        pos += nb;

        if (pos + blockLen > len) break;
        NSData *blockData = [NSData dataWithBytes:bytes + pos length:(NSUInteger)blockLen];
        pos += blockLen;

        // Try to decode as CBOR dict — look for $type
        NSDictionary *decoded = [self _tryDecodeCBORDict:blockData];
        if (decoded && decoded[@"$type"]) {
            [records addObject:decoded];
        }
        // Capture rev from commit block
        if (decoded && decoded[@"rev"] && !lastRev) {
            lastRev = decoded[@"rev"];
        }
    }

    // Dispatch records to indexers
    for (NSDictionary *record in records) {
        NSString *collection = record[@"$type"];
        if (!collection) continue;

        for (id<AppViewIndexer> indexer in _indexers) {
            if ([indexer canIndexCollection:collection]) {
                NSError *indexErr = nil;
                BOOL ok = [indexer indexRecord:record
                                           did:did
                                    collection:collection
                                         error:&indexErr];
                if (!ok && indexErr) {
                    PDS_LOG_DEBUG(@"[AppView BackfillWorker] Dead-letter %@ for %@: %@",
                                  collection, did, indexErr.localizedDescription);
                    NSData *raw = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil]
                                  ?: [NSData data];
                    [_database recordDeadLetterEvent:collection
                                                seq:0
                                                did:did
                                                rev:lastRev
                                                cid:nil
                                          rawRecord:raw
                                    validationError:indexErr.localizedDescription ?: @"unknown"
                                              error:nil];
                }
                break; // Only first matching indexer handles a record
            }
        }
    }

    return lastRev;
}

// ---------------------------------------------------------------------------
// Minimal uvarint decoder
// ---------------------------------------------------------------------------

- (int)_readUvarint:(const uint8_t *)buf remaining:(NSUInteger)remaining value:(uint64_t *)outValue {
    uint64_t value = 0;
    int shift = 0;
    for (NSUInteger i = 0; i < remaining && i < 10; i++) {
        uint8_t b = buf[i];
        value |= ((uint64_t)(b & 0x7F)) << shift;
        shift += 7;
        if ((b & 0x80) == 0) {
            *outValue = value;
            return (int)(i + 1);
        }
    }
    return -1; // truncated
}

// ---------------------------------------------------------------------------
// Minimal CBOR map decoder (top-level only)
// ---------------------------------------------------------------------------

- (nullable NSDictionary *)_tryDecodeCBORDict:(NSData *)data {
    if (data.length == 0) return nil;
    const uint8_t *b = (const uint8_t *)data.bytes;
    NSUInteger len = data.length;
    NSUInteger pos = 0;

    // CBOR major type 5 = map, major type 6 = tag (skip CID prefix tags)
    uint8_t initial = b[pos];
    uint8_t majorType = (initial >> 5) & 0x07;

    // Skip CID prefix if present (0xd8 0x2a = tag 42)
    if (majorType == 6) {
        pos++; // skip tag byte
        if (pos >= len) return nil;
        // skip tag number (may be multi-byte but we only handle 0xd8 0x2a)
        if (b[pos - 1] == 0xd8 && pos < len) pos++; // two-byte tag
        if (pos >= len) return nil;
        initial = b[pos];
        majorType = (initial >> 5) & 0x07;
        // After tag likely comes a byte string (the CID bytes), skip it
        if (majorType == 2) {
            NSUInteger cidLen = 0;
            uint8_t addl = initial & 0x1F;
            pos++;
            if (addl <= 23) {
                cidLen = addl;
            } else if (addl == 24 && pos < len) {
                cidLen = b[pos++];
            } else {
                return nil;
            }
            pos += cidLen;
            if (pos >= len) return nil;
            initial = b[pos];
            majorType = (initial >> 5) & 0x07;
        }
    }

    if (majorType != 5) return nil; // not a map

    // Decode map count
    uint8_t addl = initial & 0x1F;
    NSUInteger mapCount = 0;
    pos++;
    if (addl <= 23) {
        mapCount = addl;
    } else if (addl == 24 && pos < len) {
        mapCount = b[pos++];
    } else {
        return nil; // too complex
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:mapCount];
    for (NSUInteger i = 0; i < mapCount; i++) {
        if (pos >= len) return nil;
        // Decode key (must be text string, major type 3)
        uint8_t keyInitial = b[pos];
        if ((keyInitial >> 5) != 3) return nil;
        NSUInteger keyLen = keyInitial & 0x1F;
        pos++;
        if (keyLen > 23) {
            if (pos >= len) return nil;
            keyLen = b[pos++];
        }
        if (pos + keyLen > len) return nil;
        NSString *key = [[NSString alloc] initWithBytes:b + pos
                                                 length:keyLen
                                               encoding:NSUTF8StringEncoding];
        pos += keyLen;
        if (!key) return nil;

        // Decode value (only handle text strings and nested for $type)
        if (pos >= len) return nil;
        uint8_t valInitial = b[pos];
        uint8_t valMajor = (valInitial >> 5) & 0x07;
        if (valMajor == 3) {
            // Text string
            NSUInteger valLen = valInitial & 0x1F;
            pos++;
            if (valLen > 23 && pos < len) valLen = b[pos++];
            if (pos + valLen > len) return nil;
            NSString *val = [[NSString alloc] initWithBytes:b + pos
                                                     length:valLen
                                                   encoding:NSUTF8StringEncoding];
            pos += valLen;
            if (val) result[key] = val;
        } else {
            // Skip value (variable width — use a rough skip)
            pos = [self _skipCBORValue:b atPos:pos length:len];
            if (pos == NSUIntegerMax) return nil;
        }
    }

    return result.count > 0 ? [result copy] : nil;
}

- (NSUInteger)_skipCBORValue:(const uint8_t *)b atPos:(NSUInteger)pos length:(NSUInteger)len {
    if (pos >= len) return NSUIntegerMax;
    uint8_t initial = b[pos];
    uint8_t major = (initial >> 5) & 0x07;
    uint8_t addl  = initial & 0x1F;
    pos++;

    NSUInteger count = 0;
    if (addl <= 23) {
        count = addl;
    } else if (addl == 24 && pos < len) {
        count = b[pos++];
    } else if (addl == 25 && pos + 1 < len) {
        count = ((NSUInteger)b[pos] << 8) | b[pos+1]; pos += 2;
    } else if (addl == 26 && pos + 3 < len) {
        count = ((NSUInteger)b[pos] << 24) | ((NSUInteger)b[pos+1] << 16)
              | ((NSUInteger)b[pos+2] << 8) | b[pos+3]; pos += 4;
    } else {
        return NSUIntegerMax;
    }

    switch (major) {
        case 0: case 1: return pos;                    // uint/int (no additional bytes beyond count)
        case 2: case 3: return pos + count;             // byte/text string
        case 4: {                                        // array
            for (NSUInteger i = 0; i < count; i++) {
                pos = [self _skipCBORValue:b atPos:pos length:len];
                if (pos == NSUIntegerMax) return NSUIntegerMax;
            }
            return pos;
        }
        case 5: {                                        // map
            for (NSUInteger i = 0; i < count * 2; i++) {
                pos = [self _skipCBORValue:b atPos:pos length:len];
                if (pos == NSUIntegerMax) return NSUIntegerMax;
            }
            return pos;
        }
        case 6: return [self _skipCBORValue:b atPos:pos length:len]; // tag
        case 7: return pos; // simple/float
    }
    return NSUIntegerMax;
}

// ---------------------------------------------------------------------------
// Error helpers
// ---------------------------------------------------------------------------

- (void)_failWithMessage:(NSString *)msg statusCode:(NSInteger)code {
    [_database recordBackfillError:_did message:msg error:nil];
    NSError *err = [NSError errorWithDomain:AppViewBackfillWorkerErrorDomain
                                       code:code
                                   userInfo:@{NSLocalizedDescriptionKey: msg}];
    [_delegate worker:self didFailForDID:_did error:err rateLimitedUntil:nil];
}

- (void)_failWithError:(NSError *)err rateLimitedUntil:(nullable NSDate *)until {
    [_database recordBackfillError:_did message:err.localizedDescription ?: @"" error:nil];
    [_delegate worker:self didFailForDID:_did error:err rateLimitedUntil:until];
}

@end
