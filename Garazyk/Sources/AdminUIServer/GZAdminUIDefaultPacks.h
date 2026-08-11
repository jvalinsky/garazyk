// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAdminUIDefaultPacks.h

 @abstract Composition root listing service-neutral Admin UI packs.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Returns the service-neutral packs in shell tab order.
 * @discussion Service-owned packs are appended by their compatibility executable. This preserves
 * the Admin UI library's one-way dependency boundary.
 */
FOUNDATION_EXPORT NSArray<Class> *GZAdminUIDefaultPacks(void);

NS_ASSUME_NONNULL_END
