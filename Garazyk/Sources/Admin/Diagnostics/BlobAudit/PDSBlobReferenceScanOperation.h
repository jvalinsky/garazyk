// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSBlobAuditOperation.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSBlobReferenceScanOperation
 * @brief Scans records for blob references to find unreferenced blobs.
 *
 * Analyzes all records in repositories to find which blobs are actually referenced.
 * Identifies blob cleanup candidates.
 */
@interface PDSBlobReferenceScanOperation : PDSBlobAuditOperation

@end

NS_ASSUME_NONNULL_END
