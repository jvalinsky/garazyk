/*!
 @file RecordLifecycleHandler.m

 @abstract Record lifecycle handler implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/RecordLifecycleHandler.h"
#import "AppView/NotificationService.h"
#import "App/Services/PDSRecordService.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Debug/PDSLogger.h"

@interface RecordLifecycleHandler ()
@property (nonatomic, strong) NotificationService *notificationService;
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation RecordLifecycleHandler

- (instancetype)initWithNotificationService:(NotificationService *)notificationService
                                   database:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _notificationService = notificationService;
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
    NSString *cid = [info[@"cid"] isKindOfClass:[NSNull class]] ? nil : info[@"cid"];
    NSData *recordCBOR = [info[@"recordCBOR"] isKindOfClass:[NSNull class]] ? nil : info[@"recordCBOR"];

    if (!did || !collection || !rkey || !action) return;

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

    if ([action isEqualToString:@"delete"]) {
        // When a record is deleted, remove associated notifications
        [self.notificationService deleteNotificationsForSubjectURI:uri error:nil];
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
    }
}

#pragma mark - Like Notifications

- (void)handleLike:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid {
    // record.subject = { uri: "at://targetDID/...", cid: "..." }
    NSDictionary *subject = record[@"subject"];
    if (![subject isKindOfClass:[NSDictionary class]]) return;

    NSString *subjectURI = subject[@"uri"];
    if (!subjectURI) return;

    // Extract the target actor DID from the subject URI (at://did/collection/rkey)
    NSString *targetDID = [self extractDIDFromATURI:subjectURI];
    if (!targetDID || [targetDID isEqualToString:did]) return; // Don't notify self-likes

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
    // record.subject = "did:plc:..." (the followed user)
    NSString *targetDID = record[@"subject"];
    if (![targetDID isKindOfClass:[NSString class]]) return;
    if ([targetDID isEqualToString:did]) return; // Don't notify self-follows

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
    // Check for reply — notify the parent post author
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

    // Check for mentions in facets
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

    // Check for quote embeds — notify the quoted post author
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
    // AT URI format: at://did/collection/rkey
    if (![atURI hasPrefix:@"at://"]) return nil;

    NSString *path = [atURI substringFromIndex:5]; // skip "at://"
    NSRange slashRange = [path rangeOfString:@"/"];
    if (slashRange.location == NSNotFound) {
        return path; // just the DID
    }
    return [path substringToIndex:slashRange.location];
}

@end
