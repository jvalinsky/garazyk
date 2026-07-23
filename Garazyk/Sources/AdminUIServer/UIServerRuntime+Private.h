// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpServer.h"

@class UIAuthManager;
@class UIBackendClient;
@class XrpcDispatcher;

NS_ASSUME_NONNULL_BEGIN

#define AUTH_GUARD(weakSelf, req, res) \
    if (![weakSelf ensureAuthorized:(req) response:(res)]) return;

/// Shared helpers used across UIServerRuntime's implementation files.
NSString *UIEscaped(NSString *value);
NSString * _Nullable UIStringFromDict(NSDictionary *dict, NSString *key);
NSString *UISafe(id value, NSString *fallback);
NSUInteger UISafeLength(id value);
NSString *UIGenerateNonce(void);
void UIApplyNonceCSP(HttpResponse *response, NSString *nonce, NSString * _Nullable pdsOrigin);

@interface UIServerRuntime ()


@property(nonatomic, strong) HttpServer *httpServer;
@property(nonatomic, strong, readwrite) UIServiceConfig *configuration;
@property(nonatomic, strong) UIAuthManager *authManager;
@property(nonatomic, strong) UIBackendClient *backendClient;
@property(nonatomic, strong) XrpcDispatcher *xrpcDispatcher;
@property(nonatomic, assign, readwrite, getter=isRunning) BOOL running;

- (BOOL)ensureAuthorized:(HttpRequest *)request response:(HttpResponse *)response;

@end

/// Static browser asset serving. Implemented in UIServerRuntime+StaticAssets.m.
@interface UIServerRuntime (StaticAssets)

- (void)serveStaticAssetForPath:(NSString *)path response:(HttpResponse *)response;

@end

/// Admin-panel HTML partial renderers. Implemented in UIServerRuntime+Renderers.m.
@interface UIServerRuntime (Renderers)
- (NSString *)renderAccountsPartial:(NSDictionary *)result;
- (NSString *)renderInvitesPartial:(NSDictionary *)result;
- (NSString *)renderAppViewMetricsPartial:(NSDictionary *)result;
- (NSString *)renderIngestHealthPartial:(NSDictionary *)result;
- (NSString *)renderBackfillQueuePartial:(NSDictionary *)result;
- (NSString *)renderRelayMetricsPartial:(NSDictionary *)result;
- (NSString *)renderAccountDetailPartial:(NSDictionary *)result;
- (NSString *)renderBlobsPartial:(NSDictionary *)result did:(nullable NSString *)did;
- (NSString *)renderServerStatsPartial:(NSDictionary *)result;
- (NSString *)renderAuditLogPartial:(NSDictionary *)result;
- (NSString *)renderPDSReportsPartial:(NSDictionary *)result;
- (NSString *)renderRelayUpstreamsPartial:(NSDictionary *)result;
- (NSString *)renderPLCDIDPartial:(NSDictionary *)result;
- (NSString *)renderPLCLogPartial:(NSDictionary *)result;
- (NSString *)renderDescribeRepoPartial:(NSDictionary *)result;
- (NSString *)renderListRecordsPartial:(NSDictionary *)result;
- (NSString *)renderGetRecordPartial:(NSDictionary *)result;

- (NSString *)renderOzoneStatusesPartial:(NSDictionary *)result;
- (NSString *)renderOzoneEventsPartial:(NSDictionary *)result;
- (NSString *)renderOzoneSubjectPartial:(NSDictionary *)result;
- (NSString *)renderOzoneTeamPartial:(NSDictionary *)result;
- (NSString *)renderOzoneSetsPartial:(NSDictionary *)result;
- (NSString *)renderOzoneTemplatesPartial:(NSDictionary *)result;
- (NSString *)renderOzoneConfigPartial:(NSDictionary *)result;
- (NSString *)renderSessionsPartial:(NSDictionary *)result;
- (NSString *)renderAppPasswordsPartial:(NSDictionary *)result;
- (NSString *)renderChatConvosPartial:(NSDictionary *)result;
- (NSString *)renderChatMessagesPartial:(NSDictionary *)result;
- (NSString *)renderConnectionsPartial;
- (NSString *)renderOverviewPartial:(NSDictionary *)result;
- (NSString *)renderMSTAccountsPartial:(NSDictionary *)result;
- (NSString *)renderMSTTreePartial:(NSDictionary *)result;
- (NSString *)renderMSTStatsPartial:(NSDictionary *)result;
- (NSString *)renderRelayHealthPartial:(NSDictionary *)result;
- (NSString *)renderOzoneModerationReportsPartial:(NSDictionary *)result;
- (NSString *)renderPLCHealthPartial:(NSDictionary *)result;
- (NSString *)renderPLCMetricsPartial:(NSDictionary *)result;
- (NSString *)renderPLCListPartial:(NSDictionary *)result cursor:(nullable NSString *)cursor;
- (NSString *)renderOzoneScheduledPartial:(NSDictionary *)result;
- (NSString *)renderOzoneVerificationPartial:(NSDictionary *)result;
- (NSString *)renderOzoneSafelinksPartial:(NSDictionary *)result;
- (NSString *)renderOzoneSettingsPartial:(NSDictionary *)result;
- (NSString *)renderOzoneSignaturesPartial:(nullable NSDictionary *)result;
- (NSString *)renderOzoneSignatureResultsPartial:(NSDictionary *)result;
- (NSString *)renderOzoneHostingPartial:(NSDictionary *)result did:(nullable NSString *)did;
- (NSString *)labShellHTML:(NSString *)nonce;
- (NSString *)labClientMetadataJSON;
- (NSString *)renderVideoHealthPartial:(NSDictionary *)result;
- (NSString *)renderVideoJobsPartial:(NSDictionary *)result;
- (NSString *)renderVideoJobDetailPartial:(NSDictionary *)result;
- (NSString *)renderVideoQuotasPartial:(NSDictionary *)result;

@end


@interface UIServerRuntime (Routes)
- (void)registerPDSRoutes;
- (void)registerAppViewRoutes;
- (void)registerRelayRoutes;
- (void)registerPLCRoutes;
- (void)registerDataExplorerRoutes;
- (void)registerLabRoutes;
- (void)registerOzoneRoutes;
- (void)registerSecurityRoutes;
- (void)registerChatRoutes;
- (void)registerVideoRoutes;
- (void)registerMSTRoutes;
@end

NS_ASSUME_NONNULL_END
