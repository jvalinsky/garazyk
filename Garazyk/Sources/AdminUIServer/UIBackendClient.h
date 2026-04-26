#import <Foundation/Foundation.h>

@class UIServiceConfig;

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient : NSObject

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration;

- (NSDictionary *)fetchServiceOverview;
- (NSDictionary *)searchAccountsWithQuery:(nullable NSString *)query;
- (NSDictionary *)fetchInviteCodes;
- (NSDictionary *)disableInvitesForAccount:(NSString *)account;

// AppView Admin Operations
- (NSDictionary *)fetchAppViewMetrics;
- (NSDictionary *)fetchIngestHealth;
- (NSDictionary *)fetchBackfillQueueWithStatus:(nullable NSString *)status limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
- (NSDictionary *)retryBackfillForDID:(NSString *)did;
- (NSDictionary *)cancelBackfillForDID:(NSString *)did;
- (NSDictionary *)enqueueBackfillDIDs:(NSArray<NSString *> *)dids;
- (NSDictionary *)rebuildBackfillScope;

// Relay Admin Operations
- (NSDictionary *)fetchRelayMetrics;
- (NSDictionary *)fetchRelayUpstreams;
- (NSDictionary *)fetchRelayHealth;
- (NSDictionary *)requestCrawlForHostname:(NSString *)hostname;

// PLC Admin Operations
- (NSDictionary *)lookupDID:(NSString *)did;
- (NSDictionary *)fetchPLCLogForDID:(NSString *)did;
- (NSDictionary *)fetchPLCHealth;
- (NSDictionary *)fetchPLCMetrics;
- (NSDictionary *)fetchPLCList;
- (NSDictionary *)fetchPLCExportWithAfter:(nullable NSString *)after count:(NSUInteger)count;

// PDS Admin Operations (extended)
- (NSDictionary *)fetchAccountInfoForDID:(NSString *)did;
- (NSDictionary *)updateAccountHandle:(NSString *)handle forDID:(NSString *)did;
- (NSDictionary *)deleteAccount:(NSString *)did;
- (NSDictionary *)bulkTakedownAccounts:(NSArray<NSString *> *)dids;
- (NSDictionary *)bulkDeleteAccounts:(NSArray<NSString *> *)dids;
- (NSDictionary *)enableInvitesForAccount:(NSString *)account;
- (NSDictionary *)fetchServerStats;
- (NSDictionary *)fetchAuditLogWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;
- (NSDictionary *)fetchReportsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;
- (NSDictionary *)resolveReport:(NSString *)reportID action:(NSString *)action;

// Repo/Record Operations (Data Explorer)
- (NSDictionary *)describeRepo:(NSString *)did;
- (NSDictionary *)listRecordsForDID:(NSString *)did collection:(nullable NSString *)collection limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
- (NSDictionary *)getRecordForDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey;

// Chat Operations
- (NSDictionary *)fetchChatConvosWithLimit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
- (NSDictionary *)fetchChatMessagesForConvoID:(NSString *)convoID limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
- (NSDictionary *)lockChatConvo:(NSString *)convoID;

// Repo/Record Operations (Data Explorer) - read-only
- (NSDictionary *)fetchBlobsForDID:(NSString *)did limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
- (NSDictionary *)fetchBlobForDID:(NSString *)did cid:(NSString *)cid;

// Ozone Moderation Operations
- (NSDictionary *)fetchOzoneStatusesWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;
- (NSDictionary *)fetchOzoneEventsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;
- (NSDictionary *)emitModerationEvent:(NSDictionary *)event;
- (NSDictionary *)fetchSubjectStatusForDID:(NSString *)did;
- (NSDictionary *)fetchModerationReportsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;
- (NSDictionary *)fetchScheduledActionsWithStatuses:(nullable NSArray<NSString *> *)statuses cursor:(nullable NSString *)cursor limit:(NSUInteger)limit;
- (NSDictionary *)scheduleAction:(NSDictionary *)actionSpec;
- (NSDictionary *)cancelScheduledActionsForSubjects:(NSArray<NSString *> *)subjects;
- (NSDictionary *)listOzoneVerifications;
- (NSDictionary *)grantOzoneVerifications:(NSArray<NSDictionary *> *)verifications;
- (NSDictionary *)revokeOzoneVerifications:(NSArray<NSString *> *)dids;
- (NSDictionary *)fetchSafelinkRules;
- (NSDictionary *)addSafelinkRule:(NSDictionary *)rule;
- (NSDictionary *)removeSafelinkRule:(NSString *)url pattern:(NSString *)pattern;
- (NSDictionary *)listOzoneSettings;
- (NSDictionary *)upsertOzoneSetting:(NSDictionary *)option;
- (NSDictionary *)removeOzoneSettings:(NSArray<NSString *> *)keys;
- (NSDictionary *)findRelatedAccounts:(NSString *)did;
- (NSDictionary *)findSignatureCorrelation:(NSArray<NSString *> *)dids;
- (NSDictionary *)searchAccountsBySignature:(NSDictionary *)patterns;
- (NSDictionary *)fetchHostingHistoryForDID:(NSString *)did;

// Ozone Team Operations
- (NSDictionary *)fetchOzoneTeamMembers;
- (NSDictionary *)addOzoneTeamMember:(NSDictionary *)member;
- (NSDictionary *)removeOzoneTeamMember:(NSString *)did;

// Ozone Set Operations
- (NSDictionary *)fetchOzoneSetsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;
- (NSDictionary *)upsertOzoneSet:(NSDictionary *)setSpec;
- (NSDictionary *)deleteOzoneSet:(NSString *)name;

// Ozone Template Operations
- (NSDictionary *)fetchOzoneTemplates;
- (NSDictionary *)createOzoneTemplate:(NSDictionary *)template;
- (NSDictionary *)deleteOzoneTemplate:(NSString *)name;

// Ozone Configuration
- (NSDictionary *)fetchOzoneConfig;
- (NSDictionary *)updateOzoneConfig:(NSDictionary *)config;

// Security Operations
- (NSDictionary *)fetchActiveSessionsForDID:(NSString *)did;
- (NSDictionary *)revokeSessionForDID:(NSString *)did sessionID:(NSString *)sessionID;
- (NSDictionary *)fetchAppPasswordsForDID:(NSString *)did;
- (NSDictionary *)createAppPasswordForDID:(NSString *)did name:(NSString *)passwordName;
- (NSDictionary *)deleteAppPasswordForDID:(NSString *)did passwordName:(NSString *)passwordName;

// MST Viewer Operations
- (NSDictionary *)fetchMSTAccounts;
- (NSDictionary *)fetchMSTTreeForDID:(NSString *)did;
- (NSDictionary *)fetchMSTStatsForDID:(NSString *)did;
- (NSData *)fetchMSTExportForDID:(NSString *)did format:(NSString *)format;

@end

NS_ASSUME_NONNULL_END

