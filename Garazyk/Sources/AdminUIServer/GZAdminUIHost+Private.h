// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpServer.h"

@class UIAuthManager;
@class UIBackendClient;
@class XrpcDispatcher;

NS_ASSUME_NONNULL_BEGIN

#define AUTH_GUARD(weakSelf, req, res) \
    if (![weakSelf ensureAuthorized:(req) response:(res)]) return;

/**
 * @abstract Private helpers and categories that compose the admin HTTP server.
 * @discussion Route handlers must authorize requests before invoking renderers or backend
 * operations. Rendering methods transform backend dictionaries into HTML only; they do not
 * perform authorization or persistence. Call them on the server's request-handling context.
 */
NSString *UIEscaped(NSString *value);
/** @abstract Returns a string value for a dictionary key, or nil when the value is not a string. */
NSString * _Nullable UIStringFromDict(NSDictionary *dict, NSString *key);
/** @abstract Returns a string representation of a value, falling back when it is absent or unsafe. */
NSString *UISafe(id value, NSString *fallback);
/** @abstract Returns the length of a string-like value, or zero for an unsupported value. */
NSUInteger UISafeLength(id value);
/** @abstract Generates a nonce for one response's content-security policy. */
NSString *UIGenerateNonce(void);
/** @abstract Adds a nonce-bound CSP response header, allowing the configured PDS origin when present. */
void UIApplyNonceCSP(HttpResponse *response, NSString *nonce, NSString * _Nullable pdsOrigin);

/** @abstract The HTTP server that owns registered admin routes. */
@interface GZAdminUIHost ()


/** @abstract Server instance used to register and serve admin routes. */
@property(nonatomic, strong) HttpServer *httpServer;
/** @abstract Immutable configuration for local UI routing and backend access. */
@property(nonatomic, strong, readwrite) UIServiceConfig *configuration;
/** @abstract Backing storage for the composed pack list. */
@property(nonatomic, copy, readwrite) NSArray<Class> *packs;
/** @abstract Session and credential authority used by `ensureAuthorized:response:`. */
@property(nonatomic, strong) UIAuthManager *authManager;
/** @abstract Synchronous proxy for configured PDS, AppView, and Ozone operations. */
@property(nonatomic, strong) UIBackendClient *backendClient;
/** @abstract Dispatcher for XRPC requests exposed by the local server. */
@property(nonatomic, strong) XrpcDispatcher *xrpcDispatcher;
/** @abstract Indicates whether the runtime has started serving requests. */
@property(nonatomic, assign, readwrite, getter=isRunning) BOOL running;

/** @abstract Validates the request's admin session and writes an unauthorized response on failure. */
- (BOOL)ensureAuthorized:(HttpRequest *)request response:(HttpResponse *)response;

@end

/** @abstract Serves packaged browser assets without applying admin-page rendering. */
@interface GZAdminUIHost (StaticAssets)

/** @abstract Resolves a static asset path and writes its content or an HTTP error to the response. */
- (void)serveStaticAssetForPath:(NSString *)path response:(HttpResponse *)response;

@end

/** @abstract Escaped HTML partial renderers for already-authorized admin requests. */
@interface GZAdminUIHost (Renderers)
/** @abstract Renders the PDS account-search result. */
- (NSString *)renderAccountsPartial:(NSDictionary *)result;
/** @abstract Renders the PDS invite-code result. */
- (NSString *)renderInvitesPartial:(NSDictionary *)result;
/** @abstract Renders AppView aggregate metrics. */
- (NSString *)renderAppViewMetricsPartial:(NSDictionary *)result;
/** @abstract Renders AppView ingest health. */
- (NSString *)renderIngestHealthPartial:(NSDictionary *)result;
/** @abstract Renders the AppView backfill queue. */
- (NSString *)renderBackfillQueuePartial:(NSDictionary *)result;
/** @abstract Renders relay metrics. */
- (NSString *)renderRelayMetricsPartial:(NSDictionary *)result;
/** @abstract Renders one PDS account detail result. */
- (NSString *)renderAccountDetailPartial:(NSDictionary *)result;
/** @abstract Renders blob metadata, optionally scoped to a DID. */
- (NSString *)renderBlobsPartial:(NSDictionary *)result did:(nullable NSString *)did;
/** @abstract Renders PDS server statistics. */
- (NSString *)renderServerStatsPartial:(NSDictionary *)result;
/** @abstract Renders a paginated PDS audit-log result. */
- (NSString *)renderAuditLogPartial:(NSDictionary *)result;
/** @abstract Renders PDS moderation reports. */
- (NSString *)renderPDSReportsPartial:(NSDictionary *)result;
/** @abstract Renders relay upstream status. */
- (NSString *)renderRelayUpstreamsPartial:(NSDictionary *)result;
/** @abstract Renders a PLC DID lookup result. */
- (NSString *)renderPLCDIDPartial:(NSDictionary *)result;
/** @abstract Renders PLC operation-log entries. */
- (NSString *)renderPLCLogPartial:(NSDictionary *)result;
/** @abstract Renders PDS repository metadata. */
- (NSString *)renderDescribeRepoPartial:(NSDictionary *)result;
/** @abstract Renders a PDS record-list result. */
- (NSString *)renderListRecordsPartial:(NSDictionary *)result;
/** @abstract Renders a single PDS record result. */
- (NSString *)renderGetRecordPartial:(NSDictionary *)result;

