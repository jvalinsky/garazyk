// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient (Video)

/**
 * @abstract Fetch video jobs with state.
 * @param state Job state filter.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor from a previous response.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchVideoJobsWithState:(nullable NSString *)state limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

- (NSDictionary *)fetchVideoJobById:(NSString *)jobId;

- (NSDictionary *)fetchVideoUploadLimits;

- (NSDictionary *)fetchVideoHealth;

/**
 * @abstract Retry video job with id.
 * @param jobId Video job identifier.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)retryVideoJobWithId:(NSString *)jobId;

@end

NS_ASSUME_NONNULL_END
