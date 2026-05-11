// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSBlobAuditOperation.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSBlobOrphanScanOperation
 * @brief Scans filesystem for blobs without database metadata.
 *
 * Finds orphaned blob files that exist on disk but have no entry in the blobs table.
 */
@interface PDSBlobOrphanScanOperation : PDSBlobAuditOperation

@end

NS_ASSUME_NONNULL_END
