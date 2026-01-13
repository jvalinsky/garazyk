#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const PLCOperationErrorDomain;

typedef NS_ENUM(NSInteger, PLCOperationErrorCode) {
    PLCOperationErrorInvalidKey = 1,
    PLCOperationErrorEncodingFailed,
    PLCOperationErrorSigningFailed,
    PLCOperationErrorInvalidOperation,
    PLCOperationErrorMissingRotationKey,
};

/**
 * Builds and signs PLC operations for did:plc identity creation and updates.
 *
 * A PLC operation contains:
 * - type: "plc_operation"
 * - rotationKeys: Array of did:key identifiers for recovery
 * - verificationMethods: Dict with "atproto" key containing signing key as did:key
 * - alsoKnownAs: Array of handles (at:// URIs)
 * - services: Dict with service definitions
 * - prev: CID of previous operation (null for genesis)
 * - sig: Base64url signature (without padding)
 */
@interface PLCOperationBuilder : NSObject

/**
 * The rotation key (secp256k1) used to sign operations.
 * This is the private key - 32 bytes.
 */
@property (nonatomic, strong, readonly) NSData *rotationPrivateKey;

/**
 * The rotation key as a did:key identifier (derived from rotationPrivateKey).
 */
@property (nonatomic, copy, readonly) NSString *rotationDIDKey;

/**
 * The signing key for atproto repo commits as did:key.
 * This goes in verificationMethods.atproto.
 */
@property (nonatomic, copy) NSString *signingDIDKey;

/**
 * The user's handle (e.g., "alice.bsky.social").
 * Will be formatted as "at://<handle>" in alsoKnownAs.
 */
@property (nonatomic, copy) NSString *handle;

/**
 * The PDS endpoint URL (e.g., "https://pds.example.com").
 */
@property (nonatomic, copy) NSString *pdsEndpoint;

/**
 * Additional rotation keys (as did:key strings) beyond the primary one.
 * These provide recovery options.
 */
@property (nonatomic, strong) NSArray<NSString *> *additionalRotationKeys;

/**
 * Initialize with a rotation key.
 * @param rotationPrivateKey The 32-byte secp256k1 private key for signing operations
 * @param error Error output if key is invalid
 */
- (nullable instancetype)initWithRotationPrivateKey:(NSData *)rotationPrivateKey
                                              error:(NSError **)error;

/**
 * Initialize and generate a new rotation key.
 * @param error Error output if key generation fails
 */
- (nullable instancetype)initWithNewRotationKeyWithError:(NSError **)error;

/**
 * Build a genesis (creation) operation.
 * @param error Error output
 * @return The signed operation dictionary ready for submission, or nil on error
 */
- (nullable NSDictionary *)buildGenesisOperationWithError:(NSError **)error;

/**
 * Build an update operation.
 * @param prevCID The CID of the previous operation in the DAG (as hex string)
 * @param error Error output
 * @return The signed operation dictionary, or nil on error
 */
- (nullable NSDictionary *)buildUpdateOperationWithPrev:(NSString *)prevCID
                                                  error:(NSError **)error;

/**
 * Compute the DID from a signed genesis operation.
 * DID = did:plc:<base32-lower(sha256(dag-cbor(op)))[0:24]>
 * @param operation The signed genesis operation
 * @param error Error output
 * @return The computed did:plc identifier, or nil on error
 */
+ (nullable NSString *)computeDIDFromGenesisOperation:(NSDictionary *)operation
                                                error:(NSError **)error;

/**
 * Validate a PLC operation structure.
 * @param operation The operation to validate
 * @param error Error output with details if invalid
 * @return YES if valid, NO otherwise
 */
+ (BOOL)validateOperation:(NSDictionary *)operation error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
