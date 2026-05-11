// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewConfiguration.h

 @abstract Configuration contract for the standalone AppView server.

 @discussion Loaded from the same config file as PDSConfiguration (or a
 dedicated appview.conf file in the data directory), keyed under the
 `appview.*` namespace.

 Key / env-var mapping:

   Key                                   Env var
   ─────────────────────────────────────────────────────────────────────
   appview.mode                          APPVIEW_MODE
   appview.relay_urls[]                  APPVIEW_RELAY_URLS (comma-sep)
   appview.cursor.checkpoint_interval_ms APPVIEW_CURSOR_CHECKPOINT_MS
   appview.backfill.enabled              APPVIEW_BACKFILL_ENABLED
   appview.backfill.global_workers       APPVIEW_BACKFILL_GLOBAL_WORKERS
   appview.backfill.per_host_workers     APPVIEW_BACKFILL_PER_HOST_WORKERS
   appview.master_secret                 APPVIEW_MASTER_SECRET
   appview.plc.url                       APPVIEW_PLC_URL
   appview.partial.enabled               APPVIEW_PARTIAL_ENABLED
   appview.partial.seed_dids[]           APPVIEW_PARTIAL_SEED_DIDS (comma-sep)
   appview.partial.allowlist[]           APPVIEW_PARTIAL_ALLOWLIST (comma-sep)
   appview.partial.ttl_hours             APPVIEW_PARTIAL_TTL_HOURS
   appview.partial.proxy_fallback        APPVIEW_PARTIAL_PROXY_FALLBACK
   appview.partial.proxy_fallback_url    APPVIEW_PARTIAL_PROXY_FALLBACK_URL
   appview.http.port                     APPVIEW_HTTP_PORT
   appview.data_directory                APPVIEW_DATA_DIR
   appview.admin_secret                  APPVIEW_ADMIN_SECRET

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @enum AppViewMode

 @abstract Operating mode for app.bsky.* request handling.

 @constant AppViewModeProxy     Forward all app.bsky.* requests to upstream AppView.
 @constant AppViewModeStandalone Run a local, self-contained AppView.
 */
typedef NS_ENUM(NSInteger, AppViewMode) {
    AppViewModeProxy      = 0,
    AppViewModeStandalone = 1,
};

/*!
 @class AppViewConfiguration

 @abstract Configuration for the standalone AppView runtime.
 */
@interface AppViewConfiguration : NSObject

#pragma mark - Core

/*! Operating mode. Default: AppViewModeStandalone. */
@property (nonatomic, assign) AppViewMode mode;

/*! Relay WebSocket URLs to subscribe to. E.g. wss://bsky.network. */
@property (nonatomic, strong) NSArray<NSString *> *relayURLs;

/*! Directory for the AppView database and working files. */
@property (nonatomic, copy)   NSString *dataDirectory;

/*! Port for the AppView HTTP query API. Default 3200. */
@property (nonatomic, assign) NSUInteger httpPort;

/*! Shared master secret for verifying PDS-signed JWTs. */
@property (nonatomic, copy, nullable) NSString *masterSecret;

/*! Admin API secret for admin endpoints. */
@property (nonatomic, copy, nullable) NSString *adminSecret;

#pragma mark - Cursor / Checkpoint

/*! How often to persist the relay cursor (ms). Default 5000. */
@property (nonatomic, assign) NSUInteger cursorCheckpointIntervalMs;

#pragma mark - PLC

/*! PLC directory URL for DID resolution during backfill. Default: https://plc.directory */
@property (nonatomic, copy) NSString *plcURL;

#pragma mark - Backfill

/*! Whether to run the backfill orchestrator. Default YES. */
@property (nonatomic, assign) BOOL backfillEnabled;

/*! Global concurrent backfill worker cap. Default 8. */
@property (nonatomic, assign) NSUInteger backfillGlobalWorkers;

/*! Per-PDS-host concurrent worker cap. Default 2. */
@property (nonatomic, assign) NSUInteger backfillPerHostWorkers;

#pragma mark - Partial / Interest-Graph Mode

/*! Whether to enable partial (relevance-scoped) materialization. Default NO (materialize all). */
@property (nonatomic, assign) BOOL partialEnabled;

/*! DIDs that are permanent relevance-set members (seeds). */
@property (nonatomic, strong) NSArray<NSString *> *partialSeedDIDs;

/*! DIDs that are explicitly allowlisted (permanent members). */
@property (nonatomic, strong) NSArray<NSString *> *partialAllowlist;

/*! TTL in hours for dynamic relevance entries. Default 168 (7 days). */
@property (nonatomic, assign) NSUInteger partialTTLHours;

/*! When YES, proxy to upstream for non-R query misses while backfill is in progress. */
@property (nonatomic, assign) BOOL partialProxyFallback;

/*! Upstream AppView URL for proxy fallback. */
@property (nonatomic, copy, nullable) NSString *partialProxyFallbackURL;

#pragma mark - Video

/*! Base URL of the Jelcz video service for constructing HLS playlist URLs. */
@property (nonatomic, copy, nullable) NSString *videoServiceURL;

#pragma mark - Lifecycle

/*!
 @method defaultConfiguration

 @abstract Returns a configuration with all defaults set.
 */
+ (instancetype)defaultConfiguration;

/*!
 @method configurationFromEnvironment

 @abstract Reads configuration from environment variables.
 Returns default configuration with env overrides applied.
 */
+ (instancetype)configurationFromEnvironment;

/*!
 @method loadFromDictionary:

 @abstract Apply values from a dictionary (typically loaded from a config file).
 Keys follow the `appview.*` dotted format above but without the "appview." prefix.
 */
- (void)loadFromDictionary:(NSDictionary *)dict;

/*!
 @method validate:

 @abstract Validate the configuration. Returns NO if required values are missing.
 */
- (BOOL)validate:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
