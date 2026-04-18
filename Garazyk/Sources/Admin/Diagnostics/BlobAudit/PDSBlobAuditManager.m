#import "PDSBlobAuditManager.h"
#import "PDSBlobOrphanScanOperation.h"
#import "PDSBlobCIDVerificationOperation.h"
#import "PDSBlobConsistencyCheckOperation.h"
#import "PDSBlobReferenceScanOperation.h"
#import "Blob/BlobStorage.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import <sqlite3.h>

@interface PDSBlobAuditManager ()
@property (nonatomic, strong, readwrite) NSOperationQueue *auditQueue;
@property (nonatomic, strong) BlobStorage *blobStorage;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSOperation *> *jobMap;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation PDSBlobAuditManager

- (instancetype)initWithBlobStorage:(BlobStorage *)blobStorage
                 serviceDatabases:(PDSServiceDatabases *)serviceDatabases {
    if ((self = [super init])) {
        _blobStorage = blobStorage;
        _serviceDatabases = serviceDatabases;
        _jobMap = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.atproto.pds.diagnostics.auditmanager", DISPATCH_QUEUE_SERIAL);

        // Create operation queue with serial execution
        _auditQueue = [[NSOperationQueue alloc] init];
        _auditQueue.maxConcurrentOperationCount = 1;
        _auditQueue.qualityOfService = NSQualityOfServiceBackground;
    }
    return self;
}

- (nullable NSString *)startAuditWithType:(NSString *)type dryRun:(BOOL)dryRun {
    NSString *jobId = [[NSUUID UUID] UUIDString];

    // Insert job record into database
    NSError *error = nil;
    if (![self insertJobRecord:jobId type:type error:&error]) {
        PDS_LOG_DB_ERROR(@"Failed to insert job record: %@", error);
        return nil;
    }

    // Create and queue operation
    PDSBlobAuditOperation *operation = [self createOperationForType:type
                                                              jobId:jobId
                                                             dryRun:dryRun];
    if (operation) {
        dispatch_async(self.queue, ^{
            self.jobMap[jobId] = operation;
        });

        [self.auditQueue addOperation:operation];
        return jobId;
    }

    return nil;
}

- (PDSBlobAuditOperation *)createOperationForType:(NSString *)type
                                            jobId:(NSString *)jobId
                                           dryRun:(BOOL)dryRun {
    if ([type isEqualToString:@"orphans"]) {
        return [[PDSBlobOrphanScanOperation alloc] initWithJobId:jobId
                                                       auditType:type
                                                     blobStorage:self.blobStorage
                                                 serviceDatabases:self.serviceDatabases
                                                          dryRun:dryRun];
    } else if ([type isEqualToString:@"cid_verify"]) {
        return [[PDSBlobCIDVerificationOperation alloc] initWithJobId:jobId
                                                            auditType:type
                                                          blobStorage:self.blobStorage
                                                      serviceDatabases:self.serviceDatabases
                                                               dryRun:dryRun];
    } else if ([type isEqualToString:@"consistency"]) {
        return [[PDSBlobConsistencyCheckOperation alloc] initWithJobId:jobId
                                                             auditType:type
                                                           blobStorage:self.blobStorage
                                                       serviceDatabases:self.serviceDatabases
                                                                dryRun:dryRun];
    } else if ([type isEqualToString:@"references"]) {
        return [[PDSBlobReferenceScanOperation alloc] initWithJobId:jobId
                                                          auditType:type
                                                        blobStorage:self.blobStorage
                                                    serviceDatabases:self.serviceDatabases
                                                             dryRun:dryRun];
    }

    return nil;
}

