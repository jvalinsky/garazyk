/*!
 @file AppViewNotificationIndexer.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppViewServer/Indexers/AppViewNotificationIndexer.h"
#import "AppViewServer/AppViewDatabase.h"
#import "AppViewServer/Ingest/AppViewIngestEngine.h"
#import "Debug/PDSLogger.h"

static NSSet<NSString *> *notifSources(void) {
    static NSSet *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [NSSet setWithArray:@[
            @"app.bsky.feed.like",
            @"app.bsky.feed.repost",
            @"app.bsky.feed.post",
            @"app.bsky.graph.follow",
        ]];
    });
    return s;
}

@interface AppViewNotificationIndexer ()
@property (nonatomic, strong) AppViewDatabase *avdb;
@end

@implementation AppViewNotificationIndexer

- (instancetype)initWithDatabase:(AppViewDatabase *)database {
    self = [super init];
    if (!self) return nil;
    _avdb = database;
    return self;
}

- (BOOL)canIndexCollection:(NSString *)collection {
    return [notifSources() containsObject:collection];
}

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
              error:(NSError **)error {
    // Notification fan-out:
    // - like/repost: extract subject AT-URI, parse DID from authority, fan to author
    // - post: extract reply.parent.uri for reply notif, facets for mention notifs
    // - follow: fan to subject DID

    NSString *recipientDID = nil;

    if ([collection isEqualToString:@"app.bsky.feed.like"] ||
        [collection isEqualToString:@"app.bsky.feed.repost"]) {
        NSDictionary *subject = record[@"subject"];
        NSString *uri = subject[@"uri"];
        recipientDID = [self _didFromATURI:uri];
    } else if ([collection isEqualToString:@"app.bsky.graph.follow"]) {
        recipientDID = record[@"subject"];
    } else if ([collection isEqualToString:@"app.bsky.feed.post"]) {
        NSDictionary *reply = record[@"reply"];
        NSDictionary *parent = reply[@"parent"];
        NSString *parentURI = parent[@"uri"];
        recipientDID = [self _didFromATURI:parentURI];
    }

    if (recipientDID && [_avdb isDIDRelevant:recipientDID]) {
        PDS_LOG_DEBUG(@"[AppViewNotificationIndexer] Fan-out %@ notif to %@", collection, recipientDID);
        // In a full implementation: insert into notifications table
    }

    return YES;
}

- (BOOL)handleIngestEvent:(AppViewIngestEvent *)event error:(NSError **)error {
    for (NSDictionary *op in event.ops) {
        NSString *action = op[@"action"];
        NSString *path   = op[@"path"];

        NSRange slash = [path rangeOfString:@"/"];
        NSString *collection = (slash.location != NSNotFound)
            ? [path substringToIndex:slash.location] : path;

        if (![self canIndexCollection:collection]) continue;

        if ([action isEqualToString:@"create"]) {
            NSDictionary *record = op[@"record"];
            if (record) [self indexRecord:record did:event.did collection:collection error:nil];
        } else if ([action isEqualToString:@"delete"]) {
            // Retract notification if record deleted
        }
    }
    return YES;
}

- (BOOL)processPendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error {
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error {
    return YES;
}

// ---------------------------------------------------------------------------

- (nullable NSString *)_didFromATURI:(nullable NSString *)atURI {
    // AT-URI format: at://did:xxx:yyy/collection/rkey
    if (!atURI || ![atURI hasPrefix:@"at://"]) return nil;
    NSString *rest = [atURI substringFromIndex:5];
    NSRange slash = [rest rangeOfString:@"/"];
    return (slash.location != NSNotFound) ? [rest substringToIndex:slash.location] : rest;
}

@end
