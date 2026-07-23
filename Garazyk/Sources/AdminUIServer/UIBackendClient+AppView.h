// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient (AppView)

- (NSDictionary *)fetchAppViewMetrics;

- (NSDictionary *)fetchIngestHealth;

- (NSDictionary *)fetchBackfillQueueWithStatus:(nullable NSString *)status limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

/**
 * @abstract Retry backfill for did.
 * @param did Actor DID for the request.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)retryBackfillForDID:(NSString *)did;

- (NSDictionary *)cancelBackfillForDID:(NSString *)did;

- (NSDictionary *)enqueueBackfillDIDs:(NSArray<NSString *> *)dids;

- (NSDictionary *)rebuildBackfillScope;

@end

NS_ASSUME_NONNULL_END
