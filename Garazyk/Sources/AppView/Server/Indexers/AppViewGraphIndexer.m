// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewGraphIndexer.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Indexers/AppViewGraphIndexer.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "AppView/Server/Relevance/AppViewRelevanceSet.h"
#import "Debug/GZLogger.h"

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
@property (nonatomic, strong) PDSGraphService *graphService;
@end

@implementation AppViewGraphIndexer

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                    relevanceSet:(nullable AppViewRelevanceSet *)relevanceSet
                    graphService:(nullable PDSGraphService *)graphService {
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
    
    // list and listitem are addressed by rkey; a nil one formats as "(null)" and
    // an empty one leaves an empty last segment, either of which stores a URI
    // that no deleteRecord: call can ever match. follow and block ignore rkey.
    BOOL addressedByRkey = [collection isEqualToString:@"app.bsky.graph.list"] ||
                           [collection isEqualToString:@"app.bsky.graph.listitem"];
    if (addressedByRkey && rkey.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"AppViewGraphIndexer"
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"Missing rkey for rkey-addressed graph record"}];
        return NO;
    }

    if ([collection isEqualToString:@"app.bsky.graph.list"]) {
        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        return [_graphService indexList:record did:did uri:uri cid:cid error:error];
    }

    if ([collection isEqualToString:@"app.bsky.graph.listitem"]) {
        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        return [_graphService indexListitem:record did:did uri:uri cid:cid error:error];
    }

    if ([collection isEqualToString:@"app.bsky.graph.starterpack"]) {
        return [_graphService indexStarterPack:record did:did rkey:rkey cid:cid error:error];
    }

    GZ_LOG_DEBUG(@"[AppViewGraphIndexer] Indexed %@ for %@", collection, did);
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
    GZ_LOG_DEBUG(@"[AppViewGraphIndexer] Replaying pending delta for %@", delta.did);
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error {
    GZ_LOG_DEBUG(@"[AppViewGraphIndexer] Delete %@/%@ for %@", collection, rkey, did);
    // Mirrors the guard in indexRecord:; without it the URI below cannot address
    // any stored row, so the DELETE would silently match nothing.
    if (rkey.length == 0 &&
        ([collection isEqualToString:@"app.bsky.graph.list"] ||
         [collection isEqualToString:@"app.bsky.graph.listitem"])) {
        if (error) *error = [NSError errorWithDomain:@"AppViewGraphIndexer"
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"Missing rkey for rkey-addressed graph record"}];
        return NO;
    }
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

    if ([collection isEqualToString:@"app.bsky.graph.list"]) {
        return [_graphService unindexListWithURI:uri error:error];
    }
    if ([collection isEqualToString:@"app.bsky.graph.listitem"]) {
        return [_graphService unindexListitemWithURI:uri error:error];
    }
    // Other graph collections (follow, block, etc.) handled elsewhere
    return YES;
}

@end
