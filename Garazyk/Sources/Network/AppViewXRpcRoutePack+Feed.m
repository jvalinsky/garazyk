// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/GraphService.h"

@implementation AppViewXRpcRoutePack (Feed)

- (void)handleGetTimeline:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSString *algorithm = [request queryParamForKey:@"algorithm"];

    NSError *error = nil;
    NSDictionary *result = [self.feedService getTimelineForActor:actorDID limit:limit cursor:cursor error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get timeline"
        }];
        return;
    }

    (void)algorithm;
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetAuthorFeed:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"actor parameter is required"
        }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSString *filter = [request queryParamForKey:@"filter"];

    NSError *error = nil;
    NSDictionary *result = [self.feedService getAuthorFeedForActor:actor limit:limit cursor:cursor filter:filter error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get author feed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetPostThread:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *uri = [request queryParamForKey:@"uri"];
    if (!uri || uri.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"uri parameter is required"
        }];
        return;
    }

    NSString *depthParam = [request queryParamForKey:@"depth"];
    NSInteger depth = 10;
    if (depthParam.length > 0)
    {
        [[NSScanner scannerWithString:depthParam] scanInteger:&depth];
    }
    depth = MIN(MAX(depth, 0), 100);

    NSError *error = nil;
    NSDictionary *result = [self.feedService getPostThread:uri depth:depth error:&error];

    if (error)
    {
        response.statusCode = 404;
        [response setJsonBody:@{
            @"error": @"NotFound",
            @"message": error.localizedDescription ?: @"Post thread not found"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetFeed:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *feedURI = [request queryParamForKey:@"feed"];
    if (!feedURI || feedURI.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"feed parameter is required"
        }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [self.feedService getFeed:feedURI limit:limit cursor:cursor error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get feed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetActorLikes:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"actor parameter is required"
        }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [self.feedService getActorLikes:actor limit:limit cursor:cursor error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get actor likes"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetPosts:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *urisParam = [request queryParamForKey:@"uris"];
    if (!urisParam || urisParam.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"uris parameter is required"
        }];
        return;
    }

    NSArray<NSString *> *uris = [urisParam componentsSeparatedByString:@","];
    NSError *error = nil;
    NSDictionary *result = [self.feedService getPosts:uris error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get posts"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"posts": @[] }];
}

- (void)handleGetFeedGenerators:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *urisParam = [request queryParamForKey:@"uris"];
    if (!urisParam || urisParam.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"uris parameter is required"
        }];
        return;
    }

    NSArray<NSString *> *uris = [urisParam componentsSeparatedByString:@","];
    NSError *error = nil;
    NSDictionary *result = [self.feedService getFeedGenerators:uris error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get feed generators"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"feeds": @[] }];
}

- (void)handleGetLikes:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *uri = [request queryParamForKey:@"uri"];
    if (!uri || uri.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"uri parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [self.graphService getLikesForURI:uri limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetRepostedBy:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *uri = [request queryParamForKey:@"uri"];
    if (!uri || uri.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"uri parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [self.graphService getRepostedByForURI:uri limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

@end