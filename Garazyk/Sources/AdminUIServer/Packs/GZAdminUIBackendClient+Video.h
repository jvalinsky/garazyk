// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Video-service administration operations used by the authenticated admin UI.
 * @discussion Job listing and retry use the PDS administrative transport; direct video endpoints
 * use the configured video admin token. Methods block for their HTTP request and return upstream
 * JSON or a dictionary containing `error` and `message`; no NSError is exposed to callers.
 */
@interface GZAdminUIBackendClient (Video)

/**
 * @abstract Lists video jobs using optional state, page size, and cursor filters.
 */
- (NSDictionary *)fetchVideoJobsWithState:(nullable NSString *)state limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

/** @abstract Retrieves a video job for a nonempty job identifier. */
- (NSDictionary *)fetchVideoJobById:(NSString *)jobId;

/** @abstract Retrieves video upload limits without changing video-service state. */
- (NSDictionary *)fetchVideoUploadLimits;

/** @abstract Retrieves health and normalizes successful responses to `status: online`. */
- (NSDictionary *)fetchVideoHealth;

/**
 * @abstract Requests a retry for a nonempty job identifier and changes job processing state.
 */
- (NSDictionary *)retryVideoJobWithId:(NSString *)jobId;

@end

NS_ASSUME_NONNULL_END
