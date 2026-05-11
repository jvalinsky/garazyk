/*!
 @file GermIdentityService.h

 @abstract Server-side AC Protocol identity verification for Germ E2EE.

 @discussion Verifies Anchor Key <-> DID bindings, validates succession
 proof chains, and provides query access to current anchor keys for a
 given DID. The identity service does NOT store private keys — it
 only verifies signatures and tracks the public key history.

 Key format: TypedKeyMaterial wire format (1-byte algorithm prefix +
 32-byte key data). Currently only curve25519Signing (ed25519) is
 supported, matching the AC Protocol specification.

 Models after Germ's current shipping 1:1 E2EE DM product.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@protocol PDSQueryDatabase;

NS_ASSUME_NONNULL_BEGIN

/*!
 @constant kGermAlgorithmCurve25519Signing
 @abstract Algorithm byte for ed25519 signing keys in TypedKeyMaterial.
 */
extern const uint8_t kGermAlgorithmCurve25519Signing;

@interface GermIdentityService : NSObject

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

#pragma mark - Declaration Verification

/*!
 @method verifyDeclaration:did:error:

 @abstract Verifies that a declaration record's Anchor Key is valid
 for the given DID.

 @param anchorKeyWireFormat The currentKey field from the declaration
        record (TypedKeyMaterial wire format).
 @param did The DID that owns this declaration.
 @param error Output parameter for errors.

 @return YES if the anchor key is a valid ed25519 public key, NO otherwise.

 @discussion This verifies the key format and algorithm. The actual
 Anchor Key signature over the DID is verified client-side (the
 server doesn't have the DID document to verify the bidirectional
 binding). The server stores the key for lookup.
 */
- (BOOL)verifyDeclaration:(NSData *)anchorKeyWireFormat
                      did:(NSString *)did
                    error:(NSError **)error;

#pragma mark - Succession Verification

/*!
 @method verifySuccessionProofs:currentKey:attestation:error:

 @abstract Verifies a chain of succession proofs.

 @param proofsWireFormat The continuityProofs field from the
        declaration record (concatenated proof wire format).
 @param currentKeyWireFormat The current (successor) anchor key.
 @param attestationWireFormat The dependent identity (DID) wire format.
 @param error Output parameter for errors.

 @return Array of predecessor anchor key wire formats (NSData), or nil
         on verification failure.

 @discussion Each proof is a (TypedKeyMaterial, TypedSignature) pair.
 The chain is verified from the current key backwards: each successor
 must have signed over (discriminator, attestation, predecessor,
 successor). If any proof fails, the entire chain is rejected.
 */
- (nullable NSArray<NSData *> *)verifySuccessionProofs:(NSData *)proofsWireFormat
                                           currentKey:(NSData *)currentKeyWireFormat
                                          attestation:(NSData *)attestationWireFormat
                                                error:(NSError **)error;

#pragma mark - Key Lookup

/*!
 @method getAnchorKeyForDid:error:

 @abstract Retrieves the current anchor key for a DID.

 @param did The DID to look up.
 @param error Output parameter for errors.

 @return The anchor key wire format (TypedKeyMaterial), or nil if not
         found.

 @discussion Looks up the most recent com.germnetwork.declaration
 record in the DID's PDS repo.
 */
- (nullable NSData *)getAnchorKeyForDid:(NSString *)did
                                  error:(NSError **)error;

#pragma mark - Key History

/*!
 @method getKeyHistoryForDid:error:

 @abstract Retrieves the full anchor key history for a DID.

 @param did The DID to look up.
 @param error Output parameter for errors.

 @return Array of anchor key wire formats in chronological order
         (oldest first), or nil on error.
 */
- (nullable NSArray<NSData *> *)getKeyHistoryForDid:(NSString *)did
                                              error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
