#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const PLCDirectoryErrorDomain;

typedef NS_ENUM(NSInteger, PLCDirectoryErrorCode) {
    PLCDirectoryErrorNetworkError = 1,
    PLCDirectoryErrorInvalidResponse,
    PLCDirectoryErrorOperationRejected,
    PLCDirectoryErrorDIDNotFound,
    PLCDirectoryErrorConflict,
};

/**
 * Client for interacting with the PLC directory (plc.directory).
 *
 * The PLC directory is the central registry for did:plc identifiers.
 * It stores the operation log (DAG) for each DID.
 */
@interface PLCDirectoryClient : NSObject

/**
 * The base URL for the PLC directory.
 * Defaults to "https://plc.directory".
 */
@property (nonatomic, copy) NSString *baseURL;

/**
 * Timeout interval for requests. Defaults to 30 seconds.
 */
@property (nonatomic, assign) NSTimeInterval timeoutInterval;

/**
 * Initialize with default settings (production plc.directory).
 */
- (instancetype)init;

/**
 * Initialize with a custom base URL (e.g., for testing).
 * @param baseURL The base URL for the PLC directory
 */
- (instancetype)initWithBaseURL:(NSString *)baseURL;

#pragma mark - Operations

/**
 * Submit a new operation to the PLC directory.
 * For genesis operations, this creates a new DID.
 * For update operations, this updates an existing DID.
 *
 * @param operation The signed PLC operation
 * @param did The DID this operation is for
 * @param completion Completion handler with success flag and optional error
 */
- (void)submitOperation:(NSDictionary *)operation
                 forDID:(NSString *)did
             completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/**
 * Synchronously submit an operation.
 * @param operation The signed PLC operation
 * @param did The DID this operation is for
 * @param error Error output
 * @return YES on success, NO on failure
 */
- (BOOL)submitOperationSync:(NSDictionary *)operation
                     forDID:(NSString *)did
                      error:(NSError **)error;

#pragma mark - Queries

/**
 * Get the operation log (audit log) for a DID.
 * Returns all operations in the DID's history.
 *
 * @param did The DID to query
 * @param completion Completion handler with operations array or error
 */
- (void)getOperationLog:(NSString *)did
             completion:(void (^)(NSArray<NSDictionary *> * _Nullable operations, NSError * _Nullable error))completion;

/**
 * Synchronously get the operation log.
 * @param did The DID to query
 * @param error Error output
 * @return Array of operations, or nil on error
 */
- (nullable NSArray<NSDictionary *> *)getOperationLogSync:(NSString *)did
                                                    error:(NSError **)error;

/**
 * Resolve a DID to its current document.
 *
 * @param did The DID to resolve
 * @param completion Completion handler with DID document or error
 */
- (void)resolveDID:(NSString *)did
        completion:(void (^)(NSDictionary * _Nullable document, NSError * _Nullable error))completion;

/**
 * Synchronously resolve a DID.
 * @param did The DID to resolve
 * @param error Error output
 * @return DID document, or nil on error
 */
- (nullable NSDictionary *)resolveDIDSync:(NSString *)did
                                    error:(NSError **)error;

/**
 * Check if a DID exists in the directory.
 * @param did The DID to check
 * @param completion Completion handler with existence flag
 */
- (void)checkDIDExists:(NSString *)did
            completion:(void (^)(BOOL exists, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
