// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAdminUIPack.h

 @abstract Contract for a service's admin UI route registration module.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GZAdminUIHost;

/*!
 @protocol GZAdminUIPack

 @abstract Registers one service's admin routes on a host and describes how that service
 appears in the shell navigation.

 @discussion Mirrors @c XrpcRoutePack: registration is a class method so packs stay stateless,
 and the host holds no compile-time knowledge of any conforming class beyond this protocol.
 */
@protocol GZAdminUIPack <NSObject>

/*! Stable identifier used for routing, logging, and shell composition. */
+ (NSString *)packIdentifier;

/*! Human-readable name shown in the shell navigation. */
+ (NSString *)displayName;

/*!
 @abstract Sidebar sections this pack contributes to the shell.
 @discussion Populated when the shell is made composable (WS11 M2 slice 4); packs register
 routes correctly before that milestone lands, so an empty array is a valid interim value.
 */
+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections;

/*! Registers this pack's routes on the host's HTTP server. */
+ (void)registerRoutesWithHost:(GZAdminUIHost *)host;

@end

NS_ASSUME_NONNULL_END
