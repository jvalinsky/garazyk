// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/SearchIndexService.h"

@implementation AppViewXRpcRoutePack (Search)

- (void)handleSearchActorsSkeleton:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *query = [request queryParamForKey:@"q"];
    if (!query) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"q parameter is required" }];
        return;
    }
    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [self.searchIndexService searchActors:query limit:limit cursor:cursor error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleSearchPostsSkeleton:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *query = [request queryParamForKey:@"q"];
    if (!query) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"q parameter is required" }];
        return;
    }
    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [self.searchIndexService searchPosts:query limit:limit cursor:cursor error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleSearchStarterPacksSkeleton:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *query = [request queryParamForKey:@"q"];
    if (!query) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"q parameter is required" }];
        return;
    }
    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [self.searchIndexService searchStarterPacks:query limit:limit cursor:cursor error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

@end