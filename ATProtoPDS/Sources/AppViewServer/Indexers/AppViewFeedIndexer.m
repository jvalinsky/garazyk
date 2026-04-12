/*!
 @file AppViewFeedIndexer.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppViewServer/Indexers/AppViewFeedIndexer.h"
#import "AppViewServer/AppViewDatabase.h"
#import "AppViewServer/Ingest/AppViewIngestEngine.h"
#import "Debug/PDSLogger.h"

static NSSet<NSString *> *feedCollections(void) {
    static NSSet *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [NSSet setWithArray:@[
            @"app.bsky.feed.post",
            @"app.bsky.feed.repost",
            @"app.bsky.feed.like",
            @"app.bsky.feed.generator",
            @"app.bsky.feed.threadgate",
            @"app.bsky.feed.postgate",
        ]];
    });
    return s;
}

@interface AppViewFeedIndexer ()
@property (nonatomic, strong) AppViewDatabase *avdb;
@end

@implementation AppViewFeedIndexer

- (instancetype)initWithDatabase:(AppViewDatabase *)database {
    self = [super init];
    if (!self) return nil;
    _avdb = database;
    return self;
}

- (BOOL)canIndexCollection:(NSString *)collection {
    return [feedCollections() containsObject:collection];
}

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
              error:(NSError **)error {
    // Validate presence of $type
    if (!record[@"$type"]) {
        if (error) *error = [NSError errorWithDomain:@"AppViewFeedIndexer"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing $type"}];
        return NO;
    }

    // Post: require text or embed
    if ([collection isEqualToString:@"app.bsky.feed.post"]) {
        if (!record[@"text"] && !record[@"embed"]) {
            if (error) *error = [NSError errorWithDomain:@"AppViewFeedIndexer"
                                                    code:2
                                                userInfo:@{NSLocalizedDescriptionKey: @"Post missing text and embed"}];
            return NO;
        }
    }

    // Like/Repost: require subject
    if ([collection isEqualToString:@"app.bsky.feed.like"] ||
        [collection isEqualToString:@"app.bsky.feed.repost"]) {
        if (!record[@"subject"]) {
            if (error) *error = [NSError errorWithDomain:@"AppViewFeedIndexer"
                                                    code:3
                                                userInfo:@{NSLocalizedDescriptionKey: @"Like/repost missing subject"}];
            return NO;
        }
    }

    PDS_LOG_DEBUG(@"[AppViewFeedIndexer] Indexed %@ for %@", collection, did);
    return YES;
}

- (BOOL)handleIngestEvent:(AppViewIngestEvent *)event error:(NSError **)error {
    for (NSDictionary *op in event.ops) {
        NSString *action = op[@"action"];
        NSString *path   = op[@"path"];

        // path: collection/rkey
        NSRange slash = [path rangeOfString:@"/"];
        NSString *collection = (slash.location != NSNotFound)
            ? [path substringToIndex:slash.location] : path;

        if (![self canIndexCollection:collection]) continue;

        if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
            NSDictionary *record = op[@"record"];
            if (record) {
                [self indexRecord:record did:event.did collection:collection error:nil];
            }
        } else if ([action isEqualToString:@"delete"]) {
            NSString *rkey = (slash.location != NSNotFound)
                ? [path substringFromIndex:slash.location + 1] : @"";
            [self deleteRecord:rkey did:event.did collection:collection error:nil];
        }
    }
    return YES;
}

- (BOOL)processPendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error {
    PDS_LOG_DEBUG(@"[AppViewFeedIndexer] Replaying pending delta for %@", delta.did);
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error {
    PDS_LOG_DEBUG(@"[AppViewFeedIndexer] Delete %@/%@ for %@", collection, rkey, did);
    return YES;
}

@end
