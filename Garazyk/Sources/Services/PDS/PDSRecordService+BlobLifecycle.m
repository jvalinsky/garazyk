// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRecordService+BlobLifecycle.h"
#import "Admin/Diagnostics/BlobAudit/PDSBlobAuditUtils.h"
#import "Core/CID.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/Pool/DatabasePool.h"

@implementation PDSRecordService (BlobLifecycle)

- (BOOL)syncBlobReferencesForRecordURI:(NSString *)recordURI
                              recordValue:(NSDictionary *)recordValue
                                   forDid:(NSString *)did
                              transactor:(id<PDSActorStoreTransactor>)transactor
                                   error:(NSError **)error {
    NSSet<NSString *> *referenceCIDs = PDSBlobAuditBlobReferenceCIDsFromJSONObject(recordValue);
    PDSActorStore *store = (PDSActorStore *)transactor;
    NSMutableArray<NSData *> *previousCIDs = [NSMutableArray array];
    sqlite3_stmt *selectPrevious = [store prepareStatement:@"SELECT blob_cid FROM blob_refs WHERE record_uri = ?" error:error];
    if (!selectPrevious) return NO;

    sqlite3_bind_text(selectPrevious, 1, recordURI.UTF8String, -1, SQLITE_TRANSIENT);
    int stepResult = SQLITE_OK;
    while ((stepResult = sqlite3_step(selectPrevious)) == SQLITE_ROW) {
        const void *bytes = sqlite3_column_blob(selectPrevious, 0);
        int length = sqlite3_column_bytes(selectPrevious, 0);
        if (bytes && length > 0) {
            [previousCIDs addObject:[NSData dataWithBytes:bytes length:(NSUInteger)length]];
        }
    }
    [store finalizeStatement:selectPrevious];
    if (stepResult != SQLITE_DONE) {
        if (error) *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to read previous blob references"}];
        return NO;
    }

    sqlite3_stmt *deletePrevious = [store prepareStatement:@"DELETE FROM blob_refs WHERE record_uri = ?" error:error];
    if (!deletePrevious) return NO;
    sqlite3_bind_text(deletePrevious, 1, recordURI.UTF8String, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(deletePrevious) != SQLITE_DONE) {
        [store finalizeStatement:deletePrevious];
        if (error) *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to remove previous blob references"}];
        return NO;
    }
    [store finalizeStatement:deletePrevious];

    sqlite3_stmt *insertReference = [store prepareStatement:@"INSERT OR IGNORE INTO blob_refs (record_uri, blob_cid, did, created_at) SELECT ?, cid, ?, strftime('%Y-%m-%dT%H:%M:%fZ','now') FROM blobs WHERE cid = ? AND did = ?" error:error];
    sqlite3_stmt *promoteBlob = [store prepareStatement:@"UPDATE blobs SET state = 'referenced' WHERE cid = ? AND did = ? AND EXISTS (SELECT 1 FROM blob_refs WHERE record_uri = ? AND blob_cid = blobs.cid)" error:error];
    if (!insertReference || !promoteBlob) {
        if (insertReference) [store finalizeStatement:insertReference];
        if (promoteBlob) [store finalizeStatement:promoteBlob];
        return NO;
    }
    for (NSString *cidString in referenceCIDs) {
        CID *cid = [CID cidFromString:cidString];
        if (!cid) continue;
        NSData *cidBytes = cid.bytes;
        sqlite3_bind_text(insertReference, 1, recordURI.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(insertReference, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(insertReference, 3, cidBytes.bytes, (int)cidBytes.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(insertReference, 4, did.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(insertReference) != SQLITE_DONE) {
            [store finalizeStatement:insertReference];
            [store finalizeStatement:promoteBlob];
            if (error) *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create blob reference"}];
            return NO;
        }
        sqlite3_reset(insertReference);
        sqlite3_clear_bindings(insertReference);

        sqlite3_bind_blob(promoteBlob, 1, cidBytes.bytes, (int)cidBytes.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(promoteBlob, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(promoteBlob, 3, recordURI.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(promoteBlob) != SQLITE_DONE) {
            [store finalizeStatement:insertReference];
            [store finalizeStatement:promoteBlob];
            if (error) *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to promote referenced blob"}];
            return NO;
        }
        sqlite3_reset(promoteBlob);
        sqlite3_clear_bindings(promoteBlob);
    }
    [store finalizeStatement:insertReference];
    [store finalizeStatement:promoteBlob];

    sqlite3_stmt *deleteOrphan = [store prepareStatement:@"DELETE FROM blobs WHERE cid = ? AND did = ? AND NOT EXISTS (SELECT 1 FROM blob_refs WHERE blob_cid = ? AND did = ?)" error:error];
    if (!deleteOrphan) return NO;
    for (NSData *cidBytes in previousCIDs) {
        sqlite3_bind_blob(deleteOrphan, 1, cidBytes.bytes, (int)cidBytes.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(deleteOrphan, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(deleteOrphan, 3, cidBytes.bytes, (int)cidBytes.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(deleteOrphan, 4, did.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(deleteOrphan) != SQLITE_DONE) {
            [store finalizeStatement:deleteOrphan];
            if (error) *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to reclaim unreferenced blob"}];
            return NO;
        }
        sqlite3_reset(deleteOrphan);
        sqlite3_clear_bindings(deleteOrphan);
    }
    [store finalizeStatement:deleteOrphan];
    return YES;
}

- (BOOL)syncBlobReferencesForRecordURI:(NSString *)recordURI
                              recordValue:(NSDictionary *)recordValue
                                   forDid:(NSString *)did
                                    error:(NSError **)error {
    __block BOOL operationSucceeded = NO;
    BOOL transactionSucceeded =
        [self.databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
            operationSucceeded = [self syncBlobReferencesForRecordURI:recordURI
                                                           recordValue:recordValue
                                                                forDid:did
                                                            transactor:transactor
                                                                 error:blockError];
        } error:error];
    return transactionSucceeded && operationSucceeded;
}

- (BOOL)removeBlobReferencesForRecordURI:(NSString *)recordURI
                                  forDid:(NSString *)did
                             transactor:(id<PDSActorStoreTransactor>)transactor
                                  error:(NSError **)error {
    return [self syncBlobReferencesForRecordURI:recordURI recordValue:@{} forDid:did transactor:transactor error:error];
}

- (BOOL)removeBlobReferencesForRecordURI:(NSString *)recordURI
                                  forDid:(NSString *)did
                                   error:(NSError **)error {
    return [self syncBlobReferencesForRecordURI:recordURI recordValue:@{} forDid:did error:error];
}

@end
