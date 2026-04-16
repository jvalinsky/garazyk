#import "Network/XrpcAppBskyFeedPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/GraphService.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Debug/PDSLogger.h"

@implementation XrpcAppBskyFeedPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(PDSDatabase *)appViewDatabase
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController {

    FeedService *feedService = [[FeedService alloc] initWithDatabase:appViewDatabase];
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
    GraphService *graphService = [[GraphService alloc] initWithDatabase:appViewDatabase];

    // app.bsky.feed.getAuthorFeed
    [dispatcher registerAppBskyFeedGetAuthorFeed:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *limitParam = request.queryParams[@"limit"];
        if (limitParam && limitParam.length > 0) {
            NSScanner *scanner = [NSScanner scannerWithString:limitParam];
            NSInteger parsed = 0;
            if ([scanner scanInteger:&parsed] && scanner.isAtEnd) {
                limit = parsed;
            }
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *filter = [request queryParamForKey:@"filter"];
        NSError *error = nil;
        NSDictionary *result = [feedService getAuthorFeedForActor:actor limit:limit cursor:cursor filter:filter error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getTimeline
    [dispatcher registerAppBskyFeedGetTimeline:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required for timeline"];
            return;
        }
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) return;
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [feedService getTimelineForActor:actorDID limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getActorLikes
    [dispatcher registerAppBskyFeedGetActorLikes:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [feedService getActorLikes:actor limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getPostThread
    [dispatcher registerAppBskyFeedGetPostThread:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }
        NSInteger depth = 6;
        NSString *depthParam = [request queryParamForKey:@"depth"];
        if (depthParam) {
            NSScanner *scanner = [NSScanner scannerWithString:depthParam];
            NSInteger parsed = 0;
            if ([scanner scanInteger:&parsed] && scanner.isAtEnd) {
                depth = parsed;
            }
        }
        NSError *error = nil;
        NSDictionary *result = [feedService getPostThread:uri depth:depth error:&error];
        if (error) {
            [XrpcErrorHelper setNotFoundError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getFeed
    [dispatcher registerAppBskyFeedGetFeed:^(HttpRequest *request, HttpResponse *response) {
        NSString *feed = [request queryParamForKey:@"feed"];
        if (!feed) {
            [XrpcErrorHelper setValidationError:response message:@"Missing feed parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [feedService getFeed:feed limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getPosts
    [dispatcher registerAppBskyFeedGetPosts:^(HttpRequest *request, HttpResponse *response) {
        id urisParam = request.queryParams[@"uris"];
        NSArray<NSString *> *uris = nil;
        if ([urisParam isKindOfClass:[NSArray class]]) {
            uris = urisParam;
        } else if ([urisParam isKindOfClass:[NSString class]]) {
            uris = @[urisParam];
        } else {
            [XrpcErrorHelper setValidationError:response message:@"Missing uris parameter"];
            return;
        }
        NSError *error = nil;
        NSDictionary *result = [feedService getPosts:uris error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getFeedGenerators
    [dispatcher registerAppBskyFeedGetFeedGenerators:^(HttpRequest *request, HttpResponse *response) {
        id feedsParam = request.queryParams[@"feeds"];
        NSArray<NSString *> *feedURIs = nil;
        if ([feedsParam isKindOfClass:[NSArray class]]) {
            feedURIs = (NSArray<NSString *> *)feedsParam;
        } else if ([feedsParam isKindOfClass:[NSString class]]) {
            feedURIs = @[(NSString *)feedsParam];
        } else {
            [XrpcErrorHelper setValidationError:response message:@"Missing feeds parameter"];
            return;
        }
        NSMutableArray<NSDictionary *> *feeds = [NSMutableArray arrayWithCapacity:feedURIs.count];
        for (NSString *feedURI in feedURIs) {
            [feeds addObject:@{@"uri": feedURI, @"did": @"", @"creator": @{@"did": @"", @"handle": @"", @"displayName": @""}}];
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"feeds": feeds}];
    }];

    // app.bsky.feed.getSuggestedFeeds - Get suggested feeds
    [dispatcher registerMethod:@"app.bsky.feed.getSuggestedFeeds" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"feeds": @[]}];
    }];

    // app.bsky.feed.getLikes - Get likes for a post
    [dispatcher registerMethod:@"app.bsky.feed.getLikes" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [graphService getLikesForURI:uri limit:limit cursor:cursor error:&error];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"uri": uri, @"likes": @[]}];
    }];

    // app.bsky.feed.getRepostedBy - Get actors who reposted
    [dispatcher registerMethod:@"app.bsky.feed.getRepostedBy" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [graphService getRepostedByForURI:uri limit:limit cursor:cursor error:&error];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"uri": uri, @"repostedBy": @[]}];
    }];

    // app.bsky.feed.getActorFeeds - Get feed generators created by an actor
    [dispatcher registerMethod:@"app.bsky.feed.getActorFeeds" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
        if (cursor) {
            query = [query stringByAppendingString:@" AND rkey < ?"];
        }
        query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];

        NSMutableArray *args = [NSMutableArray arrayWithObjects:actor, @"app.bsky.feed.generator", nil];
        if (cursor) [args addObject:cursor];
        [args addObject:@(limit)];

        NSError *error = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:args error:&error];
        NSMutableArray *feeds = [NSMutableArray array];

        for (NSDictionary *row in rows) {
            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:actor error:nil];
            if (!block || !block.blockData) continue;
            NSDictionary *record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            if (!record) continue;

            NSString *rkey = row[@"rkey"];
            NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.generator/%@", actor, rkey];
            NSDictionary *generatorView = @{
                @"uri": uri,
                @"cid": cidStr ?: @"",
                @"did": actor,
                @"creator": [actorService getProfileForActor:actor error:nil] ?: @{@"did": actor},
                @"displayName": record[@"displayName"] ?: @"",
                @"description": record[@"description"] ?: @"",
                @"avatar": record[@"avatar"] ?: [NSNull null],
                @"likeCount": @0,
                @"indexedAt": record[@"createdAt"] ?: @"",
                @"labels": @[],
                @"viewer": @{}
            };
            [feeds addObject:generatorView];
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"feeds"] = feeds;
        if (feeds.count >= (NSUInteger)limit && rows.count > 0) {
            result[@"cursor"] = [rows lastObject][@"rkey"];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getFeedGenerator - Get a single feed generator by URI
    [dispatcher registerMethod:@"app.bsky.feed.getFeedGenerator" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *feed = [request queryParamForKey:@"feed"];
        if (!feed) {
            [XrpcErrorHelper setValidationError:response message:@"Missing feed parameter"];
            return;
        }

        NSArray *components = [feed componentsSeparatedByString:@"/"];
        if (components.count < 5) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid feed URI"];
            return;
        }
        NSString *did = components[2];
        NSString *rkey = components[4];

        NSString *query = @"SELECT cid FROM records WHERE did = ? AND collection = ? AND rkey = ? LIMIT 1";
        NSError *error = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:@[did, @"app.bsky.feed.generator", rkey] error:&error];

        if (rows.count == 0) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Feed generator not found"}];
            return;
        }

        NSString *cidStr = rows[0][@"cid"];
        CID *cid = [CID cidFromString:cidStr];
        NSDictionary *record = nil;
        if (cid) {
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:did error:nil];
            if (block && block.blockData) {
                record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            }
        }

        NSDictionary *generatorView = @{
            @"uri": feed,
            @"cid": cidStr ?: @"",
            @"did": did,
            @"creator": [actorService getProfileForActor:did error:nil] ?: @{@"did": did},
            @"displayName": record[@"displayName"] ?: @"",
            @"description": record[@"description"] ?: @"",
            @"likeCount": @0,
            @"indexedAt": record[@"createdAt"] ?: @"",
            @"labels": @[],
            @"viewer": @{}
        };

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"view": generatorView, @"isOnline": @YES, @"isValid": @YES}];
    }];

    // app.bsky.feed.searchPosts - Search posts by text
    [dispatcher registerMethod:@"app.bsky.feed.searchPosts" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *q = [request queryParamForKey:@"q"];
        if (!q || q.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing q parameter"];
            return;
        }

        NSInteger limit = 25;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSString *query = @"SELECT did, rkey, cid FROM records WHERE collection = ? ORDER BY rkey DESC LIMIT ?";
        NSError *error = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:@[@"app.bsky.feed.post", @(limit * 5)] error:&error];

        NSMutableArray *posts = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            if ((NSInteger)posts.count >= limit) break;

            NSString *postDID = row[@"did"];
            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:postDID error:nil];
            if (!block || !block.blockData) continue;
            NSDictionary *record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            if (!record) continue;

            NSString *text = record[@"text"] ?: @"";
            if ([text rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound) {
                NSString *rkey = row[@"rkey"];
                NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", postDID, rkey];
                NSDictionary *postView = @{
                    @"uri": uri,
                    @"cid": cidStr ?: @"",
                    @"author": [actorService getProfileForActor:postDID error:nil] ?: @{@"did": postDID},
                    @"record": record,
                    @"replyCount": @0,
                    @"repostCount": @0,
                    @"likeCount": @0,
                    @"quoteCount": @0,
                    @"indexedAt": record[@"createdAt"] ?: @"",
                    @"viewer": @{},
                    @"labels": @[]
                };
                [posts addObject:postView];
            }
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"posts"] = posts;
        result[@"hitsTotal"] = @(posts.count);

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getQuotes - Get posts that quote a given post
    [dispatcher registerMethod:@"app.bsky.feed.getQuotes" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }

        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSString *query = @"SELECT did, rkey, cid FROM records WHERE collection = ? ORDER BY rkey DESC LIMIT ?";
        NSError *error = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:@[@"app.bsky.feed.post", @(limit * 5)] error:&error];

        NSMutableArray *posts = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            if ((NSInteger)posts.count >= limit) break;

            NSString *postDID = row[@"did"];
            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:postDID error:nil];
            if (!block || !block.blockData) continue;
            NSDictionary *record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            if (!record) continue;

            NSDictionary *embed = record[@"embed"];
            if (!embed) continue;

            NSString *embedType = embed[@"$type"];
            BOOL isQuote = NO;

            if ([embedType isEqualToString:@"app.bsky.embed.record"]) {
                NSDictionary *embedRecord = embed[@"record"];
                if ([embedRecord[@"uri"] isEqualToString:uri]) {
                    isQuote = YES;
                }
            } else if ([embedType isEqualToString:@"app.bsky.embed.recordWithMedia"]) {
                NSDictionary *embedRecord = embed[@"record"][@"record"];
                if ([embedRecord[@"uri"] isEqualToString:uri]) {
                    isQuote = YES;
                }
            }

            if (isQuote) {
                NSString *rkey = row[@"rkey"];
                NSString *postURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", postDID, rkey];
                NSDictionary *postView = @{
                    @"uri": postURI,
                    @"cid": cidStr ?: @"",
                    @"author": [actorService getProfileForActor:postDID error:nil] ?: @{@"did": postDID},
                    @"record": record,
                    @"replyCount": @0,
                    @"repostCount": @0,
                    @"likeCount": @0,
                    @"quoteCount": @0,
                    @"indexedAt": record[@"createdAt"] ?: @"",
                    @"viewer": @{},
                    @"labels": @[]
                };
                [posts addObject:postView];
            }
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"uri"] = uri;
        result[@"posts"] = posts;

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.describeFeedGenerator - Describe this server's feed generator
    [dispatcher registerMethod:@"app.bsky.feed.describeFeedGenerator" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"did": @"",
            @"feeds": @[],
            @"links": @{}
        }];
    }];

    // app.bsky.feed.getFeedSkeleton - Get skeleton of a feed from a feed generator
    [dispatcher registerMethod:@"app.bsky.feed.getFeedSkeleton" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *feed = [request queryParamForKey:@"feed"];
        if (!feed || feed.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing feed parameter"];
            return;
        }

        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }

        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSArray *feedComponents = [feed componentsSeparatedByString:@"/"];
        if (feedComponents.count < 5) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"UnknownFeed", @"message": @"Unknown feed"}];
            return;
        }
        NSString *feedDid = feedComponents[2];
        NSString *feedCollection = feedComponents[3];

        if (![feedCollection isEqualToString:@"app.bsky.feed.generator"]) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"UnknownFeed", @"message": @"Unknown feed"}];
            return;
        }

        NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
        NSMutableArray *args = [NSMutableArray arrayWithObjects:feedDid, @"app.bsky.feed.post", nil];
        if (cursor.length > 0) {
            query = [query stringByAppendingString:@" AND rkey < ?"];
            [args addObject:cursor];
        }
        query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];
        [args addObject:@(limit)];

        NSError *queryError = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:args error:&queryError];
        if (!rows) {
            [XrpcErrorHelper setInternalServerError:response message:queryError.localizedDescription ?: @"Failed to query feed"];
            return;
        }

        NSMutableArray *skeletonFeed = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            NSString *postRkey = row[@"rkey"];
            NSString *postURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", feedDid, postRkey ?: @""];
            [skeletonFeed addObject:@{@"post": postURI}];
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:skeletonFeed forKey:@"feed"];
        if (rows.count >= (NSUInteger)limit && rows.lastObject[@"rkey"]) {
            result[@"cursor"] = rows.lastObject[@"rkey"];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.sendInteractions - Log feed interactions
    [dispatcher registerMethod:@"app.bsky.feed.sendInteractions" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.feed.getListFeed - Get feed from a list
    [dispatcher registerMethod:@"app.bsky.feed.getListFeed" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *list = [request queryParamForKey:@"list"];
        if (!list) {
            [XrpcErrorHelper setValidationError:response message:@"Missing list parameter"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"feed": @[]}];
    }];

    PDS_LOG_INFO(@"Registered app.bsky.feed.* endpoints");
}

@end
