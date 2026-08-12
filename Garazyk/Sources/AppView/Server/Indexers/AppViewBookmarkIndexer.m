// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAppViewBookmarkIndexer.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Indexers/AppViewBookmarkIndexer.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Services/BookmarkService.h"
#import "Debug/GZLogger.h"

@interface GZAppViewBookmarkIndexer ()
@property (nonatomic, strong) GZAppViewDatabase *avdb;
@property (nonatomic, strong) PDSBookmarkService *bookmarkService;
@end

@implementation GZAppViewBookmarkIndexer

- (instancetype)initWithDatabase:(GZAppViewDatabase *)database
               bookmarkService:(PDSBookmarkService *)bookmarkService {
    self = [super init];
    if (!self) return nil;
    _avdb = database;
    _bookmarkService = bookmarkService;
    return self;
}

#pragma mark - AppViewIndexer

- (BOOL)canIndexCollection:(NSString *)collection {
    return [collection isEqualToString:@"app.bsky.bookmark"];
}

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
               rkey:(NSString *)rkey
                cid:(nullable NSString *)cid
              error:(NSError **)error {
    NSDictionary *bookmarkRecord = record[@"record"] ?: record;

    NSString *subjectURI = nil;
    NSString *subjectCID = nil;
    NSString *createdAt = nil;

    NSDictionary *subject = bookmarkRecord[@"subject"];
    if ([subject isKindOfClass:[NSDictionary class]]) {
        subjectURI = subject[@"uri"];
        subjectCID = subject[@"cid"];
    }

    id createdAtVal = bookmarkRecord[@"createdAt"];
    if ([createdAtVal isKindOfClass:[NSString class]]) {
        createdAt = (NSString *)createdAtVal;
    }

    if (!subjectURI) {
        if (error) *error = [NSError errorWithDomain:@"AppViewBookmarkIndexer"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing subject in bookmark record"}];
        return NO;
    }

    // A repo holds one bookmark record per rkey, and bookmarks.uri is UNIQUE, so
    // the rkey must reach the URI: hardcoding a constant here collapsed every
    // bookmark a DID owns onto one row that INSERT OR REPLACE kept overwriting,
    // and left deleteRecord: below (which does use rkey) matching nothing.
    if (rkey.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"AppViewBookmarkIndexer"
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing rkey in bookmark record"}];
        return NO;
    }

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSError *indexErr = nil;
    BOOL ok = [_bookmarkService indexBookmark:bookmarkRecord
                                     did:did
                                     uri:uri
                                     cid:cid
                                   error:&indexErr];
    if (!ok) {
        GZ_LOG_WARN(@"[AppViewBookmarkIndexer] Failed to index bookmark for %@: %@",
                     did, indexErr.localizedDescription);
        if (error) *error = indexErr;
        return NO;
    }

    GZ_LOG_DEBUG(@"[AppViewBookmarkIndexer] Indexed bookmark for %@: %@", did, uri);
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey
                  did:(NSString *)did
           collection:(NSString *)collection
               error:(NSError **)error {
    // Mirrors the URI construction in indexRecord:, including its rkey guard.
    if (rkey.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"AppViewBookmarkIndexer"
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing rkey in bookmark record"}];
        return NO;
    }

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSError *unindexErr = nil;
    BOOL ok = [_bookmarkService unindexBookmarkWithURI:uri
                                             did:did
                                           error:&unindexErr];
    if (!ok) {
        GZ_LOG_WARN(@"[AppViewBookmarkIndexer] Failed to unindex bookmark for %@: %@",
                    did, unindexErr.localizedDescription);
    }
    return ok;
}

@end