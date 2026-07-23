// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/ActorService.h"

@implementation AppViewXRpcRoutePack (Actor)

- (void)handleGetProfile:(HttpRequest *)request response:(HttpResponse *)response
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

    NSError *error = nil;
    NSDictionary *profile = [self.actorService getProfileForActor:actor error:&error];

    if (error || !profile)
    {
        response.statusCode = 404;
        [response setJsonBody:@{
            @"error": @"ActorNotFound",
            @"message": [NSString stringWithFormat:@"Actor not found: %@", actor]
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:profile];
}

- (void)handleGetProfiles:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorsParam = [request queryParamForKey:@"actors"];
    if (!actorsParam || actorsParam.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"actors parameter is required"
        }];
        return;
    }

    NSArray<NSString *> *actorDIDs = [actorsParam componentsSeparatedByString:@","];
    NSError *error = nil;
    NSArray *profiles = [self.actorService getProfilesForActors:actorDIDs error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get profiles"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"profiles": profiles ?: @[] }];
}

- (void)handleSearchActors:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *term = [request queryParamForKey:@"q"] ?: [request queryParamForKey:@"term"] ?: @"";
    NSInteger limit = parseLimitParam(request, 25, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [self.actorService searchActors:term limit:limit cursor:cursor error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Search failed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"actors": @[] }];
}

- (void)handleSearchActorsTypeahead:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *term = [request queryParamForKey:@"q"] ?: [request queryParamForKey:@"term"] ?: @"";
    NSInteger limit = parseLimitParam(request, 20, 100);

    NSError *error = nil;
    NSArray *actors = [self.actorService searchActorsTypeahead:term limit:limit error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Search failed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"actors": actors ?: @[] }];
}

- (void)handleGetPreferences:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    NSDictionary *prefs = [self.actorService getPreferencesForActor:actorDID error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get preferences"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:prefs ?: @{ @"preferences": @[] }];
}

- (void)handlePutPreferences:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Request body required"
        }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
    if (!body)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Invalid JSON body"
        }];
        return;
    }

    NSArray *preferences = body[@"preferences"];
    if (!preferences)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"preferences field required"
        }];
        return;
    }

    NSError *error = nil;
    BOOL success = [self.actorService putPreferencesForActor:actorDID preferences:preferences error:&error];

    if (!success)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to update preferences"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleGetSuggestions:(HttpRequest *)request response:(HttpResponse *)response
{
    response.statusCode = 200;
    [response setJsonBody:@{ @"actors": @[] }];
}

@end