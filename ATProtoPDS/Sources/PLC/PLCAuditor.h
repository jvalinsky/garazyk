/*!
 @file PLCAuditor.h

 @abstract PLC operation chain verification APIs.
 */

#import <Foundation/Foundation.h>
#import "PLCStore.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PLCAuditor

 @abstract Validates PLC operation history and proposed PLC operations.

 @discussion Verifies signature chains, `prev` links, tombstone placement,
 and rotation-key transitions against data retrieved from a PLCStore.
 */
@interface PLCAuditor : NSObject

/*!
 @method initWithStore:

 @abstract Creates an auditor backed by the provided PLC store.

 @param store PLC history store used during verification.
 */
- (instancetype)initWithStore:(id<PLCStore>)store;

/*!
 @method verifyDID:error:

 @abstract Verifies the persisted operation chain for a DID.

 @param did DID to verify.
 @param error On failure, set to the verification error.
 @result YES when history is internally consistent and signatures verify.
 */
- (BOOL)verifyDID:(NSString *)did error:(NSError **)error;

/*!
 @method verifyOperation:proposedDate:nullifiedCIDs:error:

 @abstract Verifies whether an incoming operation is valid for append.

 @param op Proposed PLC operation.
 @param proposedDate Timestamp context used for time-window checks.
 @param nullified On success, receives CIDs nullified by this operation.
 @param error On failure, set to the verification error.
 @result YES when the operation is valid for insertion, otherwise NO.
 */
- (BOOL)verifyOperation:(PLCOperation *)op
	           proposedDate:(NSDate *)proposedDate
	          nullifiedCIDs:(NSArray<NSString *> * _Nullable __autoreleasing * _Nullable)nullified
	                  error:(NSError **)error;

/*!
 @method verifyOperation:error:

 @abstract Verifies a proposed operation using current time as context.

 @param op Proposed PLC operation.
 @param error On failure, set to the verification error.
 @result YES when valid, otherwise NO.
 */
- (BOOL)verifyOperation:(PLCOperation *)op error:(NSError **)error;

/*!
 @method hashForOperationData:

 @abstract Computes the canonical hash used for PLC operation signing.

 @param data Normalized PLC operation payload.
 @result Hash bytes used as the signature payload.
 */
- (NSData *)hashForOperationData:(NSDictionary *)data;

@end

NS_ASSUME_NONNULL_END
