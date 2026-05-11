// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppView/Services/BookmarkService.h"
#import "Database/PDSDatabase.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/FeedService.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Database/Schema.h"

@interface BookmarkService ()
@property (nonatomic, strong) id<PDSQueryDatabase> database;
@property (nonatomic, strong) ActorService *actorService;
@property (nonatomic, strong) FeedService *feedService;
@end

@implementation BookmarkService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
        _actorService = [[ActorService alloc] initWithDatabase:database];
        _feedService = [[FeedService alloc] initWithDatabase:database];
    }
    return self;
}

- (nullable NSDictionary *)getBookmarksForActor:(NSString *)actorDID
                                           limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error {
    limit = MIN(MAX(limit, 1), 100);

    NSString *query = @"SELECT subject_uri, subject_cid, created_at FROM bookmarks WHERE did = ?";
    if (cursor) {
        // Simple cursor based on ID or created_at. For now, let's use created_at descending.
        query = [query stringByAppendingString:@" AND created_at < ?"];
    }
    query = [query stringByAppendingString:@" ORDER BY created_at DESC LIMIT ?"];

    NSMutableArray *args = [NSMutableArray arrayWithObject:actorDID];
    if (cursor) {
        [args addObject:cursor];
    }
    [args addObject:@(limit)];

    NSArray *rows = [self.database executeParameterizedQuery:query params:args error:error];
    if (!rows) return nil;

    NSMutableArray *bookmarks = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSString *subjectURI = row[@"subject_uri"];
        NSDictionary *post = [self.feedService getPostByURI:subjectURI error:nil];
        if (post) {
            NSDictionary *formattedPost = [self.feedService formatPostRecord:subjectURI cid:[self.feedService generateCIDForRecord:post] record:post];
            if (formattedPost) {
                [bookmarks addObject:@{
                    @"uri": subjectURI,
                    @"cid": row[@"subject_cid"] ?: @"",
                    @"post": formattedPost,
                    @"createdAt": row[@"created_at"] ?: @""
                }];
            }
        }
    }

    NSString *nextCursor = nil;
    if (bookmarks.count > 0 && bookmarks.count == limit) {
        nextCursor = [[bookmarks lastObject] objectForKey:@"createdAt"];
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"bookmarks"] = bookmarks;
    if (nextCursor) {
        result[@"cursor"] = nextCursor;
    }

    return [result copy];
}

- (BOOL)indexBookmark:(NSDictionary *)record
                  did:(NSString *)did
                  uri:(NSString *)uri
                  cid:(nullable NSString *)cid
                error:(NSError **)error {
    // Record schema: { subject: { uri: "...", cid: "..." }, createdAt: "..." }
    NSDictionary *subject = record[@"subject"];
    if (![subject isKindOfClass:[NSDictionary class]]) return NO;

    NSString *subjectURI = subject[@"uri"];
    NSString *subjectCID = subject[@"cid"];
    NSString *createdAt = record[@"createdAt"] ?: @"";

    if (!subjectURI) return NO;

    NSString *sql = @"INSERT OR REPLACE INTO bookmarks (did, uri, subject_uri, subject_cid, created_at) VALUES (?, ?, ?, ?, ?)";
    return [self.database executeParameterizedUpdate:sql params:@[did, uri, subjectURI, subjectCID ?: [NSNull null], createdAt] error:error];
}

- (BOOL)indexBookmarkWithDid:(NSString *)did
                subjectURI:(NSString *)subjectURI
                subjectCID:(nullable NSString *)subjectCID
                 createdAt:(NSString *)createdAt
                     error:(NSError **)error {
    
    // For XRPC-based bookmarks, we use subject_uri as both 'uri' and 'subject_uri'
    NSString *sql = @"INSERT OR REPLACE INTO bookmarks (did, uri, subject_uri, subject_cid, created_at) VALUES (?, ?, ?, ?, ?)";
    return [self.database executeParameterizedUpdate:sql 
                                             params:@[did, subjectURI, subjectURI, subjectCID ?: [NSNull null], createdAt] 
                                              error:error];
}

- (BOOL)unindexBookmarkWithURI:(NSString *)uri
                           did:(NSString *)did
                         error:(NSError **)error {
    return [self.database executeParameterizedUpdate:@"DELETE FROM bookmarks WHERE did = ? AND uri = ?"
                                              params:@[did, uri]
                                               error:error];
}

- (BOOL)unindexBookmarkWithSubjectURI:(NSString *)subjectURI
                                 did:(NSString *)did
                               error:(NSError **)error {
    return [self.database executeParameterizedUpdate:@"DELETE FROM bookmarks WHERE did = ? AND subject_uri = ?"
                                              params:@[did, subjectURI]
                                               error:error];
}

@end
