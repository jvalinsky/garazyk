// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczP2PConfiguration.h

 @abstract WS16 Track A operator env parsing (phase-35 S6).

 @discussion `JELCZ_P2P` defaults off. When off, jelcz never dials the iroh-blobs
 sidecar even if `JELCZ_IROH_SIDECAR_URL` is set — HTTPS mirror paths are unchanged.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GZJelczP2PConfiguration : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Whether `JELCZ_P2P` is truthy (`1`, `true`, `yes`, `on`). Default NO. */
+ (BOOL)isP2PEnabledInEnvironment:(NSDictionary *)env;

/**
 HTTP base URL from `JELCZ_IROH_SIDECAR_URL`, or nil when unset/invalid.

 Loopback by default; set `JELCZ_IROH_SIDECAR_TRUST_LAN=1` for Docker/LAN hostnames.
 */
+ (nullable NSString *)irohSidecarHTTPBaseURLFromEnvironment:(NSDictionary *)env;

/** Whether `JELCZ_IROH_SIDECAR_TRUST_LAN` allows RFC1918 / docker hostnames. */
+ (BOOL)trustLanInEnvironment:(NSDictionary *)env;

/** YES when Track A iroh mirror fetch should be wired (`JELCZ_P2P` + valid HTTP URL). */
+ (BOOL)shouldWireIrohSidecarMirrorFetcherInEnvironment:(NSDictionary *)env;

@end

NS_ASSUME_NONNULL_END
