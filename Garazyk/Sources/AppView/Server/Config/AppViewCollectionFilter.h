// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAppViewCollectionFilter.h

 @abstract Collection allowlist matcher for scoped AppView indexing.

 @discussion When the allowlist is empty, all collections are allowed
 (current behaviour). When non-empty, a collection NSID matches if:
   - it equals an entry exactly (no trailing dot), or
   - it starts with an entry that ends with a dot (prefix match).

 This lets operators write `site.standard.` to match the entire
 site.standard.* family, or `site.standard.document` to match only
 that one collection.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class GZAppViewCollectionFilter

 @abstract Matches collection NSIDs against an optional allowlist.
 */
@interface GZAppViewCollectionFilter : NSObject

/*!
 @property allowlist

 @abstract The collection allowlist entries. Empty means allow all.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *allowlist;

/*!
 @method initWithAllowlist:

 @abstract Create a filter with the given allowlist entries.
 Empty array = allow all collections.
 */
- (instancetype)initWithAllowlist:(NSArray<NSString *> *)allowlist;

/*!
 @method shouldIndexCollection:

 @abstract Returns YES if the collection should be indexed.

 @discussion Empty allowlist => YES for everything.
 Non-empty allowlist => YES only if the NSID matches an entry
 (exact or prefix per the trailing-dot rule).
 */
- (BOOL)shouldIndexCollection:(NSString *)collection;

@end

NS_ASSUME_NONNULL_END
