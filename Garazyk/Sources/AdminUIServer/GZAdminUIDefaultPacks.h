// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAdminUIDefaultPacks.h

 @abstract Composition root listing every pack garazyk-ui serves today.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Returns every pack garazyk-ui composes, in shell tab order.
 * @discussion This is the one place in the tree allowed to name every service's admin UI pack;
 * @c GZAdminUIHost itself holds no compile-time knowledge of any of them. Callers that want the
 * full existing route surface (garazyk-ui's main, and tests exercising it end to end) use this
 * instead of duplicating the pack list.
 */
FOUNDATION_EXPORT NSArray<Class> *GZAdminUIDefaultPacks(void);

NS_ASSUME_NONNULL_END
