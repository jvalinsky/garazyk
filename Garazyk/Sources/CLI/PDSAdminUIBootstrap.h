// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAdminUIBootstrap.h
 @abstract Starts the embedded PDS admin UI listener (GZAdminUIHost).
 */

#import <Foundation/Foundation.h>

@class GZAdminUIHost;
@protocol GZAdminUIPDSOverviewSnapshot;

NS_ASSUME_NONNULL_BEGIN

/*!
 @abstract Reads PDS_ADMIN_UI_PASSWORD, then PDS_ADMIN_PASSWORD / password-file
           (same sources as PDSAdminAuth).
 */
NSString * _Nullable PDSAdminUIResolvePassword(void);

/*!
 @abstract Starts GZAdminUIHost with the six PDS-owned packs.

 @discussion Binds to PDS_ADMIN_UI_HOST / PDS_ADMIN_UI_PORT (defaults
 127.0.0.1:2590). Points the backend client at the local protocol listener.
 Uses the same operator password for UI login and /admin/login token minting.
 When @c overviewSnapshot is non-nil, attaches it for cheap local stats polls.
 Returns nil when password is unset (admin UI disabled) or on listen failure.
 */
GZAdminUIHost * _Nullable PDSAdminUIStartHost(
    NSUInteger protocolPort,
    id<GZAdminUIPDSOverviewSnapshot> _Nullable overviewSnapshot,
    NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
