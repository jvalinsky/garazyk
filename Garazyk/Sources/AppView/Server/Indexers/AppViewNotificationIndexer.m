/*!
 @file AppViewNotificationIndexer.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Indexers/AppViewNotificationIndexer.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
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
               rkey:(NSString *)rkey
                cid:(nullable NSString *)cid
              error:(NSError **)error {
    // Notification fan-out:
    // - like/repost: extract subject AT-URI, parse DID from authority, fan to author
    // - post: extract reply.parent.uri for reply notif, facets for mention notifs
    // - follow: fan to subject DID

    if (!record || !did || !collection) {
        if (error) *error = [NSError errorWithDomain:@"AppViewNotificationIndexer"
                                                 code:400
                                             userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        return NO;
    }

    // Bounds check: reject excessively large records
    if (collection.length > 100) {
        PDS_LOG_WARN(@"[AppViewNotificationIndexer] Collection name too long: %@", collection);
        return NO;
    }

    NSString *recipientDID = nil;

    if ([collection isEqualToString:@"app.bsky.feed.like"] ||
        [collection isEqualToString:@"app.bsky.feed.repost"]) {
        NSDictionary *subject = record[@"subject"];
        if (!subject) return YES; // Nothing to fan out, not an error
        NSString *uri = subject[@"uri"];
        recipientDID = [self _didFromATURI:uri];
    } else if ([collection isEqualToString:@"app.bsky.graph.follow"]) {
        recipientDID = record[@"subject"];
    } else if ([collection isEqualToString:@"app.bsky.feed.post"]) {
        NSDictionary *reply = record[@"reply"];
        if (reply) {
            NSDictionary *parent = reply[@"parent"];
            NSString *parentURI = parent[@"uri"];
            recipientDID = [self _didFromATURI:parentURI];
        }
    }

    // Validate extracted DID
    if (recipientDID && recipientDID.length > 0 && recipientDID.length < 200) {
        if ([_avdb isDIDRelevant:recipientDID]) {
            PDS_LOG_DEBUG(@"[AppViewNotificationIndexer] Fan-out %@ notif to %@", collection, recipientDID);
            // In a full implementation: insert into notifications table
        }
    }

    return YES;
}

- (BOOL)handleIngestEvent:(AppViewIngestEvent *)event error:(NSError **)error {
    if (!event || !event.ops || event.ops.count == 0) {
        return YES; // Nothing to process, not an error
    }
    // Bounds check: limit ops processed per event
    NSArray *opsToProcess = event.ops;
    if (opsToProcess.count > 100) {
        PDS_LOG_WARN(@"[AppViewNotificationIndexer] Truncating ops from %lu to 100 for event seq=%lld",
                     (unsigned long)opsToProcess.count, (long long)event.seq);
        opsToProcess = [opsToProcess subarrayWithRange:NSMakeRange(0, 100)];
    }

    for (NSDictionary *op in opsToProcess) {
        NSString *action = op[@"action"];
        NSString *path   = op[@"path"];

        if (!action || !path) continue;

        NSRange slash = [path rangeOfString:@"/"];
        NSString *collection = (slash.location != NSNotFound)
            ? [path substringToIndex:slash.location] : path;
        NSString *opRkey = (slash.location != NSNotFound)
            ? [path substringFromIndex:slash.location + 1] : @"";

        if (![self canIndexCollection:collection]) continue;

        if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
            NSDictionary *record = op[@"record"];
            NSString *cid = op[@"cid"];
            if (record) {
                [self indexRecord:record did:event.did collection:collection rkey:opRkey cid:cid error:nil];
            }
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
