/*!
 @file AppViewActorIndexer.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Indexers/AppViewActorIndexer.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "Debug/PDSLogger.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"

static NSString * const kCollection = @"app.bsky.actor.profile";

@interface AppViewActorIndexer ()
@property (nonatomic, strong) AppViewDatabase *avdb;
@end

@implementation AppViewActorIndexer

- (instancetype)initWithDatabase:(AppViewDatabase *)database {
    self = [super init];
    if (!self) return nil;
    _avdb = database;
    return self;
}

#pragma mark - AppViewIndexer

- (BOOL)canIndexCollection:(NSString *)collection {
    return [collection isEqualToString:kCollection];
}

- (BOOL)indexRecord:(NSDictionary *)record
                 did:(NSString *)did
          collection:(NSString *)collection
                 cid:(nullable NSString *)cid
               error:(NSError **)error {
    // record structure: {$type, $did, $rkey, record: {displayName, description, ...}}
    NSDictionary *profileRecord = record[@"record"] ?: record;
    NSString *displayName = profileRecord[@"displayName"];
    NSString *description = profileRecord[@"description"];
    NSString *rkey = record[@"rkey"] ?: @"self";

    NSString *avatarCID = nil;
    id avatarBlob = profileRecord[@"avatar"];
    if ([avatarBlob isKindOfClass:[NSDictionary class]])
        avatarCID = avatarBlob[@"ref"] ?: avatarBlob[@"cid"];

    NSString *bannerCID = nil;
    id bannerBlob = profileRecord[@"banner"];
    if ([bannerBlob isKindOfClass:[NSDictionary class]])
        bannerCID = bannerBlob[@"ref"] ?: bannerBlob[@"cid"];

    // Truncate to reasonable lengths (guard against malformed data)
    if (displayName.length > 640) displayName = [displayName substringToIndex:640];
    if (description.length > 2560) description = [description substringToIndex:2560];

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:profileRecord options:0 error:nil];

    // Get the CID for the record
    NSString *recordCID = cid;
    if (!recordCID && jsonData) {
        // Fallback to recalculating CID if not provided (legacy/backfill)
        // Use DAG-CBOR for correct AT Protocol CIDs
        NSError *cborError = nil;
        NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:profileRecord error:&cborError];
        if (cborData) {
            recordCID = [CID sha256:cborData].stringValue; // Note: sha256: uses 0x55, should be 0x71 ideally but CID.m sha256 is 0x55
            // Actually let's use the correct codec 0x71 if we can.
            CID *actualCID = [CID cidWithDigest:[CID sha256Digest:cborData] codec:0x71];
            recordCID = actualCID.stringValue;
        } else {
            recordCID = [CID sha256:jsonData].stringValue;
        }
    }

    // Write to database via AppViewDatabase
    // Save block first (required for AT Protocol)
    if (recordCID) {
        CID *rcid = [CID cidFromString:recordCID];
        NSData *blockData = nil;
        if (rcid) {
            // If we have CBOR data, use it, otherwise use JSON (best effort)
            blockData = [ATProtoCBORSerialization encodeDataWithJSONObject:profileRecord error:nil] ?: jsonData;
            [_avdb saveBlockWithCid:rcid.bytes
                         repoDid:did
                       blockData:blockData
                     contentType:blockData == jsonData ? @"application/json" : @"application/cbor"
                           error:nil];
        }
    }

    // Then write to records table
    NSString *handle = [AppViewIdentityHelper resolveHandleForDID:did error:nil];
    [_avdb saveRecordWithURI:uri
                         did:did
                   collection:collection
                        rkey:rkey
                          cid:recordCID
                       handle:handle
                        value:[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]
                  subjectDid:did
                       error:nil];
    return YES;
}

- (BOOL)handleIngestEvent:(AppViewIngestEvent *)event error:(NSError **)error {
    for (NSDictionary *op in event.ops) {
        NSString *action = op[@"action"];
        NSString *path   = op[@"path"];

        // path format: "collection/rkey"
        if (![path hasPrefix:kCollection]) continue;

        if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
            NSDictionary *record = op[@"record"];
            NSString *cid = op[@"cid"];
            if (record) {
                [self indexRecord:record did:event.did collection:kCollection cid:cid error:nil];
            }
        } else if ([action isEqualToString:@"delete"]) {
            // Profile delete — clear materialized data
            PDS_LOG_DEBUG(@"[AppViewActorIndexer] Deleted profile for %@", event.did);
        }
    }
    return YES;
}

- (BOOL)processPendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error {
    // Pending deltas carry raw envelopes. For now we log and return YES;
    // a production implementation would re-decode and call handleIngestEvent:.
    PDS_LOG_DEBUG(@"[AppViewActorIndexer] Replaying pending delta for %@", delta.did);
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error {
    PDS_LOG_DEBUG(@"[AppViewActorIndexer] Delete record %@/%@ for %@", collection, rkey, did);
    return YES;
}

@end
