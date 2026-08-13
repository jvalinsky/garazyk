// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpServer.h"

@class GZAdminUIAuthManager;
@class GZAdminUIBackendClient;

NS_ASSUME_NONNULL_BEGIN

#define AUTH_GUARD(weakSelf, req, res) \
    if (![weakSelf ensureAuthorized:(req) response:(res)]) return;

/**
 * @abstract Private helpers and categories that compose the admin HTTP server.
 * @discussion Route handlers must authorize requests before invoking renderers or backend
 * operations. Rendering methods transform backend dictionaries into HTML only; they do not
 * perform authorization or persistence. Call them on the server's request-handling context.
 */
NSString *GZAdminUIEscaped(NSString *value);
/** @abstract Returns a string value for a dictionary key, or nil when the value is not a string. */
NSString * _Nullable GZAdminUIStringFromDict(NSDictionary *dict, NSString *key);
/** @abstract Returns a string representation of a value, falling back when it is absent or unsafe. */
NSString *GZAdminUISafe(id value, NSString *fallback);
/** @abstract Returns the length of a string-like value, or zero for an unsupported value. */
NSUInteger GZAdminUISafeLength(id value);

/** @abstract Semantic badge for service health (`ok`/`healthy`, `degraded`, else error). */
NSString *GZAdminUIHealthBadge(NSString * _Nullable health);
/** @abstract Semantic badge for connection-like status strings. */
NSString *GZAdminUIConnectionBadge(NSString * _Nullable status);
/** @abstract One label/value row for a `detail-card`. `valueHTML` is trusted markup. */
NSString *GZAdminUIDetailRow(NSString *label, NSString * _Nullable valueHTML);
/** @abstract Mono-formatted text node for numeric/exact values. */
NSString *GZAdminUIMonoValue(id _Nullable value);
/** @abstract Interactive JSON tree/raw viewer markup for a JSON-serializable value. */
NSString *GZAdminUIJSONViewer(id _Nullable value);
/** @abstract Opens a `detail-card` container. */
NSString *GZAdminUIDetailCardOpen(void);
/** @abstract Closes a `detail-card` container. */
NSString *GZAdminUIDetailCardClose(void);
/** @abstract Section heading used inside pack partials. */
NSString *GZAdminUISectionTitle(NSString *title);
/** @abstract Formats uptime seconds as `Nh Nm`. */
NSString *GZAdminUIFormatUptime(int64_t seconds);
/** @abstract Formats byte counts as `N MB`. */
NSString *GZAdminUIFormatMegabytes(int64_t bytes);
/** @abstract Generates a nonce for one response's content-security policy. */
NSString *GZAdminUIGenerateNonce(void);
/** @abstract Adds a nonce-bound CSP response header, allowing the configured PDS origin when present. */
void GZAdminUIApplyNonceCSP(ATProtoHttpResponse *response, NSString *nonce, NSString * _Nullable pdsOrigin);

/** @abstract The HTTP server that owns registered admin routes. */
@interface GZAdminUIHost ()


/** @abstract Server instance used to register and serve admin routes. */
@property(nonatomic, strong) ATProtoHttpServer *httpServer;
/** @abstract Immutable configuration for local UI routing and backend access. */
@property(nonatomic, strong, readwrite) GZAdminUIServiceConfig *configuration;
/** @abstract Backing storage for the composed pack list. */
@property(nonatomic, copy, readwrite) NSArray<Class> *packs;
/** @abstract PDSSession and credential authority used by `ensureAuthorized:response:`. */
@property(nonatomic, strong) GZAdminUIAuthManager *authManager;
/** @abstract Synchronous proxy for configured PDS, AppView, and Ozone operations. */
@property(nonatomic, strong) GZAdminUIBackendClient *backendClient;
/** @abstract Indicates whether the runtime has started serving requests. */
@property(nonatomic, assign, readwrite, getter=isRunning) BOOL running;

/** @abstract Validates the request's admin session and writes an unauthorized response on failure. */
- (BOOL)ensureAuthorized:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;

@end

/** @abstract Serves packaged browser assets without applying admin-page rendering. */
@interface GZAdminUIHost (StaticAssets)

/** @abstract Resolves a static asset path and writes its content or an HTTP error to the response. */
- (void)serveStaticAssetForPath:(NSString *)path response:(ATProtoHttpResponse *)response;

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
/** @abstract Serves or redirects Web Tiles unique-origin documents. */
- (void)handleWebTilesDocumentRequest:(ATProtoHttpRequest *)request
                             response:(ATProtoHttpResponse *)response;
/** @abstract Serves shuttle.js / worker.js on unique-origin hosts. */
- (void)handleWebTilesScriptRequest:(ATProtoHttpRequest *)request
                           response:(ATProtoHttpResponse *)response
                               body:(NSString *)body;
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
/** @abstract Registers Germ E2EE mailbox administration routes. */
- (void)registerGermRoutes;
@end

NS_ASSUME_NONNULL_END
