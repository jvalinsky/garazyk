// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSBlobAuditManager.h"
#import "PDSBlobOrphanScanOperation.h"
#import "PDSBlobCIDVerificationOperation.h"
#import "PDSBlobConsistencyCheckOperation.h"
#import "PDSBlobReferenceScanOperation.h"
#import "Blob/BlobStorage.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"
#import <sqlite3.h>

static NSString *const PDSBlobAuditManagerErrorDomain = @"com.atproto.pds.diagnostics";

@interface PDSBlobAuditManager ()
@property (nonatomic, strong, readwrite) NSOperationQueue *auditQueue;
@property (nonatomic, strong) BlobStorage *blobStorage;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSOperation *> *jobMap;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
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
        if ([_auditQueue respondsToSelector:@selector(setQualityOfService:)]) {
            [_auditQueue performSelector:@selector(setQualityOfService:) withObject:@(NSQualityOfServiceBackground)];
        }
    }
    return self;
}

- (nullable NSString *)startAuditWithType:(NSString *)type dryRun:(BOOL)dryRun {
    NSString *jobId = [[NSUUID UUID] UUIDString];
    PDSBlobAuditOperation *operation = [self createOperationForType:type
                                                              jobId:jobId
                                                             dryRun:dryRun];
    if (!operation) {
        PDS_LOG_WARN(@"Unsupported blob audit type requested: %@", type);
        return nil;
    }

    // Insert job record into database
    NSError *error = nil;
    if (![self insertJobRecord:jobId type:type error:&error]) {
        PDS_LOG_DB_ERROR(@"Failed to insert job record: %@", error);
        return nil;
    }

    dispatch_async(self.queue, ^{
        self.jobMap[jobId] = operation;
    });

    [self.auditQueue addOperation:operation];
    return jobId;
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
    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        return NO;
    }

    NSString *sql = @"INSERT INTO blob_audit_jobs "
                    @"(id, job_type, status, progress, created_at) "
                    @"VALUES (?, ?, ?, ?, ?)";

    return [db executeParameterizedUpdate:sql
                                   params:@[jobId, type, @"pending", @0.0, @([[NSDate date] timeIntervalSince1970])]
                                    error:error];
}

- (nullable NSDictionary *)jobStatusForId:(NSString *)jobId {
    NSError *queryError = nil;
    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:&queryError];
    if (!db) return nil;

    NSString *sql = @"SELECT job_type, status, progress, started_at, completed_at, results, error "
                    @"FROM blob_audit_jobs "
                    @"WHERE id = ?";

    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:sql params:@[jobId] error:&queryError];
    NSDictionary *row = rows.firstObject;
    if (!row) {
        return nil;
    }

    NSString *jobType = [row[@"job_type"] isKindOfClass:[NSString class]] ? row[@"job_type"] : @"";
    NSString *status = [row[@"status"] isKindOfClass:[NSString class]] ? row[@"status"] : @"";
    NSNumber *progress = [row[@"progress"] isKindOfClass:[NSNumber class]] ? row[@"progress"] : @0.0;
    NSNumber *startedAt = [row[@"started_at"] isKindOfClass:[NSNumber class]] ? row[@"started_at"] : nil;
    NSNumber *completedAt = [row[@"completed_at"] isKindOfClass:[NSNumber class]] ? row[@"completed_at"] : nil;
    NSString *resultsJSON = [row[@"results"] isKindOfClass:[NSString class]] ? row[@"results"] : nil;
    NSString *errorMsg = [row[@"error"] isKindOfClass:[NSString class]] ? row[@"error"] : nil;

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"jobId"] = jobId;
    dict[@"job_type"] = jobType;
    dict[@"status"] = status;
    dict[@"progress"] = progress;
    if (startedAt.longLongValue > 0) dict[@"startedAt"] = startedAt;
    if (completedAt.longLongValue > 0) dict[@"completedAt"] = completedAt;
    if (resultsJSON) {
        NSData *data = [resultsJSON dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([parsed isKindOfClass:[NSDictionary class]]) dict[@"results"] = parsed;
    }
    if (errorMsg) dict[@"error"] = errorMsg;

    return [dict copy];
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
    NSError *queryError = nil;
    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:&queryError];
    if (!db) return nil;

    NSString *sql = @"SELECT id, job_type, status, progress, created_at "
                    @"FROM blob_audit_jobs "
                    @"ORDER BY created_at DESC "
                    @"LIMIT ?";

    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:sql params:@[@(limit)] error:&queryError];
    NSMutableArray<NSDictionary *> *results = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSString *jobId = [row[@"id"] isKindOfClass:[NSString class]] ? row[@"id"] : nil;
        NSString *jobType = [row[@"job_type"] isKindOfClass:[NSString class]] ? row[@"job_type"] : nil;
        NSString *status = [row[@"status"] isKindOfClass:[NSString class]] ? row[@"status"] : nil;
        NSNumber *progress = [row[@"progress"] isKindOfClass:[NSNumber class]] ? row[@"progress"] : @0.0;
        NSNumber *createdAt = [row[@"created_at"] isKindOfClass:[NSNumber class]] ? row[@"created_at"] : @0;
        if (!jobId || !jobType || !status) continue;
        [results addObject:@{
            @"jobId": jobId,
            @"job_type": jobType,
            @"status": status,
            @"progress": progress,
            @"createdAt": createdAt
        }];
    }

    return results.count > 0 ? results : nil;
}

- (BOOL)pruneJobsOlderThan:(NSInteger)olderThanDays error:(NSError **)error {
    if (olderThanDays < 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSBlobAuditManagerErrorDomain
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"olderThanDays must be non-negative"}];
        }
        return NO;
    }

    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        return NO;
    }

    NSTimeInterval cutoff = [[NSDate date] timeIntervalSince1970] - (olderThanDays * 24 * 3600);

    NSString *sql = @"DELETE FROM blob_audit_jobs WHERE created_at < ?";

    return [db executeParameterizedUpdate:sql params:@[@(cutoff)] error:error];
}

@end
