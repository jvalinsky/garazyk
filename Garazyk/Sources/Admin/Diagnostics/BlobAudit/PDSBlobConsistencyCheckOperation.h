// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSBlobAuditOperation.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSBlobConsistencyCheckOperation
 * @brief Verifies all blobs in database have corresponding files.
 *
 * Finds database entries that point to missing blob files.
 */
@interface PDSBlobConsistencyCheckOperation : PDSBlobAuditOperation

@end

NS_ASSUME_NONNULL_END
