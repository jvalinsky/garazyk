// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient (Ozone)

/**
 * @abstract Fetch ozone statuses with cursor.
 * @param cursor Pagination cursor from a previous response.
 * @param limit Maximum number of records to return.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchOzoneStatusesWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

- (NSDictionary *)fetchOzoneEventsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

- (NSDictionary *)emitModerationEvent:(NSDictionary *)event;

- (NSDictionary *)fetchSubjectStatusForDID:(NSString *)did;

- (NSDictionary *)fetchModerationReportsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

/**
 * @abstract Fetch scheduled actions with statuses.
 * @param statuses Scheduled action status filters.
 * @param cursor Pagination cursor from a previous response.
 * @param limit Maximum number of records to return.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchScheduledActionsWithStatuses:(nullable NSArray<NSString *> *)statuses cursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

- (NSDictionary *)scheduleAction:(NSDictionary *)actionSpec;

- (NSDictionary *)cancelScheduledActionsForSubjects:(NSArray<NSString *> *)subjects;

- (NSDictionary *)listOzoneVerifications;

/**
 * @abstract Grant ozone verifications.
 * @param verifications Verification records to apply.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)grantOzoneVerifications:(NSArray<NSDictionary *> *)verifications;

- (NSDictionary *)revokeOzoneVerifications:(NSArray<NSString *> *)dids;

- (NSDictionary *)fetchSafelinkRules;

- (NSDictionary *)fetchOzoneSettings;

- (NSDictionary *)addSafelinkRule:(NSDictionary *)rule;

- (NSDictionary *)removeSafelinkRule:(NSString *)url pattern:(NSString *)pattern;

/**
 * @abstract List ozone settings.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)listOzoneSettings;

- (NSDictionary *)upsertOzoneSetting:(NSDictionary *)option;

- (NSDictionary *)removeOzoneSettings:(NSArray<NSString *> *)keys;

- (NSDictionary *)findRelatedAccounts:(NSString *)did;

- (NSDictionary *)findSignatureCorrelation:(NSArray<NSString *> *)dids;

- (NSDictionary *)searchAccountsBySignature:(NSDictionary *)patterns;

- (NSDictionary *)fetchHostingHistoryForDID:(NSString *)did;

/**
 * @abstract Fetch ozone team members.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchOzoneTeamMembers;

- (NSDictionary *)addOzoneTeamMember:(NSDictionary *)member;

- (NSDictionary *)removeOzoneTeamMember:(NSString *)did;

- (NSDictionary *)fetchOzoneSetsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

- (NSDictionary *)upsertOzoneSet:(NSDictionary *)setSpec;

/**
 * @abstract Delete ozone set.
 * @param name Resource name.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)deleteOzoneSet:(NSString *)name;

- (NSDictionary *)fetchOzoneTemplates;

- (NSDictionary *)createOzoneTemplate:(NSDictionary *)template;

- (NSDictionary *)deleteOzoneTemplate:(NSString *)name;

/**
 * @abstract Fetch ozone config.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchOzoneConfig;

- (NSDictionary *)updateOzoneConfig:(NSDictionary *)config;

@end

NS_ASSUME_NONNULL_END
