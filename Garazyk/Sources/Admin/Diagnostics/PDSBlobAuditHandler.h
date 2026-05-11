// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSBlobAuditHandler
 * @brief Handles blob storage audit API endpoints for system diagnostics.
 *
 * Manages background blob integrity audit jobs. Supports four audit types:
 * - "orphans" - Find filesystem blobs without database metadata
 * - "cid_verify" - Verify blob CIDs match stored values
 * - "consistency" - Find DB entries pointing to missing files
 * - "references" - Scan repos for unreferenced blobs
 *
 * Jobs run asynchronously in a serial NSOperationQueue. All jobs support
 * dry-run mode for safe auditing.
 *
 * Endpoints:
 * - POST /audit - Start new audit job
 * - GET /status?jobId=<uuid> - Poll job status
 *
 * Request Format (POST /audit):
 * {
 *   "auditType": "orphans",
 *   "dryRun": true
 * }
 *
 * Response Format (POST /audit):
 * {
 *   "jobId": "550e8400-e29b-41d4-a716-446655440000",
 *   "status": "pending",
 *   "auditType": "orphans",
 *   "dryRun": true
 * }
 *
 * Response Format (GET /status):
 * {
 *   "jobId": "...",
 *   "status": "running|completed|failed",
 *   "progress": 45.5,
 *   "results": { "orphaned_count": 42, "freed_bytes": 1048576, ... },
 *   "error": null
 * }
 */
@interface PDSBlobAuditHandler : NSObject

/**
 * @brief Returns the shared singleton instance.
 *
 * @return The shared PDSBlobAuditHandler instance.
 */
+ (instancetype)sharedHandler;

/**
 * @brief Processes blob audit API requests.
 *
 * @param method HTTP method
 * @param path Request path (e.g., /audit, /status)
 * @param headers HTTP headers
 * @param body Request body (JSON)
 * @param statusCode Output status code
 * @param contentType Output content type
 * @return JSON response body or error message
 */
- (nullable NSString *)handleRequestWithMethod:(NSInteger)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

@end

NS_ASSUME_NONNULL_END
