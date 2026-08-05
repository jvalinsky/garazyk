// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSBlobAuditOperation.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSBlobCIDVerificationOperation
 * @brief Verifies blob CIDs match actual file contents.
 *
 * Recalculates ATProtoCID from blob file data and verifies it matches the stored ATProtoCID.
 * Detects any data corruption or tampering.
 */
@interface PDSBlobCIDVerificationOperation : PDSBlobAuditOperation

@end

NS_ASSUME_NONNULL_END
