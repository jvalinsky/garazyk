#import "TutorialBlobStore.h"
#import "TutorialCIDGenerator.h"
#import "TutorialSQLiteHelper.h"

NSString * const TutorialBlobErrorDomain = @"com.atproto.tutorial.blob";

@interface TutorialBlobStore ()
@property (nonatomic, copy) NSString *dataDir;
@property (nonatomic, strong) TutorialSQLiteHelper *db;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation TutorialBlobStore

- (instancetype)initWithDataDirectory:(NSString *)dataDir {
    self = [super init];
    if (!self) return nil;

    _dataDir = [dataDir copy];
    _maxBlobSize = 1024 * 1024;       // 1MB default
    _maxQuotaPerDID = 100 * 1024 * 1024; // 100MB default
    _queue = dispatch_queue_create("com.atproto.tutorial.blob", DISPATCH_QUEUE_SERIAL);

    // Create data directory
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dataDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Create blobs subdirectory
    NSString *blobsDir = [dataDir stringByAppendingPathComponent:@"blobs"];
    [fm createDirectoryAtPath:blobsDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Open metadata database
    NSString *dbPath = [dataDir stringByAppendingPathComponent:@"blobs.db"];
    _db = [[TutorialSQLiteHelper alloc] initWithPath:dbPath];
    if (!_db) return nil;

    [self createTablesIfNeeded];
    return self;
}

- (void)createTablesIfNeeded {
    NSError *error = nil;
    [self.db executeUpdate:&error sql:@"CREATE TABLE IF NOT EXISTS blobs ("
        @"cid TEXT PRIMARY KEY, "
        @"did TEXT NOT NULL, "
        @"mime_type TEXT NOT NULL, "
        @"size INTEGER NOT NULL, "
        @"created_at REAL NOT NULL"
        @")"];
    if (error) {
        NSLog(@"Warning: blob table creation error: %@", error.localizedDescription);
    }

    [self.db executeUpdate:&error sql:@"CREATE INDEX IF NOT EXISTS idx_blobs_did ON blobs(did)"];
}

- (nullable NSString *)putBlob:(NSData *)data
                        forDID:(NSString *)did
                      mimeType:(NSString *)mimeType
                         error:(NSError **)error {
    // Validate MIME type
    if (![self isValidMIMEType:mimeType]) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialBlobErrorDomain
                                         code:TutorialBlobErrorInvalidMIMEType
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid MIME type"}];
        }
        return nil;
    }

    // Check size limit
    if (data.length > self.maxBlobSize) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialBlobErrorDomain
                                         code:TutorialBlobErrorBlobTooLarge
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Blob size %lu exceeds limit %lu",
                                             (unsigned long)data.length, (unsigned long)self.maxBlobSize]}];
        }
        return nil;
    }

    // Check quota
    NSUInteger currentUsage = [self quotaUsedForDID:did];
    if (currentUsage + data.length > self.maxQuotaPerDID) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialBlobErrorDomain
                                         code:TutorialBlobErrorQuotaExceeded
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID storage quota exceeded"}];
        }
        return nil;
    }

    // Generate CID from content
    NSString *cid = [TutorialCIDGenerator generateCIDForData:data];

    // Write blob file
    NSString *blobPath = [self blobPathForCID:cid];
    NSError *writeError = nil;
    if (![data writeToFile:blobPath options:NSDataWritingAtomic error:&writeError]) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialBlobErrorDomain
                                         code:TutorialBlobErrorWriteFailed
                                     userInfo:@{NSLocalizedDescriptionKey: writeError.localizedDescription}];
        }
        return nil;
    }

    // Store metadata
    __block NSError *blockError = nil;
    [self.db executeSync:&blockError block:^(sqlite3 *db) {
        const char *sql = "INSERT OR REPLACE INTO blobs (cid, did, mime_type, size, created_at) VALUES (?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:TutorialBlobErrorDomain code:rc userInfo:nil];
            return;
        }

        sqlite3_bind_text(stmt, 1, [cid UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, [mimeType UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 4, (sqlite3_int64)data.length);
        sqlite3_bind_double(stmt, 5, [[NSDate date] timeIntervalSince1970]);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        if (rc != SQLITE_DONE) {
            blockError = [NSError errorWithDomain:TutorialBlobErrorDomain code:rc userInfo:nil];
        }
    }];

    if (blockError) {
        if (error) *error = blockError;
        return nil;
    }

    return cid;
}

- (nullable NSData *)getBlob:(NSString *)cid
                      forDID:(NSString *)did
                outMimeType:(NSString * _Nullable __autoreleasing * _Nullable)outMimeType
                     outSize:(NSUInteger * _Nullable)outSize
                       error:(NSError **)error {
    return [self getBlob:cid forDID:did range:NSMakeRange(NSNotFound, 0) outMimeType:outMimeType outSize:outSize error:error];
}

