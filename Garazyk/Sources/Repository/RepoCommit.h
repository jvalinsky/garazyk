// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file RepoCommit.h
 * @abstract ATProto repository commit structure.
 * @discussion RepoCommit represents an atomic commit to a user's ATProto repository.
 * Commits form a cryptographically-signed chain where each commit references the
 * previous commit's ATProtoCID (content identifier), creating an immutable history.
 */

#import <Foundation/Foundation.h>
#import "Core/CID.h"
#import "Core/TID.h"
#import "Auth/Crypto/Secp256k1.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Represents an atomic commit to an ATProto repository.
 * @discussion RepoCommit models the commit structure in ATProto repositories. Each commit
 * is identified by a revision string (ATProtoTID) and contains a reference to the
 * repository data (Merkle Search Tree root ATProtoCID) and the previous commit's ATProtoCID.
 * Commits are immutable and cryptographically signed.
 */
@interface RepoCommit : NSObject <NSSecureCoding>

/** @abstract Decentralized identifier of the repository owner. */
@property (nonatomic, copy) NSString *did;

/** @abstract Commit format version (currently 3). */
@property (nonatomic, assign) NSInteger version;

/** @abstract ATProtoCID of the repository data (MST root), or nil for empty repo. */
@property (nonatomic, strong, nullable) ATProtoCID *dataCID;

/** @abstract Revision identifier (ATProtoTID). */
@property (nonatomic, copy) NSString *rev;

/** @abstract ATProtoCID of the previous commit, or nil for genesis commit. */
@property (nonatomic, strong, nullable) ATProtoCID *prevCID;

/** @abstract Cryptographic signature (secp256k1). */
@property (nonatomic, copy, nullable) NSData *signature;

/**
 * @abstract Creates a new repository commit.
 * @param did Repository owner's DID.
 * @param dataCID ATProtoCID of repository data.
 * @param rev Revision identifier (ATProtoTID), or nil to auto-generate.
 * @param prevCID Previous commit's ATProtoCID.
 * @return Unsigned RepoCommit instance.
 */
+ (instancetype)createCommitWithDid:(NSString *)did
                              data:(nullable ATProtoCID *)dataCID
                               rev:(nullable NSString *)rev
                             prev:(nullable ATProtoCID *)prevCID;

/**
 * @abstract Serializes unsigned commit to DAG-CBOR.
 * @return DAG-CBOR encoded data.
 */
- (NSData *)serialize;

/**
 * @abstract Serializes signed commit to DAG-CBOR.
 * @return DAG-CBOR encoded signed data, or nil if incomplete.
 */
- (nullable NSData *)serializeSigned;

/**
 * @abstract Exports the signed commit as a CAR v1 file.
 * @return CAR-encoded data, or nil if commit is unsigned.
 */
- (nullable NSData *)exportCAR;

/**
 * @abstract Computes SHA-256 hash of the unsigned commit data.
 * @return SHA-256 digest, or nil on failure.
 */
- (nullable NSData *)computeHash;

/**
 * @abstract Computes the ATProtoCID for this commit.
 * @return ATProtoCID v1 identifying this commit.
 */
- (ATProtoCID *)computeCID;

/**
 * @abstract Signs the commit with a private key.
 * @param privateKey Raw secp256k1 private key (32 bytes).
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)signWithPrivateKey:(NSData *)privateKey error:(NSError **)error;

/**
 * @abstract Verifies the commit signature.
 * @param publicKey Raw secp256k1 public key.
 * @param error Receives failure details.
 * @return YES if valid.
 */
- (BOOL)verifySignatureWithPublicKey:(NSData *)publicKey error:(NSError **)error;

/**
 * @abstract Deserializes commit from CAR v1 data.
 * @param carData CAR v1 encoded data.
 * @param error Receives failure details.
 * @return RepoCommit instance or nil.
 */
+ (nullable instancetype)fromCARData:(NSData *)carData error:(NSError **)error;

/**
 * @abstract Deserializes a signed commit block from DAG-CBOR bytes.
 * @param blockData Signed repository commit block bytes.
 * @param error Receives failure details.
 * @return RepoCommit instance or nil.
 */
+ (nullable instancetype)fromSignedBlockData:(NSData *)blockData
                                       error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
