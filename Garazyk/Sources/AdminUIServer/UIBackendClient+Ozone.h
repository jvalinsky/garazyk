// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Moderation-service administration operations for the authenticated admin UI.
 * @discussion Requests use the PDS administrative transport, including its one-time token refresh
 * behavior. A 2xx upstream JSON response is returned unchanged; invalid arguments and upstream
 * failures are represented by dictionaries containing `error` and `message`. Mutation methods
 * have no compensating transaction or rollback.
 */
@interface UIBackendClient (Ozone)

/**
 * @abstract Lists moderation subject statuses using the optional cursor and requested page size.
 */
- (NSDictionary *)fetchOzoneStatusesWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

/** @abstract Lists moderation events using the optional cursor and requested page size. */
- (NSDictionary *)fetchOzoneEventsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

/** @abstract Creates the supplied moderation event and changes its subject's moderation state. */
- (NSDictionary *)emitModerationEvent:(NSDictionary *)event;

/** @abstract Retrieves the current moderation status for a nonempty subject DID. */
- (NSDictionary *)fetchSubjectStatusForDID:(NSString *)did;

/** @abstract Lists moderation reports using the optional cursor and requested page size. */
- (NSDictionary *)fetchModerationReportsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

/**
 * @abstract Lists scheduled actions filtered by optional statuses and paginated by cursor.
 */
- (NSDictionary *)fetchScheduledActionsWithStatuses:(nullable NSArray<NSString *> *)statuses cursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

/** @abstract Creates the supplied scheduled moderation action. */
- (NSDictionary *)scheduleAction:(NSDictionary *)actionSpec;

/** @abstract Cancels scheduled actions for the supplied subjects without rollback. */
- (NSDictionary *)cancelScheduledActionsForSubjects:(NSArray<NSString *> *)subjects;

/** @abstract Lists active Ozone verifications without changing moderation state. */
- (NSDictionary *)listOzoneVerifications;

/**
 * @abstract Grants the supplied verification records and changes moderation state.
 */
- (NSDictionary *)grantOzoneVerifications:(NSArray<NSDictionary *> *)verifications;

/** @abstract Revokes verifications for the supplied nonempty DID list. */
- (NSDictionary *)revokeOzoneVerifications:(NSArray<NSString *> *)dids;

/** @abstract Lists safelink rules using the service's fixed page size. */
- (NSDictionary *)fetchSafelinkRules;

/** @abstract Retrieves instance-scoped Ozone settings. */
- (NSDictionary *)fetchOzoneSettings;

/** @abstract Adds a validated safelink-rule specification. */
- (NSDictionary *)addSafelinkRule:(NSDictionary *)rule;

/** @abstract Removes the safelink rule identified by a nonempty URL and pattern. */
- (NSDictionary *)removeSafelinkRule:(NSString *)url pattern:(NSString *)pattern;

/**
 * @abstract Lists up to 50 instance-scoped Ozone options.
 */
- (NSDictionary *)listOzoneSettings;

/** @abstract Creates or updates the supplied Ozone option. */
- (NSDictionary *)upsertOzoneSetting:(NSDictionary *)option;

/** @abstract Removes the supplied nonempty option-key list. */
- (NSDictionary *)removeOzoneSettings:(NSArray<NSString *> *)keys;

/** @abstract Finds accounts related to a nonempty DID by Ozone signature data. */
- (NSDictionary *)findRelatedAccounts:(NSString *)did;

/** @abstract Computes signature correlations for a nonempty DID list. */
- (NSDictionary *)findSignatureCorrelation:(NSArray<NSString *> *)dids;

/** @abstract Searches accounts using the supplied signature-pattern specification. */
- (NSDictionary *)searchAccountsBySignature:(NSDictionary *)patterns;

/** @abstract Retrieves hosting history for a nonempty account DID. */
- (NSDictionary *)fetchHostingHistoryForDID:(NSString *)did;

/**
 * @abstract Lists Ozone team members without changing access control.
 */
- (NSDictionary *)fetchOzoneTeamMembers;

/** @abstract Adds the supplied team-member specification and changes moderation access control. */
- (NSDictionary *)addOzoneTeamMember:(NSDictionary *)member;

/** @abstract Removes a nonempty DID from the Ozone team. */
- (NSDictionary *)removeOzoneTeamMember:(NSString *)did;

/** @abstract Lists Ozone sets using the optional cursor and requested page size. */
- (NSDictionary *)fetchOzoneSetsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

/** @abstract Creates or updates the supplied Ozone set specification. */
- (NSDictionary *)upsertOzoneSet:(NSDictionary *)setSpec;

/**
 * @abstract Deletes the Ozone set identified by a nonempty resource name.
 */
- (NSDictionary *)deleteOzoneSet:(NSString *)name;

/** @abstract Lists Ozone moderation templates. */
- (NSDictionary *)fetchOzoneTemplates;

/** @abstract Creates the supplied Ozone moderation template. */
- (NSDictionary *)createOzoneTemplate:(NSDictionary *)template;

/** @abstract Deletes the Ozone template identified by a nonempty resource name. */
- (NSDictionary *)deleteOzoneTemplate:(NSString *)name;

/**
 * @abstract Retrieves Ozone configuration without changing service state.
 */
- (NSDictionary *)fetchOzoneConfig;

/** @abstract Replaces Ozone configuration with the supplied specification. */
- (NSDictionary *)updateOzoneConfig:(NSDictionary *)config;

@end

NS_ASSUME_NONNULL_END
