// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/GraphService.h"

@implementation AppViewXRpcRoutePack (Graph)

- (void)handleGetFollows:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [self.graphService getFollowsForActor:actor limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetFollowers:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [self.graphService getFollowersForActor:actor limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetBlocks:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [self.graphService getBlocksForActor:actorDID limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetMutes:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [self.graphService getMutesForActor:actorDID limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetRelationships:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [request queryParamForKey:@"actor"];
    if (!actorDID || ![actorDID isKindOfClass:[NSString class]] || actorDID.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor parameter is required" }];
        return;
    }

    id targetObj = [request queryParamForKey:@"others"] ?: [request queryParamForKey:@"subjects"] ?: [request queryParamForKey:@"target"];
    if (!targetObj)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"others parameter is required" }];
        return;
    }

    NSArray *others = [targetObj isKindOfClass:[NSArray class]] ? (NSArray *)targetObj : @[targetObj];
    NSString *primaryTarget = others.firstObject;

    NSError *error = nil;
    NSDictionary *result = [self.graphService getRelationship:actorDID withActor:primaryTarget error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{ @"relationships": result ? @[result] : @[] }];
}

- (void)handleGetStarterPack:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *uri = [request queryParamForKey:@"uri"];
    if (!uri || uri.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"uri parameter is required" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *result = [self.graphService getStarterPack:uri error:&error];
    if (error || !result) { response.statusCode = 404; [response setJsonBody:@{ @"error": @"NotFound", @"message": @"Starter pack not found" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{ @"starterPack": result }];
}

- (void)handleGetStarterPacks:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [self.graphService getStarterPacksForActor:actor limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"starterPacks": @[] }];
}

- (void)handleGetLists:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [self.graphService getListsForActor:actor limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"lists": @[] }];
}

- (void)handleGetList:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *list = [request queryParamForKey:@"list"];
    if (!list || list.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"list parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [self.graphService getList:list limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    if (!result) { response.statusCode = 404; [response setJsonBody:@{ @"error": @"NotFound", @"message": @"List not found" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result];
}

- (void)handleMuteActor:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Request body required" }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
    NSString *targetDID = body[@"actor"];
    if (!targetDID || targetDID.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor field required in body" }];
        return;
    }

    NSError *error = nil;
    BOOL success = [self.graphService muteActor:targetDID forActor:actorDID error:&error];
    if (!success) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleUnmuteActor:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Request body required" }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
    NSString *targetDID = body[@"actor"];
    if (!targetDID || targetDID.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor field required in body" }];
        return;
    }

    NSError *error = nil;
    BOOL success = [self.graphService unmuteActor:targetDID forActor:actorDID error:&error];
    if (!success) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleGetStarterPacksBulk:(HttpRequest *)request response:(HttpResponse *)response
{
    id urisParam = [request queryParamForKey:@"uris"];
    NSArray *uris = [urisParam isKindOfClass:[NSArray class]] ? (NSArray *)urisParam : (urisParam ? @[urisParam] : @[]);

    NSError *error = nil;
    NSArray *packs = [self.graphService getStarterPacks:uris error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{ @"starterPacks": packs ?: @[] }];
}

@end