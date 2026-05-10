/*!
 @file AppViewBookmarkIndexer.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Indexers/AppViewBookmarkIndexer.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Services/BookmarkService.h"
#import "Debug/PDSLogger.h"

@interface AppViewBookmarkIndexer ()
@property (nonatomic, strong) AppViewDatabase *avdb;
@property (nonatomic, strong) BookmarkService *bookmarkService;
@end

@implementation AppViewBookmarkIndexer

- (instancetype)initWithDatabase:(AppViewDatabase *)database
               bookmarkService:(BookmarkService *)bookmarkService {
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

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, @"main"];
    NSError *indexErr = nil;
    BOOL ok = [_bookmarkService indexBookmark:bookmarkRecord
                                     did:did
                                     uri:uri
                                     cid:cid
                                   error:&indexErr];
    if (!ok) {
        PDS_LOG_WARN(@"[AppViewBookmarkIndexer] Failed to index bookmark for %@: %@",
                     did, indexErr.localizedDescription);
        if (error) *error = indexErr;
        return NO;
    }

    PDS_LOG_DEBUG(@"[AppViewBookmarkIndexer] Indexed bookmark for %@: %@", did, uri);
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey
                  did:(NSString *)did
           collection:(NSString *)collection
               error:(NSError **)error {
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey ?: @"main"];
    NSError *unindexErr = nil;
    BOOL ok = [_bookmarkService unindexBookmarkWithURI:uri
                                             did:did
                                           error:&unindexErr];
    if (!ok) {
        PDS_LOG_WARN(@"[AppViewBookmarkIndexer] Failed to unindex bookmark for %@: %@",
                    did, unindexErr.localizedDescription);
    }
    return ok;
}

@end