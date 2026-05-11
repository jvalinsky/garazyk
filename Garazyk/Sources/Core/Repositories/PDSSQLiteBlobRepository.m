// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSQLiteBlobRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/PDSDatabase.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import <sqlite3.h>

@implementation PDSSQLiteBlobRepository {
    PDSDatabasePool *_databasePool;
}

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    self = [super init];
    if (self) {
        _databasePool = databasePool;
    }
    return self;
}

#pragma mark - PDSBlobRepository

- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:blob.did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT OR REPLACE INTO blobs (cid, did, mimeType, size, created_at) VALUES (?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_blob(stmt, 1, blob.cid.bytes, (int)blob.cid.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, blob.did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, blob.mimeType.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 4, (int)blob.size);
        sqlite3_bind_double(stmt, 5, blob.createdAt.timeIntervalSince1970);

        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

- (nullable PDSDatabaseBlob *)blobWithCid:(NSData *)cid did:(NSString *)did error:(NSError **)error {
    __block PDSDatabaseBlob *blob = nil;
    [_databasePool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM blobs WHERE cid = ? AND did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            blob = [self blobFromStatement:stmt];
        }
        [store finalizeStatement:stmt];
    } error:error];
    return blob;
}

- (nullable NSArray<PDSDatabaseBlob *> *)blobsForDid:(NSString *)did 
                                               limit:(NSInteger)limit 
                                              offset:(NSInteger)offset 
                                               error:(NSError **)error {
    __block NSMutableArray<PDSDatabaseBlob *> *blobs = [NSMutableArray array];
    [_databasePool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM blobs WHERE did = ? LIMIT ? OFFSET ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 2, (int)limit);
        sqlite3_bind_int(stmt, 3, (int)offset);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            PDSDatabaseBlob *blob = [self blobFromStatement:stmt];
            if (blob) [blobs addObject:blob];
        }
        [store finalizeStatement:stmt];
    } error:error];
    return [blobs copy];
}

- (NSInteger)blobCountForDid:(NSString *)did error:(NSError **)error {
    __block NSInteger count = 0;
    [_databasePool readWithDid:did block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT COUNT(*) FROM blobs WHERE did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = sqlite3_column_int(stmt, 0);
        }
        [store finalizeStatement:stmt];
    } error:error];
    return count;
}

- (BOOL)deleteBlob:(NSData *)cid did:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"DELETE FROM blobs WHERE cid = ? AND did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

- (nullable NSData *)blobForId:(NSString *)blobId error:(NSError **)error {
    // blobId is CID string
    NSData *cidBytes = [self dataFromCidString:blobId];
    if (!cidBytes) return nil;
    
    __block NSData *data = nil;
    // We need to find which DID this blob belongs to, or try __service__
    // The protocol doesn't take DID, but the implementation does.
    // This is a mapping issue. For now, let's assume we can find it in __service__
    // or we'll need to update the protocol.
    [_databasePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT * FROM blobs WHERE cid = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;
        
        sqlite3_bind_blob(stmt, 1, cidBytes.bytes, (int)cidBytes.length, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
             PDSDatabaseBlob *blob = [self blobFromStatement:stmt];
             // The ACTUAL blob data is in the blob storage, not DB.
             // This repo only holds metadata.
        }
        [store finalizeStatement:stmt];
    } error:error];
    return data; 
}

- (BOOL)deleteBlob:(NSString *)blobId error:(NSError **)error {
    NSData *cidBytes = [self dataFromCidString:blobId];
    if (!cidBytes) return NO;
    return [self deleteBlob:cidBytes did:@"__service__" error:error];
}

- (BOOL)hasBlob:(NSString *)blobId error:(NSError **)error {
    NSData *cidBytes = [self dataFromCidString:blobId];
    if (!cidBytes) return NO;
    PDSDatabaseBlob *blob = [self blobWithCid:cidBytes did:@"__service__" error:error];
    return blob != nil;
}

- (NSData *)dataFromCidString:(NSString *)cidString {
    CID *cid = [CID cidFromString:cidString];
    return cid.bytes;
}

- (PDSDatabaseBlob *)blobFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    
    int blobBytes = sqlite3_column_bytes(stmt, 0);
    if (blobBytes > 0) {
        blob.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:blobBytes];
    }
    
    blob.did = @((const char *)sqlite3_column_text(stmt, 1));
    
    const char *mimeTypeText = (const char *)sqlite3_column_text(stmt, 2);
    if (mimeTypeText) {
        blob.mimeType = @(mimeTypeText);
    }
    
    blob.size = sqlite3_column_int(stmt, 3);
    
    const char *createdAtText = (const char *)sqlite3_column_text(stmt, 4);
    if (createdAtText) {
        // Use timeIntervalSince1970 if stored as double, or parse if string
        blob.createdAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 4)];
    }
    
    return blob;
}

@end
