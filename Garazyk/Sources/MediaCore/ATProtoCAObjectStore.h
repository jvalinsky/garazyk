// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoCAObjectStore.h

 @abstract Content-addressed media object store for jelcz (ADR 0036 / WS12 Phase 2).

 @discussion Stores immutable media bytes under a DASL CID. VOD objects use
 BLAKE3 CIDs with a regenerable chunk outboard (`.bao`) for range proofs.
 Live segments may use SHA-256 CIDs in the same store without an outboard.

 The outboard is derived acceleration data: deleting or regenerating it does
 not change the media CID. Phase 9 stores wire-compatible Bao outboards and
 serves Bao slices from @c produceProof so clients can verify ranges without
 the full object. Legacy GZBO outboards remain readable when present.
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ATProtoCAObjectStoreErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoCAObjectStoreErrorCode) {
    ATProtoCAObjectStoreErrorInvalidArgument = 1,
    ATProtoCAObjectStoreErrorCIDMismatch = 2,
    ATProtoCAObjectStoreErrorNotFound = 3,
    ATProtoCAObjectStoreErrorIO = 4,
    ATProtoCAObjectStoreErrorInvalidProof = 5,
    ATProtoCAObjectStoreErrorRange = 6,
};

/** Digest profile for put / CID computation. */
typedef NS_ENUM(NSInteger, ATProtoCAObjectDigestProfile) {
    /** Live segments / ATProto-interop: raw + SHA-256. */
    ATProtoCAObjectDigestProfileSHA256 = 0,
    /** Flat-VOD objects: raw + BLAKE3. */
    ATProtoCAObjectDigestProfileBLAKE3 = 1,
};

/**
 Disk-backed content-addressed object store with optional BLAKE3 outboard proofs.
 */
@interface ATProtoCAObjectStore : NSObject

/** Root directory containing `objects/` and `proofs/`. */
@property (nonatomic, copy, readonly) NSString *rootDirectory;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 Opens or creates a store under `rootDirectory`.

 Creates `objects/` and `proofs/` if missing.
 */
- (nullable instancetype)initWithRootDirectory:(NSString *)rootDirectory
                                         error:(NSError **)error NS_DESIGNATED_INITIALIZER;

/** Computes the CID for `data` under the given digest profile. */
+ (nullable ATProtoCID *)cidForData:(NSData *)data
                            profile:(ATProtoCAObjectDigestProfile)profile
                              error:(NSError **)error;

/**
 Stores `data` under its content CID.

 If `expectedCID` is non-nil, the computed CID must match or the put fails
 with `ATProtoCAObjectStoreErrorCIDMismatch` and nothing is written.
 For BLAKE3 profile, also generates and persists the outboard proof.
 */
- (nullable ATProtoCID *)putData:(NSData *)data
                     expectedCID:(nullable ATProtoCID *)expectedCID
                         profile:(ATProtoCAObjectDigestProfile)profile
                           error:(NSError **)error;

/** Returns `@{ @"cid", @"size", @"hasProof" }` or nil if missing. */
- (nullable NSDictionary<NSString *, id> *)statCID:(ATProtoCID *)cid error:(NSError **)error;

- (nullable NSData *)dataForCID:(ATProtoCID *)cid error:(NSError **)error;

/**
 Returns a subrange of the object. `offset+length` past EOF truncates.
 Zero-length at EOF returns empty data. Offset past EOF is an error.
 */
- (nullable NSData *)dataForCID:(ATProtoCID *)cid
                         offset:(NSUInteger)offset
                         length:(NSUInteger)length
                          error:(NSError **)error;

- (BOOL)deleteCID:(ATProtoCID *)cid error:(NSError **)error;

/**
 Builds and persists the BLAKE3 chunk outboard for an existing object.
 No-op regenerate for SHA-256 objects (returns YES without writing).
 */
- (BOOL)generateProofForCID:(ATProtoCID *)cid error:(NSError **)error;

/** Deletes and regenerates the outboard; media CID is unchanged. */
- (BOOL)regenerateProofForCID:(ATProtoCID *)cid error:(NSError **)error;

/**
 Produces untrusted proof material for authenticating `[offset, offset+length)`.

 Returns a dictionary:
 `cid`, `offset`, `length`, `totalLength`, `chunkSize`, `chunkDigests` (NSArray of NSData),
 `firstChunkIndex`, `rangeData` (the bytes of the requested range).
 */
- (nullable NSDictionary<NSString *, id> *)produceProofForCID:(ATProtoCID *)cid
                                                      offset:(NSUInteger)offset
                                                      length:(NSUInteger)length
                                                       error:(NSError **)error;

/**
 Verifies a proof dictionary from `-produceProofForCID:offset:length:error:`.

 Checks range leaf digests and that BLAKE3 of the full object (caller supplies
 `fullObjectData` or it is loaded from `store` when non-nil) matches `cid`.
 */
+ (BOOL)verifyProof:(NSDictionary<NSString *, id> *)proof
      fullObjectData:(nullable NSData *)fullObjectData
               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
