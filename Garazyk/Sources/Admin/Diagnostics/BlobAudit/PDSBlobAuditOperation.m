// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSBlobAuditOperation.h"
#import "PDSBlobAuditOperation_Protected.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Blob/BlobStorage.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

@interface PDSBlobAuditOperation ()
@property (nonatomic, copy, readwrite) NSString *jobId;
@property (nonatomic, copy, readwrite) NSString *auditType;
// Redeclare protected properties as readwrite for internal use
@property (nonatomic, strong, readwrite) BlobStorage *blobStorage;
@property (nonatomic, strong, readwrite) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG, readwrite) dispatch_queue_t queue;
// Redeclare readonly properties as readwrite for internal use
@property (nonatomic, readwrite) double progress;
@property (nonatomic, strong, readwrite, nullable) NSDictionary *results;
@property (nonatomic, strong, readwrite, nullable) NSError *operationError;
@end

@implementation PDSBlobAuditOperation

- (instancetype)initWithJobId:(NSString *)jobId
                    auditType:(NSString *)auditType
                  blobStorage:(BlobStorage *)blobStorage
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                       dryRun:(BOOL)dryRun {
    if ((self = [super init])) {
        _jobId = [jobId copy];
        _auditType = [auditType copy];
        _blobStorage = blobStorage;
        _serviceDatabases = serviceDatabases;
        _dryRun = dryRun;
        _progress = 0;
        _queue = dispatch_queue_create("com.atproto.pds.diagnostics.audit", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)main {
    // Base class does nothing - subclasses should override
    [self updateProgress:1.0 status:@"Completed"];
}

- (void)updateProgress:(double)progress status:(nullable NSString *)status {
    dispatch_async(self.queue, ^{
        self.progress = progress;

        // Call progress callback if set
        if (self.progressCallback) {
            self.progressCallback(progress, status);
        }

        // Update database
        [self updateJobProgress:progress status:status];
    });
}

- (void)updateJobProgress:(double)progress status:(nullable NSString *)status {
    if (!self.serviceDatabases) return;

    NSError *dbError = nil;
    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:&dbError];
    if (!db) return;

    NSString *sql = @"UPDATE blob_audit_jobs SET progress = ? WHERE id = ?";

    [db executeParameterizedUpdate:sql params:@[@(progress), self.jobId] error:nil];
}

- (BOOL)saveResults:(NSDictionary *)results error:(NSError **)error {
    if (!self.serviceDatabases) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        return NO;
    }

    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Cannot access database"}];
        return NO;
    }

    NSError *jsonError = nil;
    NSData *resultsData = [NSJSONSerialization dataWithJSONObject:results options:0 error:&jsonError];
    if (!resultsData) {
        if (error) *error = jsonError;
        return NO;
    }

    NSString *resultsJSON = [[NSString alloc] initWithData:resultsData encoding:NSUTF8StringEncoding];

    NSString *sql = @"UPDATE blob_audit_jobs SET status = ?, completed_at = ?, results = ? WHERE id = ?";

    return [db executeParameterizedUpdate:sql
                                   params:@[@"completed", @([[NSDate date] timeIntervalSince1970]), resultsJSON, self.jobId]
                                    error:error];
}

@end
