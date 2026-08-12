// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

@class GZAdminUIBackendClient;

NS_ASSUME_NONNULL_BEGIN

/** @abstract Admin UI pack for the Ozone surface. */
@interface GZAdminUIOzonePack : NSObject <GZAdminUIPack>

/** @abstract Renders Ozone subject-status results. */
+ (NSString *)renderOzoneStatusesPartial:(NSDictionary *)result;
/** @abstract Renders Ozone moderation events. */
+ (NSString *)renderOzoneEventsPartial:(NSDictionary *)result;
/** @abstract Renders an Ozone subject result. */
+ (NSString *)renderOzoneSubjectPartial:(NSDictionary *)result;
/** @abstract Renders Ozone team-member results. */
+ (NSString *)renderOzoneTeamPartial:(NSDictionary *)result;
/** @abstract Renders Ozone set results. */
+ (NSString *)renderOzoneSetsPartial:(NSDictionary *)result;
/** @abstract Renders Ozone template results. */
+ (NSString *)renderOzoneTemplatesPartial:(NSDictionary *)result;
/** @abstract Renders Ozone configuration. */
+ (NSString *)renderOzoneConfigPartial:(NSDictionary *)result;
/** @abstract Renders Ozone moderation reports. */
+ (NSString *)renderOzoneModerationReportsPartial:(NSDictionary *)result;
/** @abstract Renders Ozone scheduled actions. */
+ (NSString *)renderOzoneScheduledPartial:(NSDictionary *)result;
/** @abstract Renders Ozone verification results. */
+ (NSString *)renderOzoneVerificationPartial:(NSDictionary *)result;
/** @abstract Renders Ozone safelink rules. */
+ (NSString *)renderOzoneSafelinksPartial:(NSDictionary *)result;
/** @abstract Renders Ozone setting options. */
+ (NSString *)renderOzoneSettingsPartial:(NSDictionary *)result;
/** @abstract Renders Ozone signature-correlation results, including unavailable-state output. */
+ (NSString *)renderOzoneSignaturesPartial:(nullable NSDictionary *)result;
/** @abstract Renders Ozone signature-search results. */
+ (NSString *)renderOzoneSignatureResultsPartial:(NSDictionary *)result;
/** @abstract Renders Ozone hosting history, optionally scoped to a DID. */
+ (NSString *)renderOzoneHostingPartial:(NSDictionary *)result did:(nullable NSString *)did;

/**
 * @abstract Renders the Ozone overview with reports/events/statuses/config already filled.
 * @discussion Nested HTMX placeholders were unreliable in the embedded shell; compose once.
 */
+ (NSString *)renderOzoneOverviewHTMLWithBackend:(GZAdminUIBackendClient *)backend;

@end

NS_ASSUME_NONNULL_END
