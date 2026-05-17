// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/**
 * @abstract Reads and maintains AppView bookmark index rows.
 */
@interface BookmarkService : NSObject

/**
 * @abstract Initializes the service with a query database.
 */
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

/**
 * @abstract Returns bookmarks for an actor using cursor pagination.
 */
- (nullable NSDictionary *)getBookmarksForActor:(NSString *)actorDID
                                           limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error;

/**
 * @abstract Indexes a bookmark record from repository data.
 */
- (BOOL)indexBookmark:(NSDictionary *)record
                  did:(NSString *)did
                  uri:(NSString *)uri
                  cid:(nullable NSString *)cid
                error:(NSError **)error;

/**
 * @abstract Indexes a bookmark from normalized subject fields.
 */
- (BOOL)indexBookmarkWithDid:(NSString *)did
                subjectURI:(NSString *)subjectURI
                subjectCID:(nullable NSString *)subjectCID
                 createdAt:(NSString *)createdAt
                     error:(NSError **)error;

/**
 * @abstract Removes a bookmark index row by bookmark record URI.
 */
- (BOOL)unindexBookmarkWithURI:(NSString *)uri
                           did:(NSString *)did
                         error:(NSError **)error;

/**
 * @abstract Removes a bookmark index row by bookmarked subject URI.
 */
- (BOOL)unindexBookmarkWithSubjectURI:(NSString *)subjectURI
                                 did:(NSString *)did
                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
