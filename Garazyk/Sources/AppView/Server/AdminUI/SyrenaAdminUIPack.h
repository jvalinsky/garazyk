// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

@class GZAdminUIHost;
@class GZSyrenaAdminSnapshot;

NS_ASSUME_NONNULL_BEGIN

@interface GZSyrenaAdminUIPack : NSObject <GZAdminUIPack>

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZSyrenaAdminSnapshot *)snapshot;

/** Serving tab — client-facing health + three-lane pulse. */
+ (NSString *)servingHTML:(NSDictionary *)snapshot;
/** ATProtoFirehose tab — relay ingest. */
+ (NSString *)firehoseHTML:(NSDictionary *)snapshot;
/** Repo sync tab — funnel, enqueue, queue actions. */
+ (NSString *)repoSyncHTML:(NSDictionary *)snapshot queue:(NSDictionary *)queue;
/** Coverage tab — social index completeness. */
+ (NSString *)coverageHTML:(NSDictionary *)snapshot;
/** Exceptions triage — bounded dead-letter tables. */
+ (NSString *)exceptionsHTML:(NSDictionary *)exceptions;
/** Probe console — allowlisted admin method catalog + result. */
+ (NSString *)probeHTML:(NSArray *)catalog result:(nullable NSDictionary *)result;
/** Actor dig — hydrated indexed profile card. */
+ (NSString *)actorDigHTML:(NSDictionary *)dig;
/** Queue-only fragment for HTMX refresh (#appview-queue). */
+ (NSString *)queueTableHTML:(NSDictionary *)queue;

// Compatibility aliases used by older tests / call sites.
+ (NSString *)overviewHTML:(NSDictionary *)snapshot;
+ (NSString *)ingestionHTML:(NSDictionary *)snapshot;
+ (NSString *)backfillHTML:(NSDictionary *)snapshot;
+ (NSString *)indexesHTML:(NSDictionary *)snapshot;

@end

NS_ASSUME_NONNULL_END
