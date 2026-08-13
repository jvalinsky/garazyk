// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UITileLoadingHost.h

 @abstract Unique-origin Web Tiles loading-host helpers.

 @discussion Implements the loading-server redirect pattern from
 https://dasl.ing/tiles.html / @dasl/tiles: requests to `load.<baseHost>` for
 `/.well-known/web-tiles/` are redirected (303) to a random 20-letter
 subdomain of `baseHost`. Unique-origin responses carry the normative
 execution-policy headers plus `service-worker-allowed: /`.

Unique-origin hosts also serve shuttle.js / worker.js. CAR/MASL tile validation
and path→`{status,headers,body}` resolution live in Core/Storage
(`ATProtoWebTile`); host-side origin helpers gate postMessage peers. Full
mothership mediation remains separate.
 */

#import <Foundation/Foundation.h>
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

/** True when hostname is exactly `load.<baseHost>` (case-insensitive). */
FOUNDATION_EXPORT BOOL GZAdminUITileIsLoadHost(NSString *hostname, NSString *baseHost);

/**
 True when hostname is `<20 lowercase letters>.<baseHost>` (unique origin).
 */
FOUNDATION_EXPORT BOOL GZAdminUITileIsUniqueOriginHost(NSString *hostname, NSString *baseHost);

/** Returns a new `abcdefghijklmnopqrstuvwxyz` host label of length 20. */
FOUNDATION_EXPORT NSString *GZAdminUITileMakeUniqueOriginLabel(void);

/**
 Builds the 303 Location URL for a load-host request.

 `pathAndQuery` should begin with `/` (e.g. `/.well-known/web-tiles/`).
 */
FOUNDATION_EXPORT NSString *GZAdminUITileUniqueOriginRedirectURL(NSString *scheme,
                                                                  NSString *baseHost,
                                                                  NSString *pathAndQuery);

/** Minimal shuttle document HTML that loads shuttle.js. */
FOUNDATION_EXPORT NSString *GZAdminUITileShuttleHTML(void);

/** Shuttle bootstrap script (registers worker.js and relays messages). */
FOUNDATION_EXPORT NSString *GZAdminUITileShuttleJavaScript(void);

/** Service worker script (passthrough for /.well-known/web-tiles/). */
FOUNDATION_EXPORT NSString *GZAdminUITileServiceWorkerJavaScript(void);

/**
 True when `origin` is `https://` or `http://` + a unique-origin host of
 `baseHost`, or exactly the load host. Used to gate postMessage peers.
 */
FOUNDATION_EXPORT BOOL GZAdminUITileIsTrustedEmbedOrigin(NSString *origin, NSString *baseHost);

/**
 Builds an absolute origin (`scheme://label.baseHost`) for a unique-origin label.
 */
FOUNDATION_EXPORT NSString *GZAdminUITileUniqueOriginURL(NSString *scheme,
                                                          NSString *baseHost,
                                                          NSString *label);

/**
 Applies Web Tile execution-policy headers (and `service-worker-allowed`) to a
 unique-origin response.
 */
FOUNDATION_EXPORT void GZAdminUITileApplyUniqueOriginHeaders(ATProtoHttpResponse *response);

NS_ASSUME_NONNULL_END
