#import "PDSBlobAuditOperation.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSBlobCIDVerificationOperation
 * @brief Verifies blob CIDs match actual file contents.
 *
 * Recalculates CID from blob file data and verifies it matches the stored CID.
 * Detects any data corruption or tampering.
 */
@interface PDSBlobCIDVerificationOperation : PDSBlobAuditOperation

@end

NS_ASSUME_NONNULL_END
