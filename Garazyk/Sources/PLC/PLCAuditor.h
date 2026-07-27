// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
/**
 * @abstract Performs the verifyOperation operation.
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
 @method normalizedDataForOperation:error:

 @abstract Normalizes and validates the operational data for a PLC operation.

 @param op The PLC operation to normalize.
 @param error On failure, set to the validation error.
 @result A dictionary of validated operational data, or nil on failure.

 @discussion
    This method ensures that the operation data is safe for use by rejecting
    nil elements, type mismatches, and missing fields that could cause crashes
    when passed to collection literals. Call before any derived state is read
    from remote operation data.
 */
+ (nullable NSDictionary *)normalizedDataForOperation:(PLCOperation *)op error:(NSError **)error;

/*!
 @method verifyChain:did:error:

 @abstract Verifies an operation chain from a raw audit log without a store.

 @param operations The ordered list of PLC operations to verify.
 @param did The expected DID.
 @param error On failure, set to the verification error.
 @result YES when the chain is internally consistent and signatures verify.

 @discussion
    Verifies the signature chain, prev links, tombstone placement, and
    genesis DID matching for operations parsed from a remote audit log.
    Unlike verifyDID:error:, this method accepts a bare array of operations
    directly rather than reading from a PLCStore.
 */
+ (BOOL)verifyChain:(NSArray<PLCOperation *> *)operations did:(NSString *)did error:(NSError **)error;

/*!
 @method hashForOperationData:

 @abstract Computes the canonical hash used for PLC operation signing.

 @param data Normalized PLC operation payload.
 @result Hash bytes used as the signature payload.
 */
- (NSData *)hashForOperationData:(NSDictionary *)data;

@end

NS_ASSUME_NONNULL_END
