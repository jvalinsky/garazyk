/*!
 @file AppViewGraphIndexer.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Indexers/AppViewGraphIndexer.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "AppView/Server/Relevance/AppViewRelevanceSet.h"
#import "Debug/PDSLogger.h"

#import "AppView/Services/GraphService.h"

static NSSet<NSString *> *graphCollections(void) {
    static NSSet *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [NSSet setWithArray:@[
            @"app.bsky.graph.follow",
            @"app.bsky.graph.block",
            @"app.bsky.graph.list",
            @"app.bsky.graph.listitem",
            @"app.bsky.graph.listblock",
            @"app.bsky.graph.starterpack",
        ]];
    });
    return s;
}

@interface AppViewGraphIndexer ()
@property (nonatomic, strong) AppViewDatabase *avdb;
@property (nonatomic, weak)   AppViewRelevanceSet *relevanceSet;
@property (nonatomic, strong) GraphService *graphService;
@end

@implementation AppViewGraphIndexer

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                    relevanceSet:(nullable AppViewRelevanceSet *)relevanceSet
                    graphService:(nullable GraphService *)graphService {
    self = [super init];
    if (!self) return nil;
    _avdb        = database;
    _relevanceSet = relevanceSet;
    _graphService = graphService;
    return self;
}

- (BOOL)canIndexCollection:(NSString *)collection {
    return [graphCollections() containsObject:collection];
}

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
               rkey:(NSString *)rkey
                cid:(nullable NSString *)cid
              error:(NSError **)error {
    // Follow: validate subject
    if ([collection isEqualToString:@"app.bsky.graph.follow"]) {
        NSString *subjectDID = record[@"subject"];
        if (!subjectDID) {
            if (error) *error = [NSError errorWithDomain:@"AppViewGraphIndexer"
                                                    code:1
                                                userInfo:@{NSLocalizedDescriptionKey: @"Follow missing subject"}];
            return NO;
        }

        // If the follower is in the relevance set, add the subject as follow-of-seed
        if ([_avdb isDIDRelevant:did]) {
            [_relevanceSet addDID:subjectDID reason:AppViewRelevanceReasonFollowOfSeed];
        }
    }
    
    if ([collection isEqualToString:@"app.bsky.graph.starterpack"]) {
        [_graphService indexStarterPack:record did:did rkey:rkey cid:cid error:error];
    }

    PDS_LOG_DEBUG(@"[AppViewGraphIndexer] Indexed %@ for %@", collection, did);
    return YES;
}

- (BOOL)handleIngestEvent:(AppViewIngestEvent *)event error:(NSError **)error {
    for (NSDictionary *op in event.ops) {
        NSString *action = op[@"action"];
        NSString *path   = op[@"path"];

        NSRange slash = [path rangeOfString:@"/"];
        NSString *collection = (slash.location != NSNotFound)
            ? [path substringToIndex:slash.location] : path;
        NSString *rkey = (slash.location != NSNotFound)
            ? [path substringFromIndex:slash.location + 1] : @"";

        if (![self canIndexCollection:collection]) continue;

        if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
            NSDictionary *record = op[@"record"];
            NSString *cid = op[@"cid"];
            if (record) [self indexRecord:record did:event.did collection:collection rkey:rkey cid:cid error:nil];
        } else if ([action isEqualToString:@"delete"]) {
            [self deleteRecord:rkey did:event.did collection:collection error:nil];
        }
    }
    return YES;
}

- (BOOL)processPendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error {
    PDS_LOG_DEBUG(@"[AppViewGraphIndexer] Replaying pending delta for %@", delta.did);
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error {
    PDS_LOG_DEBUG(@"[AppViewGraphIndexer] Delete %@/%@ for %@", collection, rkey, did);
    return YES;
}

@end
