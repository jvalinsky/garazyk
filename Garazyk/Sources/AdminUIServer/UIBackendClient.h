// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class UIServiceConfig;

@class ATProtoSafeHTTPClient;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Calls backend admin services on behalf of the Admin UI.
 */
@interface UIBackendClient : NSObject

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration;

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration
                           httpClient:(nullable ATProtoSafeHTTPClient *)httpClient;

/**
 * Obtain a fresh admin JWT from the PDS /admin/login endpoint.
 *
 * Uses the pdsAdminPassword from the configuration. On success, stores
 * the returned token in configuration.pdsAdminToken and returns YES.
 * Returns NO if no password is configured or the login request fails.
 */
- (BOOL)refreshPDSAdminToken;

- (NSDictionary *)fetchServiceOverview;
- (NSDictionary *)testConnectionForService:(NSString *)serviceName;
/**
 * @abstract Test connection for service.
 * @param serviceName Backend service name.
 * @param baseURL Backend service base URL.
 * @param adminToken Admin authorization token.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)testConnectionForService:(NSString *)serviceName
                                   baseURL:(NSURL *)baseURL
                                adminToken:(nullable NSString *)adminToken;
- (NSDictionary *)searchAccountsWithQuery:(nullable NSString *)query;
/**
 * @abstract Fetch invite codes.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchInviteCodes;
- (NSDictionary *)disableInvitesForAccount:(NSString *)account;

// AppView Admin Operations
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

// Relay Admin Operations
/**
 * @abstract Fetch relay metrics.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchRelayMetrics;
- (NSDictionary *)fetchRelayUpstreams;
- (NSDictionary *)fetchRelayHealth;
- (NSDictionary *)requestCrawlForHostname:(NSString *)hostname;

// PLC Admin Operations
- (NSDictionary *)lookupDID:(NSString *)did;
/**
 * @abstract Fetch plclog for did.
 * @param did Actor DID for the request.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchPLCLogForDID:(NSString *)did;
- (NSDictionary *)fetchPLCHealth;
- (NSDictionary *)fetchPLCMetrics;
- (NSDictionary *)fetchPLCList;
- (NSDictionary *)fetchPLCExportWithAfter:(nullable NSString *)after count:(NSUInteger)count;

// PDS Admin Operations (extended)
/**
 * @abstract Fetch account info for did.
 * @param did Actor DID for the request.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchAccountInfoForDID:(NSString *)did;
- (NSDictionary *)updateAccountHandle:(NSString *)handle forDID:(NSString *)did;
- (NSDictionary *)deleteAccount:(NSString *)did;
- (NSDictionary *)bulkTakedownAccounts:(NSArray<NSString *> *)dids;
- (NSDictionary *)bulkDeleteAccounts:(NSArray<NSString *> *)dids;
- (NSDictionary *)enableInvitesForAccount:(NSString *)account;
/**
 * @abstract Fetch server stats.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchServerStats;
- (NSDictionary *)fetchAuditLogWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;
- (NSDictionary *)fetchReportsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;
- (NSDictionary *)resolveReport:(NSString *)reportID action:(NSString *)action;

// Repo/Record Operations (Data Explorer)
- (NSDictionary *)describeRepo:(NSString *)did;
/**
 * @abstract List records for did.
 * @param did Actor DID for the request.
 * @param collection Repository collection NSID.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor from a previous response.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)listRecordsForDID:(NSString *)did collection:(nullable NSString *)collection limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
- (NSDictionary *)getRecordForDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey;

// Chat Operations
/**
 * @abstract Fetch chat convos with limit.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor from a previous response.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchChatConvosWithLimit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
- (NSDictionary *)fetchChatMessagesForConvoID:(NSString *)convoID limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
- (NSDictionary *)lockChatConvo:(NSString *)convoID;

// Video Operations
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

// Repo/Record Operations (Data Explorer) - read-only
- (NSDictionary *)fetchBlobsForDID:(NSString *)did limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
- (NSDictionary *)fetchBlobForDID:(NSString *)did cid:(NSString *)cid;

// Ozone Moderation Operations
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

// Ozone Team Operations
/**
 * @abstract Fetch ozone team members.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchOzoneTeamMembers;
- (NSDictionary *)addOzoneTeamMember:(NSDictionary *)member;
- (NSDictionary *)removeOzoneTeamMember:(NSString *)did;

// Ozone Set Operations
- (NSDictionary *)fetchOzoneSetsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;
- (NSDictionary *)upsertOzoneSet:(NSDictionary *)setSpec;
/**
 * @abstract Delete ozone set.
 * @param name Resource name.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)deleteOzoneSet:(NSString *)name;

// Ozone Template Operations
- (NSDictionary *)fetchOzoneTemplates;
- (NSDictionary *)createOzoneTemplate:(NSDictionary *)template;
- (NSDictionary *)deleteOzoneTemplate:(NSString *)name;

// Ozone Configuration
/**
 * @abstract Fetch ozone config.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchOzoneConfig;
- (NSDictionary *)updateOzoneConfig:(NSDictionary *)config;

// Security Operations
- (NSDictionary *)fetchActiveSessionsForDID:(NSString *)did;
- (NSDictionary *)revokeSessionForDID:(NSString *)did sessionID:(NSString *)sessionID;
- (NSDictionary *)fetchAppPasswordsForDID:(NSString *)did;
/**
 * @abstract Create app password for did.
 * @param did Actor DID for the request.
 * @param passwordName Application password name.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)createAppPasswordForDID:(NSString *)did name:(NSString *)passwordName;
- (NSDictionary *)deleteAppPasswordForDID:(NSString *)did passwordName:(NSString *)passwordName;

// MST Viewer Operations
- (NSDictionary *)fetchMSTAccounts;
/**
 * @abstract Fetch msttree for did.
 * @param did Actor DID for the request.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchMSTTreeForDID:(NSString *)did;
- (NSDictionary *)fetchMSTStatsForDID:(NSString *)did;
- (NSData *)fetchMSTExportForDID:(NSString *)did format:(NSString *)format;

@end

NS_ASSUME_NONNULL_END
