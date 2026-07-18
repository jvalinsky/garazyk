// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSActorStore+Blob.m
 @abstract PDSActorStore category implementation for blob-related database operations.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSActorStore+Blob.h"
#import "PDSActorStoreInternal.h"
#import "Core/ATProtoError.h"
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

- (PDSDatabaseBlob *)blobFromDictionary:(NSDictionary *)row {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = row[@"cid"];
    blob.did = row[@"did"];
    blob.mimeType = row[@"mimeType"];
    blob.size = [row[@"size"] longLongValue];
    blob.createdAt = [NSDate dateWithTimeIntervalSince1970:[row[@"created_at"] doubleValue]];
    return blob;
}

- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error {
    NSString *sql = @"INSERT INTO blobs (cid, did, mimeType, size, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(cid) DO UPDATE SET did=excluded.did, mimeType=excluded.mimeType, size=excluded.size, created_at=excluded.created_at";
    NSArray *params = @[
        blob.cid ?: [NSNull null],
        blob.did ?: @"",
        blob.mimeType ?: [NSNull null],
        @(blob.size),
        @(blob.createdAt.timeIntervalSince1970)
    ];
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (nullable PDSDatabaseBlob *)getBlobForCID:(NSData *)cid error:(NSError **)error {
    NSString *sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE cid = ?";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[cid] error:error];
    if (results.count > 0) {
        return [self blobFromDictionary:results.firstObject];
    }
    return nil;
}

- (NSArray<PDSDatabaseBlob *> *)listBlobsForDid:(NSString *)did
                                           limit:(NSUInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error {
    NSData *decodedCursor = nil;
    if (cursor) {
        decodedCursor = PDSActorStoreBlobCursorData(cursor, error);
        if (!decodedCursor) return @[];
    }

    NSString *sql;
    NSMutableArray *params = [NSMutableArray array];
    [params addObject:did];
    if (decodedCursor) {
        sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE did = ? AND cid > ? ORDER BY cid LIMIT ?";
        [params addObject:decodedCursor];
    } else {
        sql = @"SELECT cid, did, mimeType, size, created_at FROM blobs WHERE did = ? ORDER BY cid LIMIT ?";
    }
    [params addObject:@(limit)];

    NSArray *results = [self.database executeParameterizedQuery:sql params:params error:error];
    NSMutableArray *blobs = [NSMutableArray arrayWithCapacity:results.count];
    for (NSDictionary *row in results) {
        [blobs addObject:[self blobFromDictionary:row]];
    }
    return [blobs copy];
}

- (BOOL)deleteBlobForCID:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM blobs WHERE cid = ? AND did = ?";
    return [self.database executeParameterizedUpdate:sql params:@[cid, did] error:error];
}

@end

#pragma clang diagnostic pop
