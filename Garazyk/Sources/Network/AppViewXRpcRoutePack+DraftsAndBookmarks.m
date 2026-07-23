// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/DraftService.h"
#import "AppView/Services/BookmarkService.h"

@implementation AppViewXRpcRoutePack (DraftsAndBookmarks)

- (void)handleGetDrafts:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    NSArray *drafts = [self.draftService getDraftsForDID:actorDID error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{ @"drafts": drafts ?: @[] }];
}

- (void)handleGetBookmarks:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [self.bookmarkService getBookmarksForActor:actorDID limit:limit cursor:cursor error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

@end