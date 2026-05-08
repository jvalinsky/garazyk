/*!
 @file PLCStore.h

 @abstract Storage contract for PLC operation history.
 */

#import <Foundation/Foundation.h>
#import "PLCOperation.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol PLCStore

 @abstract Persists and queries PLC operation history by DID.
 */
@protocol PLCStore <NSObject>

/*!
 @method getHistoryForDID:includeNullified:error:

 @abstract Returns operation history for a DID.

 @param did DID whose history is requested.
 @param includeNullified Whether operations marked nullified should be included.
 @param error On failure, set to a store error.
 @result Ordered operation history, or nil on store failure.
 */
- (nullable NSArray<PLCOperation *> *)getHistoryForDID:(NSString *)did
                                      includeNullified:(BOOL)includeNullified
                                                 error:(NSError **)error;

/*!
 @method appendOperation:nullifyCIDs:error:

 @abstract Appends an operation and applies nullifications in one write.

 @param op Operation to append.
 @param nullified CIDs that should be marked nullified by this append.
 @param error On failure, set to a store error.
 @result YES on success, otherwise NO.
 */
- (BOOL)appendOperation:(PLCOperation *)op
           nullifyCIDs:(nullable NSArray<NSString *> *)nullified
                 error:(NSError **)error;

/*!
 @method getAllDIDsWithError:

 @abstract Returns every DID currently represented in the store.

 @param error On failure, set to a store error.
 @result Array of DID strings, or nil on failure.
 */
- (nullable NSArray<NSString *> *)getAllDIDsWithError:(NSError **)error;

/*!
 @method getLatestOperationForDID:error:

 @abstract Returns the latest stored operation for a DID.

 @param did DID whose latest operation is requested.
 @param error On failure, set to a store error.
 @result Most recent operation, or nil when none exists or on failure.
 */
- (nullable PLCOperation *)getLatestOperationForDID:(NSString *)did error:(NSError **)error;

/*!
 @method exportOperationsAfter:count:error:

 @abstract Exports operations after the given timestamp up to a count limit.

 @param after Lower-bound timestamp (exclusive); nil exports from start.
 @param count Maximum number of operations to return.
 @param error On failure, set to a store error.
 @result Ordered operations for export, or nil on failure.
 */
- (nullable NSArray<PLCOperation *> *)exportOperationsAfter:(nullable NSDate *)after
                                                      count:(NSUInteger)count
                                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
