/**
 * @file RepoCommit.h
 * @brief ATProto repository commit structure
 *
 * RepoCommit represents an atomic commit to a user's ATProto repository.
 * Commits form a cryptographically-signed chain where each commit references
 * the previous commit's CID (content identifier), creating an immutable history.
 *
 * Each commit contains:
 * - Reference to repository data (Merkle Search Tree root)
 * - Revision identifier (TID-based)
 * - Link to previous commit
 * - Cryptographic signature (secp256k1)
 *
 * Commits are serialized using DAG-CBOR and stored in CAR (Content Addressable
 * Archive) format for efficient transport and storage.
 *
 * @see MST, CID, CAR
 */

#import <Foundation/Foundation.h>
#import "Core/CID.h"
#import "Core/TID.h"
#import "Auth/Secp256k1.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class RepoCommit
 * @brief Represents an atomic commit to an ATProto repository
 *
 * RepoCommit models the commit structure in ATProto repositories. Each commit
 * is identified by a revision string (TID) and contains a reference to the
 * repository data (Merkle Search Tree root CID) and the previous commit's CID.
 *
 * Commit Chain:
 * - First commit: prevCID is nil (genesis commit)
 * - Subsequent commits: prevCID links to parent, forming chain
 * - Each commit is signed with repository owner's private key
 * - Commits are immutable once created
 *
 * Storage Format:
 * - Serialized as DAG-CBOR (codec 0x71)
 * - Packaged in CAR v1 format for transport
 * - CID computed from unsigned commit data (before signature)
 *
 * Usage:
 * @code
 * RepoCommit *commit = [RepoCommit createCommitWithDid:@"did:plc:..."
 *                                                 data:mstRootCID
 *                                                  rev:[TID generate]
 *                                                 prev:prevCommitCID];
 * [commit signWithPrivateKey:privateKeyData error:&err];
 * NSData *carData = [commit serialize];
 * @endcode
 */
@interface RepoCommit : NSObject <NSSecureCoding>

/*! Decentralized identifier of the repository owner */
@property (nonatomic, copy) NSString *did;

/*! Commit format version (currently 3 per ATProto spec) */
@property (nonatomic, assign) NSInteger version;

/*! CID of the repository data (MST root), or nil for empty repo */
@property (nonatomic, strong, nullable) CID *dataCID;

/*! Revision identifier (TID-based timestamp) uniquely identifying this commit */
@property (nonatomic, copy) NSString *rev;

/*! CID of the previous commit in the chain, or nil for genesis commit */
@property (nonatomic, strong, nullable) CID *prevCID;

/*! Cryptographic signature (secp256k1) over the unsigned commit data */
@property (nonatomic, strong, nullable) NSData *signature;

/**
 * @brief Create a new repository commit
 *
 * @param did Repository owner's DID
 * @param dataCID CID of repository data (MST root), or nil for empty repo
 * @param rev Revision identifier (TID), or nil to auto-generate
 * @param prevCID Previous commit's CID, or nil for genesis commit
 * @return Unsigned RepoCommit instance (call signWithPrivateKey: before use)
 */
+ (instancetype)createCommitWithDid:(NSString *)did
                              data:(nullable CID *)dataCID
                               rev:(nullable NSString *)rev
                             prev:(nullable CID *)prevCID;

/**
 * @brief Serialize commit to CAR v1 format
 *
 * Produces a Content Addressable Archive containing the signed commit block.
 * The commit CID is used as the CAR root.
 *
 * @return CAR-encoded commit data ready for storage or transmission
 */
- (NSData *)serialize;

/**
 * @brief Compute SHA-256 hash of the unsigned commit data
 *
 * Hash is computed over the DAG-CBOR encoding of the commit structure
 * (excluding signature field). Used for signature generation.
 *
 * @return SHA-256 digest (32 bytes), or nil if serialization fails
 */
- (nullable NSData *)computeHash;

/**
 * @brief Compute CID for this commit
 *
 * CID is computed from the unsigned commit data using:
 * - Multicodec: DAG-CBOR (0x71)
 * - Multihash: SHA-256 (0x12)
 *
 * @return CID v1 identifying this commit
 */
- (CID *)computeCID;

/**
 * @brief Sign the commit with a private key
 *
 * Computes hash of unsigned commit data and signs with secp256k1.
 * Sets the signature property on success.
 *
 * @param privateKey Raw secp256k1 private key (32 bytes)
 * @param error Error pointer for signing failures
 * @return YES if signed successfully, NO on failure
 */
- (BOOL)signWithPrivateKey:(NSData *)privateKey error:(NSError **)error;

/**
 * @brief Verify the commit signature
 *
 * Recomputes hash of unsigned commit data and verifies signature
 * using secp256k1.
 *
 * @param publicKey Raw secp256k1 public key (33 or 65 bytes)
 * @param error Error pointer for verification failures
 * @return YES if signature is valid, NO otherwise
 */
- (BOOL)verifySignatureWithPublicKey:(NSData *)publicKey error:(NSError **)error;

/**
 * @brief Deserialize commit from CAR v1 data
 *
 * Parses CAR format, extracts commit block, and decodes DAG-CBOR structure.
 * Validates commit structure and signature presence.
 *
 * @param carData CAR v1 encoded commit data
 * @param error Error pointer for parsing failures
 * @return RepoCommit instance or nil on parse failure
 */
+ (nullable instancetype)fromCARData:(NSData *)carData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
