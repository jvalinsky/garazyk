#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;
@class BlobStorage;

/**
 * @class PDSBlobAuditOperation
 * @brief Base class for blob audit operations.
 *
 * Subclasses implement specific audit types (orphan detection, CID verification, etc.)
 * Operations are designed to run in NSOperationQueue with progress tracking and cancellation support.
 */
@interface PDSBlobAuditOperation : NSOperation

/**
 * @brief Unique job ID for this audit operation.
 */
@property (nonatomic, copy, readonly) NSString *jobId;

/**
 * @brief Audit type identifier (e.g., "orphans", "cid_verify").
 */
@property (nonatomic, copy, readonly) NSString *auditType;

/**
 * @brief Current progress (0.0 to 1.0).
 */
@property (nonatomic, readonly) double progress;

/**
 * @brief Whether the operation is running in dry-run mode.
 */
@property (nonatomic, readonly) BOOL dryRun;

/**
 * @brief Operation results as a dictionary.
 */
@property (nonatomic, strong, nullable, readonly) NSDictionary *results;

/**
 * @brief Error encountered during operation, if any.
 */
@property (nonatomic, strong, nullable, readonly) NSError *operationError;

/**
 * @brief Initialize operation with required dependencies.
 *
 * @param jobId Unique identifier for this job
 * @param auditType Type of audit to perform
 * @param blobStorage Blob storage instance
 * @param serviceDatabases Service database instance
 * @param dryRun If YES, don't make any changes
 * @return Initialized operation
 */
- (instancetype)initWithJobId:(NSString *)jobId
                    auditType:(NSString *)auditType
                  blobStorage:(BlobStorage *)blobStorage
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                       dryRun:(BOOL)dryRun;

/**
 * @brief Progress callback block.
 *
 * Called periodically to report progress updates.
 */
@property (nonatomic, copy, nullable) void (^progressCallback)(double progress, NSString *_Nullable status);

/**
 * @brief Update progress and optionally status.
 *
 * @param progress Progress value (0.0 to 1.0)
 * @param status Optional status message
 */
- (void)updateProgress:(double)progress status:(nullable NSString *)status;

/**
 * @brief Save results to the database.
 *
 * @param results Operation results dictionary
 * @param error Output error parameter
 * @return YES if saved successfully, NO on error
 */
- (BOOL)saveResults:(NSDictionary *)results error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
