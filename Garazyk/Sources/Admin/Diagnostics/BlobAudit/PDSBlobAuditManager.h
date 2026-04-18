#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class BlobStorage;
@class PDSServiceDatabases;

/**
 * @class PDSBlobAuditManager
 * @brief Manages blob audit job creation, tracking, and execution.
 *
 * Provides a queue-based system for running blob audits with persistence,
 * progress tracking, and job cancellation support.
 */
@interface PDSBlobAuditManager : NSObject

/**
 * @brief The operation queue used for audit execution.
 *
 * Jobs are executed serially (maxConcurrentOperations = 1) to prevent
 * resource exhaustion during expensive file I/O and hashing operations.
 */
@property (nonatomic, strong, readonly) NSOperationQueue *auditQueue;

/**
 * @brief Initialize with required dependencies.
 *
 * @param blobStorage Blob storage instance for audit operations
 * @param serviceDatabases Service database instance for job persistence
 * @return Initialized manager
 */
- (instancetype)initWithBlobStorage:(BlobStorage *)blobStorage
                 serviceDatabases:(PDSServiceDatabases *)serviceDatabases;

/**
 * @brief Start a new audit job.
 *
 * @param type Audit type: "orphans", "cid_verify", "consistency", or "references"
 * @param dryRun If YES, don't make any changes
 * @return Job ID (UUID string) or nil on error
 */
- (nullable NSString *)startAuditWithType:(NSString *)type dryRun:(BOOL)dryRun;

/**
 * @brief Get the current status of an audit job.
 *
 * @param jobId The job ID to query
 * @return Dictionary with status, progress, startedAt, completedAt, results, error
 */
- (nullable NSDictionary *)jobStatusForId:(NSString *)jobId;

/**
 * @brief Cancel a running or pending audit job.
 *
 * @param jobId The job ID to cancel
 * @return YES if the job was cancelled, NO if not found or already completed
 */
- (BOOL)cancelJobWithId:(NSString *)jobId;

/**
 * @brief Get recent audit jobs.
 *
 * @param limit Maximum number of jobs to return
 * @return Array of job status dictionaries
 */
- (nullable NSArray<NSDictionary *> *)recentJobs:(NSInteger)limit;

/**
 * @brief Clean up old audit job records.
 *
 * @param olderThanDays Remove jobs older than this many days
 * @param error Output parameter for errors
 * @return YES if successful, NO on error
 */
- (BOOL)pruneJobsOlderThan:(NSInteger)olderThanDays error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
