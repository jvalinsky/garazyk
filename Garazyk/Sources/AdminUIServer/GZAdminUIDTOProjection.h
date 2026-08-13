// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAdminUIDTOProjection.h

 @abstract Shared allowlist projection for Admin UI backend dictionaries (WS11 M4).
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Copies only the named keys from @c src into a new dictionary.

 Null values are omitted. Unknown keys (including secrets / tokens / raw
 payloads) never appear in the result.
 */
FOUNDATION_EXPORT NSDictionary<NSString *, id> *GZAdminUIProjectDictionary(
    NSDictionary *src,
    NSArray<NSString *> *keys);

/**
 Projects each dictionary element of @c raw through @c GZAdminUIProjectDictionary.

 Non-dictionary elements are skipped. Non-array @c raw yields an empty array.
 */
FOUNDATION_EXPORT NSArray<NSDictionary *> *GZAdminUIProjectDictionaries(
    id _Nullable raw,
    NSArray<NSString *> *keys);

NS_ASSUME_NONNULL_END
