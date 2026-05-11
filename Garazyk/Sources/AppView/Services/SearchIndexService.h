// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file SearchIndexService.h

 @abstract Full-text search service using FTS5 for actor, post, and starter pack search.

 @discussion Provides skeleton search results (DIDs/URIs only) per the
 app.bsky.unspecced lexicon schemas. Uses SQLite FTS5 virtual tables
 with content= sync tables for index rebuild. Part of AppView layer.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppView/Server/Hooks/AppViewIndexHook.h"

@protocol PDSQueryDatabase;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class SearchIndexService

 @abstract FTS5-backed full-text search service.

 @discussion Provides skeleton search results for actors, posts, and starter packs.
 Results are lightweight (DIDs/URIs only) matching the unspecced skeleton lexicon format.
 Index is populated from the records table on startup if empty.
 */
@interface SearchIndexService : NSObject <AppViewIndexHook>

/*! Initialize with database connection. */
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

/*! Database connection (exposed for testing). */
@property (nonatomic, strong, readonly) id<PDSQueryDatabase> database;

#pragma mark - Search

/*! Search actors by query string. Returns skeleton results with DIDs. */
- (nullable NSDictionary *)searchActors:(NSString *)query
                                   limit:(NSInteger)limit
                                  cursor:(nullable NSString *)cursor
                                   error:(NSError **)error;

/*! Search posts by query string. Returns skeleton results with URIs. */
- (nullable NSDictionary *)searchPosts:(NSString *)query
                                  limit:(NSInteger)limit
                                 cursor:(nullable NSString *)cursor
                                  error:(NSError **)error;

/*! Search starter packs by query string. Returns skeleton results with URIs. */
- (nullable NSDictionary *)searchStarterPacks:(NSString *)query
                                         limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error;

#pragma mark - Index Management

/*! Rebuild the search index from records table. */
- (BOOL)rebuildIndexWithError:(NSError **)error;

/*! Populate the search index if empty. Called once at startup. */
- (BOOL)populateIndexIfEmptyWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
