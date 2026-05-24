// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PLCOperation.h

 @abstract PLC operation model and state replay for DID documents.

 @discussion
    Defines the PLC operation structure used in the AT Protocol's PLC directory.
    Operations form a hash-linked chain that defines the state of a DID over time.

    The PLCStateReplayer class replays operation history to compute the current
    DID document state.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PLCOperation

 @abstract Represents a single operation in a DID's PLC operation chain.

 @discussion
    PLC operations are signed, hash-linked records that define changes to a DID's
    state. Each operation references the previous operation via the `prev` field,
    forming an immutable history chain.
 */
@interface PLCOperation : NSObject

/*! The DID this operation belongs to. */
@property (nonatomic, copy) NSString *did;

/*! CID of the previous operation (nil for genesis operation). */
@property (nonatomic, copy, nullable) NSString *prev;

/*! Base64-encoded signature of the operation hash. */
@property (nonatomic, copy) NSString *sig;

/*! The operation payload containing rotation keys, services, etc. */
@property (nonatomic, copy) NSDictionary *data;

/*! Content Identifier (CID) for this operation. */
@property (nonatomic, copy, nullable) NSString *cid;

/*! Timestamp when this operation was created. */
@property (nonatomic, strong, nullable) NSDate *createdAt;

/*! Whether this operation has been nullified by a later operation. */
@property (nonatomic, assign) BOOL nullified;

/*! Directory-assigned export sequence number. Not part of signed operation data. */
@property (nonatomic, strong, nullable) NSNumber *sequence;

/*!
 @method calculateDIDForData:

 @abstract Calculates the DID from unsigned operation data.

 @discussion
    This method hashes the unsigned operation data. Per the did-method-plc
    specification (v0.3.0), the DID MUST be derived from the SIGNED operation
    (including the `sig` field). Use calculateDIDForSignedOperation: instead.

    This method is retained only for backward compatibility with legacy
    test vectors and MUST NOT be used for new DID creation.

 @param data The unsigned operation data dictionary.
 @return The DID string derived from the data.
 */
/**
 * @abstract Performs the calculateDIDForData operation.
 */
+ (NSString *)calculateDIDForData:(NSDictionary *)data;

/*!
 @method calculateDIDForSignedOperation:

 @abstract Calculates the DID from a signed operation.

 @discussion
    Per the did-method-plc specification (v0.3.0), the DID is derived from
    the SHA-256 hash of the DAG-CBOR encoding of the SIGNED operation,
    including the `sig` field:

        did:plc:<first 24 chars of base32(SHA-256(DAG-CBOR(signedOp)))>

    This is the correct and spec-compliant way to derive a DID.

 @param signedOperation The complete signed operation dictionary (including `sig`).
 @return The DID string derived from the signed operation.
 */
/**
 * @abstract Performs the calculateDIDForSignedOperation operation.
 */
+ (NSString *)calculateDIDForSignedOperation:(NSDictionary *)signedOperation;

/*!
 @method calculateCIDForOperation:error:

 @abstract Calculates the CID for an operation dictionary.

 @param operation The operation dictionary to calculate CID for.
 @param error On failure, set to an error describing the failure.
 @return The CID string, or nil on failure.
 */
+ (nullable NSString *)calculateCIDForOperation:(NSDictionary *)operation error:(NSError **)error;

/*!
 @method operationFromDictionary:error:

 @abstract Creates a PLCOperation from a dictionary representation.

 @param dict The dictionary containing operation data.
 @param error On failure, set to an error describing the parse failure.
 @return A PLCOperation instance, or nil if parsing failed.
 */
+ (nullable instancetype)operationFromDictionary:(NSDictionary *)dict error:(NSError **)error;

/*!
 @method isValidDidPlc:

 @abstract Validates a did:plc string format.

 @param did The DID string to validate.
 @return YES if valid, NO otherwise.
 */
+ (BOOL)isValidDidPlc:(NSString *)did;

/*!
 @method assertDidPlc:error:

 @abstract Asserts that a DID is valid and returns an error if not.

 @param did The DID string to validate.
 @param error On failure, set to an error describing why validation failed.
 @return YES if valid, NO otherwise.
 */
+ (BOOL)assertDidPlc:(NSString *)did error:(NSError **)error;

/*!
 @method toDictionary

 @abstract Converts the operation to a dictionary representation.

 @return A dictionary containing all operation fields.
 */
- (NSDictionary *)toDictionary;

@end

#pragma mark - PLCDIDState

/*!
 @class PLCDIDState

 @abstract Represents the computed state of a DID from replaying operations.

 @discussion
    The DID state is computed by replaying all operations in a DID's history.
    It contains the current rotation keys, verification methods, and services.
 */
@interface PLCDIDState : NSObject

/*! The DID this state belongs to. */
@property (nonatomic, copy) NSString *did;

/*! Current rotation keys (did:key format). */
@property (nonatomic, strong) NSArray<NSString *> *rotationKeys;

/*! Verification methods mapped by key ID. */
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *verificationMethods;

/*! Alternative identifiers for this DID. */
@property (nonatomic, strong) NSArray<NSString *> *alsoKnownAs;

/*! Service endpoints for this DID. */
@property (nonatomic, strong) NSDictionary *services;

/*! Whether this DID has been tombstoned (permanently deactivated). */
@property (nonatomic, assign) BOOL tombstoned;

/*!
 @method toDIDDocument

 @abstract Converts the state to a DID document.

 @return A DID document dictionary conforming to DID Core specification.
 */
- (NSDictionary *)toDIDDocument;

@end

#pragma mark - PLCStateReplayer

/*!
 @class PLCStateReplayer

 @abstract Replays PLC operation history to compute DID state.

 @discussion
    Takes an array of PLC operations and replays them in order to compute
    the current DID document state. Validates signatures and prev links
    during replay.
 */
@interface PLCStateReplayer : NSObject

/*!
 @method replayHistory:error:

 @abstract Replays operation history to compute DID state.

 @param history Array of PLC operations in chronological order.
 @param error On failure, set to an error describing the replay failure.
 @return The computed DID state, or nil if replay failed.
 */
+ (nullable PLCDIDState *)replayHistory:(NSArray<PLCOperation *> *)history error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
