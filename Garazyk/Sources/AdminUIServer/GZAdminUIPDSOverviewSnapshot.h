// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAdminUIPDSOverviewSnapshot.h
 @abstract Protocol for a cheap local PDS overview snapshot (embedded kaszlak).
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Implemented by @c GZPDSAdminSnapshot. Stored on @c GZAdminUIPDSPack so
 @c /admin/partials/pds-stats can skip the XRPC round-trip when embedded.
 */
@protocol GZAdminUIPDSOverviewSnapshot <NSObject>
- (NSDictionary<NSString *, id> *)snapshot;
@end

NS_ASSUME_NONNULL_END
