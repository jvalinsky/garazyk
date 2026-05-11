// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewSearchIndexHook.h

 @abstract Index hook that pushes records to a search index.

 @discussion A built-in index hook that extracts searchable text from
 records and pushes them to a configured search endpoint. This enables
 full-text search across indexed records.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppView/Server/Hooks/AppViewIndexHook.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class AppViewSearchIndexHook

 @abstract Pushes indexed records to a search endpoint.
 */
@interface AppViewSearchIndexHook : NSObject <AppViewIndexHook>

/*!
 @method initWithSearchEndpoint:

 @abstract Initialize with the search endpoint URL.

 @param searchEndpoint The URL of the search indexing service.
 */
- (instancetype)initWithSearchEndpoint:(NSString *)searchEndpoint;

@end

NS_ASSUME_NONNULL_END