/** @abstract Renders Ozone subject-status results. */
- (NSString *)renderOzoneStatusesPartial:(NSDictionary *)result;
/** @abstract Renders Ozone moderation events. */
- (NSString *)renderOzoneEventsPartial:(NSDictionary *)result;
/** @abstract Renders an Ozone subject result. */
- (NSString *)renderOzoneSubjectPartial:(NSDictionary *)result;
/** @abstract Renders Ozone team-member results. */
- (NSString *)renderOzoneTeamPartial:(NSDictionary *)result;
/** @abstract Renders Ozone set results. */
- (NSString *)renderOzoneSetsPartial:(NSDictionary *)result;
/** @abstract Renders Ozone template results. */
- (NSString *)renderOzoneTemplatesPartial:(NSDictionary *)result;
/** @abstract Renders Ozone configuration. */
- (NSString *)renderOzoneConfigPartial:(NSDictionary *)result;
/** @abstract Renders configured backend connection status. */
- (NSString *)renderConnectionsPartial;
/** @abstract Renders the server overview result. */
- (NSString *)renderOverviewPartial:(NSDictionary *)result;
/** @abstract Renders Merkle-search-tree account results. */
- (NSString *)renderMSTAccountsPartial:(NSDictionary *)result;
/** @abstract Renders Merkle-search-tree nodes. */
- (NSString *)renderMSTTreePartial:(NSDictionary *)result;
/** @abstract Renders Merkle-search-tree statistics. */
- (NSString *)renderMSTStatsPartial:(NSDictionary *)result;
/** @abstract Renders relay health. */
- (NSString *)renderRelayHealthPartial:(NSDictionary *)result;
/** @abstract Renders Ozone moderation reports. */
- (NSString *)renderOzoneModerationReportsPartial:(NSDictionary *)result;
/** @abstract Renders PLC health. */
- (NSString *)renderPLCHealthPartial:(NSDictionary *)result;
/** @abstract Renders PLC metrics. */
- (NSString *)renderPLCMetricsPartial:(NSDictionary *)result;
/** @abstract Renders a paginated PLC listing using the supplied cursor. */
- (NSString *)renderPLCListPartial:(NSDictionary *)result cursor:(nullable NSString *)cursor;
/** @abstract Renders Ozone scheduled actions. */
- (NSString *)renderOzoneScheduledPartial:(NSDictionary *)result;
/** @abstract Renders Ozone verification results. */
- (NSString *)renderOzoneVerificationPartial:(NSDictionary *)result;
/** @abstract Renders Ozone safelink rules. */
- (NSString *)renderOzoneSafelinksPartial:(NSDictionary *)result;
/** @abstract Renders Ozone setting options. */
- (NSString *)renderOzoneSettingsPartial:(NSDictionary *)result;
/** @abstract Renders Ozone signature-correlation results, including unavailable-state output. */
- (NSString *)renderOzoneSignaturesPartial:(nullable NSDictionary *)result;
/** @abstract Renders Ozone signature-search results. */
- (NSString *)renderOzoneSignatureResultsPartial:(NSDictionary *)result;
/** @abstract Renders Ozone hosting history, optionally scoped to a DID. */
- (NSString *)renderOzoneHostingPartial:(NSDictionary *)result did:(nullable NSString *)did;
/** @abstract Renders the lab shell with the response CSP nonce. */
- (NSString *)labShellHTML:(NSString *)nonce;
/** @abstract Serializes safe client metadata for the lab shell. */
- (NSString *)labClientMetadataJSON;
/** @abstract Renders video-service health. */
- (NSString *)renderVideoHealthPartial:(NSDictionary *)result;
/** @abstract Renders video-job results. */
- (NSString *)renderVideoJobsPartial:(NSDictionary *)result;
/** @abstract Renders a video-job detail result. */
- (NSString *)renderVideoJobDetailPartial:(NSDictionary *)result;
/** @abstract Renders video quota information. */
- (NSString *)renderVideoQuotasPartial:(NSDictionary *)result;

@end

/** @abstract Registers authenticated route groups on the runtime HTTP server. */
@interface GZAdminUIHost (Routes)
/** @abstract Registers PDS administration routes. */
- (void)registerPDSRoutes;
/** @abstract Registers AppView administration routes. */
- (void)registerAppViewRoutes;
/** @abstract Registers relay administration routes. */
- (void)registerRelayRoutes;
/** @abstract Registers PLC administration routes. */
- (void)registerPLCRoutes;
/** @abstract Registers data-explorer routes. */
- (void)registerDataExplorerRoutes;
/** @abstract Registers development-lab routes. */
- (void)registerLabRoutes;
/** @abstract Registers Ozone administration routes. */
- (void)registerOzoneRoutes;
/** @abstract Registers UI security-management routes. */
- (void)registerSecurityRoutes;
/** @abstract Registers chat administration routes. */
- (void)registerChatRoutes;
/** @abstract Registers video administration routes. */
- (void)registerVideoRoutes;
/** @abstract Registers Merkle-search-tree administration routes. */
- (void)registerMSTRoutes;
@end

NS_ASSUME_NONNULL_END
