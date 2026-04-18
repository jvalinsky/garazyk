#import "PDSBlobAuditOperation.h"
#import "PDSBlobAuditOperation_Protected.h"
#import "Database/Service/ServiceDatabases.h"
#import "Blob/BlobStorage.h"
#import "Debug/PDSLogger.h"
#import <sqlite3.h>

@interface PDSBlobAuditOperation ()
@property (nonatomic, copy, readwrite) NSString *jobId;
@property (nonatomic, copy, readwrite) NSString *auditType;
// Redeclare protected properties as readwrite for internal use
@property (nonatomic, strong, readwrite) BlobStorage *blobStorage;
@property (nonatomic, strong, readwrite) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong, readwrite) dispatch_queue_t queue;
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

    sqlite3 *db = [self.serviceDatabases serviceDatabase];
    if (!db) return;

    NSString *sql = @"UPDATE blob_audit_jobs SET progress = ? WHERE id = ?";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_double(stmt, 1, progress);
        sqlite3_bind_text(stmt, 2, self.jobId.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }
}

- (BOOL)saveResults:(NSDictionary *)results error:(NSError **)error {
    if (!self.serviceDatabases) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        return NO;
    }

    sqlite3 *db = [self.serviceDatabases serviceDatabase];
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

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                         code:sqlite3_extended_errcode(db)
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(db)]}];
        }
        return NO;
    }

    sqlite3_bind_text(stmt, 1, "completed", -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 2, (long)[[NSDate date] timeIntervalSince1970]);
    sqlite3_bind_text(stmt, 3, resultsJSON.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, self.jobId.UTF8String, -1, SQLITE_TRANSIENT);

    BOOL success = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);

    if (!success && error) {
        *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                     code:sqlite3_extended_errcode(db)
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(db)]}];
    }

    return success;
}

@end