- (nullable NSData *)getBlob:(NSString *)cid
                      forDID:(NSString *)did
                       range:(NSRange)range
                outMimeType:(NSString * _Nullable __autoreleasing * _Nullable)outMimeType
                     outSize:(NSUInteger * _Nullable)outSize
                       error:(NSError **)error {
    // Look up metadata
    __block NSString *mimeType = nil;
    __block NSUInteger blobSize = 0;
    __block BOOL found = NO;

    __block NSError *blockError = nil;
    [self.db executeSync:&blockError block:^(sqlite3 *db) {
        const char *sql = "SELECT mime_type, size FROM blobs WHERE cid = ? AND did = ?";
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:TutorialBlobErrorDomain code:rc userInfo:nil];
            return;
        }

        sqlite3_bind_text(stmt, 1, [cid UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            mimeType = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
            blobSize = (NSUInteger)sqlite3_column_int64(stmt, 1);
            found = YES;
        }

        sqlite3_finalize(stmt);
    }];

    if (!found) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialBlobErrorDomain
                                         code:TutorialBlobErrorNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob not found"}];
        }
        return nil;
    }

    if (outMimeType) *outMimeType = mimeType;
    if (outSize) *outSize = blobSize;

    // Read blob file
    NSString *blobPath = [self blobPathForCID:cid];
    NSData *blobData = [NSData dataWithContentsOfFile:blobPath];

    if (!blobData) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialBlobErrorDomain
                                         code:TutorialBlobErrorReadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to read blob file"}];
        }
        return nil;
    }

    // Handle range request
    if (range.location != NSNotFound) {
        NSUInteger end = NSMaxRange(range);
        if (end > blobData.length) end = blobData.length;
        if (range.location >= blobData.length) {
            return [NSData data];
        }
        return [blobData subdataWithRange:NSMakeRange(range.location, end - range.location)];
    }

    return blobData;
}

- (BOOL)deleteBlob:(NSString *)cid
            forDID:(NSString *)did
             error:(NSError **)error {
    // Delete from database
    __block BOOL success = NO;
    [self.db executeSync:error block:^(sqlite3 *db) {
        const char *sql = "DELETE FROM blobs WHERE cid = ? AND did = ?";
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) return;

        sqlite3_bind_text(stmt, 1, [cid UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
        success = (rc == SQLITE_DONE && sqlite3_changes(db) > 0);
    }];

    if (success) {
        // Delete blob file
        NSString *blobPath = [self blobPathForCID:cid];
        [[NSFileManager defaultManager] removeItemAtPath:blobPath error:nil];
    }

    return success;
}

- (nullable NSArray<NSDictionary *> *)listBlobsForDID:(NSString *)did
                                                limit:(NSUInteger)limit
                                               cursor:(nullable NSString *)cursor
                                                error:(NSError **)error {
    __block NSError *blockError = nil;
    NSArray<NSDictionary *> *results = [self.db executeUnsafeRawQuery:&blockError block:^id(sqlite3 *db) {
        NSString *sql;
        if (cursor) {
            sql = @"SELECT cid, mime_type, size FROM blobs WHERE did = ? AND cid > ? ORDER BY cid LIMIT ?";
        } else {
            sql = @"SELECT cid, mime_type, size FROM blobs WHERE did = ? ORDER BY cid LIMIT ?";
        }

        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:TutorialBlobErrorDomain code:rc userInfo:nil];
            return nil;
        }

        int paramIdx = 1;
        sqlite3_bind_text(stmt, paramIdx++, [did UTF8String], -1, SQLITE_TRANSIENT);
        if (cursor) {
            sqlite3_bind_text(stmt, paramIdx++, [cursor UTF8String], -1, SQLITE_TRANSIENT);
        }
        sqlite3_bind_int64(stmt, paramIdx, (sqlite3_int64)limit);

        NSMutableArray *results = [NSMutableArray array];
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [results addObject:@{
                @"cid": [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)],
                @"mimeType": [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)],
                @"size": @(sqlite3_column_int64(stmt, 2))
            }];
        }

        sqlite3_finalize(stmt);
        return results;
    }];

    if (blockError) {
        if (error) *error = blockError;
        return nil;
    }

    return results;
}

#pragma mark - Private

- (NSString *)blobPathForCID:(NSString *)cid {
    // Use first 2 chars as subdirectory for filesystem performance
    NSString *prefix = [cid substringToIndex:MIN(2, cid.length)];
    NSString *subdir = [self.dataDir stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"blobs/%@", prefix]];
    [[NSFileManager defaultManager] createDirectoryAtPath:subdir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    return [subdir stringByAppendingPathComponent:cid];
}

- (NSUInteger)quotaUsedForDID:(NSString *)did {
    __block NSUInteger totalSize = 0;
    [self.db executeSync:nil block:^(sqlite3 *db) {
        const char *sql = "SELECT SUM(size) FROM blobs WHERE did = ?";
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) return;

        sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL) {
            totalSize = (NSUInteger)sqlite3_column_int64(stmt, 0);
        }

        sqlite3_finalize(stmt);
    }];
    return totalSize;
}

- (BOOL)isValidMIMEType:(NSString *)mimeType {
    // Basic validation: must contain a slash
    NSRange slashRange = [mimeType rangeOfString:@"/"];
    if (slashRange.location == NSNotFound || slashRange.location == 0 || slashRange.location == mimeType.length - 1) {
        return NO;
    }
    return YES;
}

@end
