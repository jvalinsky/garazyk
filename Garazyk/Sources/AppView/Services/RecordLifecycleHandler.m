/*!
 @file RecordLifecycleHandler.m

 @abstract Record lifecycle handler implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Services/RecordLifecycleHandler.h"
#import "AppView/Services/NotificationService.h"
#import "Core/NSDictionary+CID.h"
#import "AppView/Services/BookmarkService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/FeedService.h"
#import "Services/PDS/PDSRecordService.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Debug/PDSLogger.h"

@interface RecordLifecycleHandler ()
@property (nonatomic, strong) NotificationService *notificationService;
@property (nonatomic, strong) BookmarkService *bookmarkService;
@property (nonatomic, strong) GraphService *graphService;
@property (nonatomic, strong) FeedService *feedService;
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation RecordLifecycleHandler

- (instancetype)initWithNotificationService:(NotificationService *)notificationService
                             bookmarkService:(BookmarkService *)bookmarkService
                                graphService:(GraphService *)graphService
                                 feedService:(FeedService *)feedService
                                    database:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _notificationService = notificationService;
        _bookmarkService = bookmarkService;
        _graphService = graphService;
        _feedService = feedService;
        _database = database;


        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleRecordChange:)
                                                     name:PDSRecordDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)stopObserving {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:PDSRecordDidChangeNotification
                                                   object:nil];
}

- (void)dealloc {
    [self stopObserving];
}

#pragma mark - Record Change Handler

- (void)handleRecordChange:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    if (!info) return;

    NSString *did = info[@"did"];
    NSString *collection = info[@"collection"];
    NSString *rkey = info[@"rkey"];
    NSString *action = info[@"action"];
    NSString *cid = [info cidStringForKey:@"cid"];
    NSData *recordCBOR = [info[@"recordCBOR"] isKindOfClass:[NSNull class]] ? nil : info[@"recordCBOR"];

    if (!did || !collection || !rkey || !action) return;

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

    if ([action isEqualToString:@"delete"]) {
        // When a record is deleted, remove associated notifications
        [self.notificationService deleteNotificationsForSubjectURI:uri error:nil];
        
        // Handle unindexing
        if ([collection isEqualToString:@"app.bsky.bookmark.bookmark"]) {
            [self.bookmarkService unindexBookmarkWithURI:uri did:did error:nil];
        } else if ([collection isEqualToString:@"app.bsky.graph.starterpack"]) {
            [self.graphService unindexStarterPackWithRKey:rkey did:did error:nil];
        } else if ([collection isEqualToString:@"app.bsky.feed.threadgate"]) {
            [self.feedService unindexThreadgateWithURI:uri error:nil];
        } else if ([collection isEqualToString:@"app.bsky.feed.postgate"]) {
            [self.feedService unindexPostgateWithURI:uri error:nil];
        } else if ([collection isEqualToString:@"app.bsky.feed.generator"]) {
            [self.feedService unindexGeneratorWithURI:uri error:nil];
        } else if ([collection isEqualToString:@"app.bsky.graph.list"]) {
            [self.graphService unindexListWithURI:uri error:nil];
        } else if ([collection isEqualToString:@"app.bsky.graph.listitem"]) {
            [self.graphService unindexListitemWithURI:uri error:nil];
        }
        return;
    }

    // Only process creates (not updates — updates would double-notify)
    if (![action isEqualToString:@"create"]) return;

    // Decode the record to extract relationship data
    NSDictionary *record = nil;
    if (recordCBOR) {
        record = [ATProtoCBORSerialization JSONObjectWithData:recordCBOR error:nil];
    }
    if (!record) return;

    // Dispatch based on collection type
    if ([collection isEqualToString:@"app.bsky.feed.like"]) {
        [self handleLike:record did:did uri:uri cid:cid];
    } else if ([collection isEqualToString:@"app.bsky.graph.follow"]) {
        [self handleFollow:record did:did uri:uri cid:cid];
    } else if ([collection isEqualToString:@"app.bsky.feed.repost"]) {
        [self handleRepost:record did:did uri:uri cid:cid];
    } else if ([collection isEqualToString:@"app.bsky.feed.post"]) {
        [self handlePost:record did:did uri:uri cid:cid];
    } else if ([collection isEqualToString:@"app.bsky.bookmark.bookmark"]) {
        [self.bookmarkService indexBookmark:record did:did uri:uri cid:cid error:nil];
    } else if ([collection isEqualToString:@"app.bsky.graph.starterpack"]) {
        [self.graphService indexStarterPack:record did:did rkey:rkey cid:cid error:nil];
    } else if ([collection isEqualToString:@"app.bsky.feed.threadgate"]) {
        [self.feedService indexThreadgate:record did:did uri:uri cid:cid error:nil];
    } else if ([collection isEqualToString:@"app.bsky.feed.postgate"]) {
        [self.feedService indexPostgate:record did:did uri:uri cid:cid error:nil];
    } else if ([collection isEqualToString:@"app.bsky.feed.generator"]) {
        [self.feedService indexGenerator:record did:did uri:uri cid:cid error:nil];
    } else if ([collection isEqualToString:@"app.bsky.graph.list"]) {
        [self.graphService indexList:record did:did uri:uri cid:cid error:nil];
    } else if ([collection isEqualToString:@"app.bsky.graph.listitem"]) {
        [self.graphService indexListitem:record did:did uri:uri cid:cid error:nil];
    }
}

#pragma mark - Like Notifications

- (void)handleLike:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid {
    NSDictionary *subject = record[@"subject"];
    if (![subject isKindOfClass:[NSDictionary class]]) return;

    NSString *subjectURI = subject[@"uri"];
    if (!subjectURI) return;

    NSString *targetDID = [self extractDIDFromATURI:subjectURI];
    if (!targetDID || [targetDID isEqualToString:did]) return; 

    [self.notificationService createNotificationForActor:targetDID
                                               authorDID:did
                                                   reason:@"like"
                                            reasonSubject:subjectURI
                                               subjectURI:uri
                                               subjectCID:cid
                                                    error:nil];
}

#pragma mark - Follow Notifications

- (void)handleFollow:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid {
    NSString *targetDID = record[@"subject"];
    if (![targetDID isKindOfClass:[NSString class]]) return;
    if ([targetDID isEqualToString:did]) return; 

    [self.notificationService createNotificationForActor:targetDID
                                               authorDID:did
                                                   reason:@"follow"
                                            reasonSubject:nil
                                               subjectURI:uri
                                               subjectCID:cid
                                                    error:nil];
}

#pragma mark - Repost Notifications

- (void)handleRepost:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid {
    NSDictionary *subject = record[@"subject"];
    if (![subject isKindOfClass:[NSDictionary class]]) return;

    NSString *subjectURI = subject[@"uri"];
    if (!subjectURI) return;

    NSString *targetDID = [self extractDIDFromATURI:subjectURI];
    if (!targetDID || [targetDID isEqualToString:did]) return;

    [self.notificationService createNotificationForActor:targetDID
                                               authorDID:did
                                                   reason:@"repost"
                                            reasonSubject:subjectURI
                                               subjectURI:uri
                                               subjectCID:cid
                                                    error:nil];
}

#pragma mark - Post Notifications (replies and mentions)

- (void)handlePost:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid {
    NSDictionary *reply = record[@"reply"];
    if ([reply isKindOfClass:[NSDictionary class]]) {
        NSDictionary *parent = reply[@"parent"];
        if ([parent isKindOfClass:[NSDictionary class]]) {
            NSString *parentURI = parent[@"uri"];
            if (parentURI) {
                NSString *parentDID = [self extractDIDFromATURI:parentURI];
                if (parentDID && ![parentDID isEqualToString:did]) {
                    [self.notificationService createNotificationForActor:parentDID
                                                               authorDID:did
                                                                   reason:@"reply"
                                                            reasonSubject:parentURI
                                                               subjectURI:uri
                                                               subjectCID:cid
                                                                    error:nil];
                }
            }
        }
    }

    NSArray *facets = record[@"facets"];
    if ([facets isKindOfClass:[NSArray class]]) {
        for (NSDictionary *facet in facets) {
            NSArray *features = facet[@"features"];
            if (![features isKindOfClass:[NSArray class]]) continue;

            for (NSDictionary *feature in features) {
                NSString *type = feature[@"$type"];
                if ([type isEqualToString:@"app.bsky.richtext.facet#mention"]) {
                    NSString *mentionDID = feature[@"did"];
                    if (mentionDID && ![mentionDID isEqualToString:did]) {
                        [self.notificationService createNotificationForActor:mentionDID
                                                                   authorDID:did
                                                                       reason:@"mention"
                                                                reasonSubject:nil
                                                                   subjectURI:uri
                                                                   subjectCID:cid
                                                                        error:nil];
                    }
                }
            }
        }
    }

    NSDictionary *embed = record[@"embed"];
    if ([embed isKindOfClass:[NSDictionary class]]) {
        NSString *embedType = embed[@"$type"];
        NSDictionary *quotedRecord = nil;
        if ([embedType isEqualToString:@"app.bsky.embed.record"]) {
            quotedRecord = embed[@"record"];
        } else if ([embedType isEqualToString:@"app.bsky.embed.recordWithMedia"]) {
            quotedRecord = embed[@"record"][@"record"];
        }

        if ([quotedRecord isKindOfClass:[NSDictionary class]]) {
            NSString *quotedURI = quotedRecord[@"uri"];
            if (quotedURI) {
                NSString *quotedDID = [self extractDIDFromATURI:quotedURI];
                if (quotedDID && ![quotedDID isEqualToString:did]) {
                    [self.notificationService createNotificationForActor:quotedDID
                                                               authorDID:did
                                                                   reason:@"quote"
                                                            reasonSubject:quotedURI
                                                               subjectURI:uri
                                                               subjectCID:cid
                                                                    error:nil];
                }
            }
        }
    }
}

#pragma mark - Helpers

- (nullable NSString *)extractDIDFromATURI:(NSString *)atURI {
    if (![atURI hasPrefix:@"at://"]) return nil;
    NSString *path = [atURI substringFromIndex:5]; 
    NSRange slashRange = [path rangeOfString:@"/"];
    if (slashRange.location == NSNotFound) {
        return path; 
    }
    return [path substringToIndex:slashRange.location];
}

@end
