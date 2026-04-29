/*!
 @file PDSActorStore+Blob.m
 @abstract PDSActorStore category implementation for blob-related database operations.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSActorStore+Blob.h"
#import "PDSActorStoreInternal.h"
#import "Core/ATProtoError.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/PDSDatabase.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// Force static linkers to retain this category object file in Linux builds.
void PDSActorStoreLinkBlobCategory(void) {}

static NSData *PDSActorStoreBlobCursorData(NSString *cursor, NSError **error) {
    NSData *cursorData = [[NSData alloc] initWithBase64EncodedString:cursor ?: @"" options:0];
    if (cursorData.length == 0) {
        if (error) {
            *error = [ATProtoError invalidInputWithMessage:@"Invalid blob cursor"];
        }
        return nil;
    }
    return cursorData;
}

@implementation PDSActorStore (Blob)

#pragma mark - Blob Operations

- (PDSDatabaseBlob *)blobFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0)
                              length:sqlite3_column_bytes(stmt, 0)];
    blob.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];

    if (sqlite3_column_type(stmt, 2) != SQLITE_NULL) {
        blob.mimeType = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
    }

    blob.size = sqlite3_column_int64(stmt, 3);
    blob.createdAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 4)];

    return blob;
}

- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO blobs (cid, did, mimeType, size, created_at) VALUES (?, ?, ?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;

    if (blob.cid) {
        sqlite3_bind_blob(stmt, 1, blob.cid.bytes, (int)blob.cid.length, SQLITE_TRANSIENT);
    }
    sqlite3_bind_text(stmt, 2, blob.did.UTF8String, -1, SQLITE_TRANSIENT);

    if (blob.mimeType) {
        sqlite3_bind_text(stmt, 3, blob.mimeType.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3);
    }

    sqlite3_bind_int64(stmt, 4, blob.size);
    sqlite3_bind_double(stmt, 5, blob.createdAt.timeIntervalSince1970);

    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

- (nullable PDSDatabaseBlob *)getBlobForCID:(NSData *)cid error:(NSError **)error {
    __block PDSDatabaseBlob *blob = nil;
    __block NSError *blockError = nil;

    void (^workBlock)(void) = ^{
        NSString *sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE cid = ?";
        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            blob = [self blobFromStatement:stmt];
        }
    };

    if (dispatch_get_specific(kPDSActorStoreQueueKey)) {
        workBlock();
    } else {
        dispatch_sync(self.transactionQueue, workBlock);
    }

    if (error && blockError) {
        *error = blockError;
    }
    return blob;
}

- (NSArray<PDSDatabaseBlob *> *)listBlobsForDid:(NSString *)did
                                           limit:(NSUInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error {
    __block NSMutableArray<PDSDatabaseBlob *> *blobs = [NSMutableArray array];
    __block NSError *blockError = nil;
    NSData *decodedCursor = nil;
    if (cursor) {
        decodedCursor = PDSActorStoreBlobCursorData(cursor, &blockError);
        if (!decodedCursor) {
            if (error && blockError) {
                *error = blockError;
            }
            return blobs;
        }
    }

    void (^workBlock)(void) = ^{
        NSString *sql;
        if (cursor) {
            sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE did = ? AND cid > ? ORDER BY cid LIMIT ?";
        } else {
            sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE did = ? ORDER BY cid LIMIT ?";
        }

        NSError *prepError = nil;
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:&prepError];
        if (!stmt) {
            blockError = prepError;
            return;
        }

        int idx = 1;
        sqlite3_bind_text(stmt, idx++, did.UTF8String, -1, SQLITE_TRANSIENT);

        if (cursor) {
            sqlite3_bind_blob(stmt, idx++, decodedCursor.bytes, (int)decodedCursor.length, SQLITE_TRANSIENT);
        }

        sqlite3_bind_int(stmt, idx++, (int)limit);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [blobs addObject:[self blobFromStatement:stmt]];
        }
    };

    if (dispatch_get_specific(kPDSActorStoreQueueKey)) {
        workBlock();
    } else {
        dispatch_sync(self.transactionQueue, workBlock);
    }

    if (error && blockError) {
        *error = blockError;
    }
    return blobs;
}

- (BOOL)deleteBlobForCID:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM blobs WHERE cid = ? AND did = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;

    sqlite3_bind_blob(stmt, 1, cid.bytes, (int)cid.length, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);

    BOOL success = (sqlite3_step(stmt) == SQLITE_DONE);
    return success;
}

@end

#pragma clang diagnostic pop