- (BOOL)insertJobRecord:(NSString *)jobId type:(NSString *)type error:(NSError **)error {
    sqlite3 *db = [self.serviceDatabases serviceDatabase];
    if (!db) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        return NO;
    }

    NSString *sql = @"INSERT INTO blob_audit_jobs "
                    @"(id, job_type, status, progress, created_at) "
                    @"VALUES (?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                         code:sqlite3_extended_errcode(db)
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(db)]}];
        }
        return NO;
    }

    sqlite3_bind_text(stmt, 1, jobId.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, type.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, "pending", -1, SQLITE_STATIC);
    sqlite3_bind_double(stmt, 4, 0.0);
    sqlite3_bind_int64(stmt, 5, (long)[[NSDate date] timeIntervalSince1970]);

    BOOL success = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);

    return success;
}

- (nullable NSDictionary *)jobStatusForId:(NSString *)jobId {
    sqlite3 *db = [self.serviceDatabases serviceDatabase];
    if (!db) return nil;

    NSString *sql = @"SELECT job_type, status, progress, started_at, completed_at, results, error "
                    @"FROM blob_audit_jobs "
                    @"WHERE id = ?";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        return nil;
    }

    sqlite3_bind_text(stmt, 1, jobId.UTF8String, -1, SQLITE_TRANSIENT);

    NSDictionary *result = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        NSString *jobType = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        NSString *status = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        double progress = sqlite3_column_double(stmt, 2);
        long startedAt = sqlite3_column_int64(stmt, 3);
        long completedAt = sqlite3_column_int64(stmt, 4);
        NSString *resultsJSON = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 5)];
        NSString *errorMsg = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 6)];

        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"jobId"] = jobId;
        dict[@"job_type"] = jobType;
        dict[@"status"] = status;
        dict[@"progress"] = @(progress);
        if (startedAt > 0) dict[@"startedAt"] = @(startedAt);
        if (completedAt > 0) dict[@"completedAt"] = @(completedAt);
        if (resultsJSON) {
            NSData *data = [resultsJSON dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (parsed) dict[@"results"] = parsed;
        }
        if (errorMsg) dict[@"error"] = errorMsg;

        result = [dict copy];
    }

    sqlite3_finalize(stmt);
    return result;
}

- (BOOL)cancelJobWithId:(NSString *)jobId {
    __block BOOL cancelled = NO;

    dispatch_sync(self.queue, ^{
        NSOperation *operation = self.jobMap[jobId];
        if (operation && !operation.isFinished) {
            [operation cancel];
            cancelled = YES;
        }
    });

    return cancelled;
}

- (nullable NSArray<NSDictionary *> *)recentJobs:(NSInteger)limit {
    sqlite3 *db = [self.serviceDatabases serviceDatabase];
    if (!db) return nil;

    NSString *sql = @"SELECT id, job_type, status, progress, created_at "
                    @"FROM blob_audit_jobs "
                    @"ORDER BY created_at DESC "
                    @"LIMIT ?";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        return nil;
    }

    sqlite3_bind_int64(stmt, 1, limit);

    NSMutableArray *results = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSString *jobId = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        NSString *jobType = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        NSString *status = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        double progress = sqlite3_column_double(stmt, 3);
        long createdAt = sqlite3_column_int64(stmt, 4);

        NSDictionary *job = @{
            @"jobId": jobId,
            @"job_type": jobType,
            @"status": status,
            @"progress": @(progress),
            @"createdAt": @(createdAt)
        };
        [results addObject:job];
    }

    sqlite3_finalize(stmt);
    return results.count > 0 ? results : nil;
}

- (BOOL)pruneJobsOlderThan:(NSInteger)olderThanDays error:(NSError **)error {
    sqlite3 *db = [self.serviceDatabases serviceDatabase];
    if (!db) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        return NO;
    }

    NSTimeInterval cutoff = [NSDate timeIntervalSinceReferenceDate] - (olderThanDays * 24 * 3600);

    NSString *sql = @"DELETE FROM blob_audit_jobs WHERE created_at < ?";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                         code:sqlite3_extended_errcode(db)
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(db)]}];
        }
        return NO;
    }

    sqlite3_bind_int64(stmt, 1, (long)cutoff);
    BOOL success = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);

    return success;
}

@end
