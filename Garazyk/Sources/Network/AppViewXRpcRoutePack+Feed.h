// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@interface AppViewXRpcRoutePack (Feed)

- (void)handleGetTimeline:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetAuthorFeed:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetPostThread:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetFeed:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetActorLikes:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetPosts:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetFeedGenerators:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetLikes:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetRepostedBy:(HttpRequest *)request response:(HttpResponse *)response;

@end