// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

@interface BookmarkService : NSObject

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

- (nullable NSDictionary *)getBookmarksForActor:(NSString *)actorDID
                                           limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error;

- (BOOL)indexBookmark:(NSDictionary *)record
                  did:(NSString *)did
                  uri:(NSString *)uri
                  cid:(nullable NSString *)cid
                error:(NSError **)error;

- (BOOL)indexBookmarkWithDid:(NSString *)did
                subjectURI:(NSString *)subjectURI
                subjectCID:(nullable NSString *)subjectCID
                 createdAt:(NSString *)createdAt
                     error:(NSError **)error;

- (BOOL)unindexBookmarkWithURI:(NSString *)uri
                           did:(NSString *)did
                         error:(NSError **)error;

- (BOOL)unindexBookmarkWithSubjectURI:(NSString *)subjectURI
                                 did:(NSString *)did
                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
