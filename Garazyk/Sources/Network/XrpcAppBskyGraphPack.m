// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcAppBskyGraphPack.h"
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/ActorService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Debug/GZLogger.h"
#import "Services/PDS/PDSRecordService.h"

@implementation XrpcAppBskyGraphPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky.graph";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {

    GraphService *graphService = [[GraphService alloc] initWithDatabase:services.appViewDatabase];
    ActorService *actorService = [[ActorService alloc] initWithDatabase:services.appViewDatabase];

    // app.bsky.graph.getMutes - Get muted actors
    [dispatcher registerAppBskyGraphGetMutes:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [graphService getMutesForActor:actorDID limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to load mutes"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"mutes": @[]}];
    }];

    // app.bsky.graph.getBlocks - Get blocked actors
    [dispatcher registerAppBskyGraphGetBlocks:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [graphService getBlocksForActor:actorDID limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"blocks": @[]}];
    }];

    // app.bsky.graph.getListMutes - Get muted lists
    [dispatcher registerMethod:@"app.bsky.graph.getListMutes" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];

        // Load muted lists from preferences
        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }
        NSMutableArray<NSDictionary *> *prefsList = XrpcMutablePreferenceEntries(currentPrefs);
        NSUInteger existingIndex = NSNotFound;
        NSMutableDictionary *muteState = XrpcGraphMuteStateFromPreferences(prefsList, &existingIndex);
        NSArray<NSString *> *mutedListURIs = XrpcNormalizedUniqueStringArray(muteState[@"mutedLists"]);

        // Resolve list URIs to list views
        NSMutableArray *lists = [NSMutableArray array];
        NSInteger offset = cursor ? [cursor integerValue] : 0;
        NSInteger count = 0;
        for (NSInteger i = offset; i < (NSInteger)mutedListURIs.count && count < limit; i++) {
            NSString *listURI = mutedListURIs[i];
            NSDictionary *listView = XrpcLoadListViewForURI(services.appViewDatabase, actorService, listURI);
            if (listView) {
                [lists addObject:listView];
                count++;
            }
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"lists"] = [lists copy];
        if (offset + limit < (NSInteger)mutedListURIs.count) {
            result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)(offset + limit)];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getListBlocks - Get blocked lists
    [dispatcher registerMethod:@"app.bsky.graph.getListBlocks" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;

        // Query listblock records for this actor
        NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
        if (cursor) {
            query = [query stringByAppendingString:@" AND rkey < ?"];
        }
        query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];

        NSMutableArray *args = [NSMutableArray arrayWithObjects:actorDID, @"app.bsky.graph.listblock", nil];
        if (cursor) {
            [args addObject:cursor];
        }
        [args addObject:@(limit)];

        NSArray *rows = [services.appViewDatabase executeParameterizedQuery:query params:args error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        NSMutableArray *lists = [NSMutableArray array];
        NSString *lastRkey = nil;
        for (NSDictionary *row in rows) {
            NSString *rkey = row[@"rkey"];
            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;

            PDSDatabaseBlock *block = [services.appViewDatabase getBlockWithCid:cid.bytes repoDid:actorDID error:nil];
            if (!block.blockData) continue;

            NSDictionary *blockRecord = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            if (![blockRecord isKindOfClass:[NSDictionary class]]) continue;

            NSString *listURI = blockRecord[@"list"];
            if (![listURI isKindOfClass:[NSString class]]) continue;

            NSDictionary *listView = XrpcLoadListViewForURI(services.appViewDatabase, actorService, listURI);
            if (listView) {
                [lists addObject:listView];
            }
            lastRkey = rkey;
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"lists"] = [lists copy];
        if (lastRkey && (NSInteger)rows.count >= limit) {
            result[@"cursor"] = lastRkey;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getFollowers - Get followers list
    [dispatcher registerMethod:@"app.bsky.graph.getFollowers" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [graphService getFollowersForActor:actor limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"subject": @{@"did": actor}, @"followers": @[]}];
    }];

    // app.bsky.graph.getFollows - Get follows list
    [dispatcher registerMethod:@"app.bsky.graph.getFollows" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [graphService getFollowsForActor:actor limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"subject": @{@"did": actor}, @"follows": @[]}];
    }];

    // app.bsky.graph.muteActor - Mute an actor
    [dispatcher registerMethod:@"app.bsky.graph.muteActor" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) return;
        NSDictionary *body = request.jsonBody;
        NSString *targetDID = body[@"actor"];
        if (!targetDID) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor in body"];
            return;
        }
        NSError *error = nil;
        BOOL success = [graphService muteActor:targetDID forActor:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.unmuteActor - Unmute an actor
    [dispatcher registerMethod:@"app.bsky.graph.unmuteActor" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) return;
        NSDictionary *body = request.jsonBody;
        NSString *targetDID = body[@"actor"];
        if (!targetDID) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor in body"];
            return;
        }
        NSError *error = nil;
        BOOL success = [graphService unmuteActor:targetDID forActor:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.getRelationships - Get relationships between actors
    [dispatcher registerMethod:@"app.bsky.graph.getRelationships" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        id othersParam = request.queryParams[@"others"];
        NSArray<NSString *> *others = nil;
        if ([othersParam isKindOfClass:[NSArray class]]) {
            others = othersParam;
        } else if ([othersParam isKindOfClass:[NSString class]]) {
            others = @[othersParam];
        }
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *viewerDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];

        NSMutableArray *relationships = [NSMutableArray array];
        for (NSString *otherDID in others) {
            NSError *error = nil;
            NSDictionary *rel = [graphService getRelationship:viewerDID ?: actor withActor:otherDID error:&error];
            if (rel) {
                [relationships addObject:rel];
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"actor": actor, @"relationships": relationships}];
    }];

    // app.bsky.graph.getLists - Get lists created by an actor
    [dispatcher registerMethod:@"app.bsky.graph.getLists" handler:^(HttpRequest *request, HttpResponse *response) {
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
        NSMutableArray *args = [NSMutableArray arrayWithObjects:actor, @"app.bsky.graph.list", nil];
        if (cursor) [args addObject:cursor];
        [args addObject:@(limit)];
        NSError *error = nil;
        NSArray *rows = [services.appViewDatabase executeParameterizedQuery:query params:args error:&error];
        NSMutableArray *lists = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            NSString *rkey = row[@"rkey"];
            NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.list/%@", actor, rkey];
            NSDictionary *listView = XrpcLoadListViewForURI(services.appViewDatabase, actorService, uri);
            if (listView) {
                [lists addObject:listView];
            }
        }
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"lists"] = lists;
        if (lists.count >= (NSUInteger)limit) {
            result[@"cursor"] = [rows lastObject][@"rkey"];
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getList - Get a single list by URI
    [dispatcher registerMethod:@"app.bsky.graph.getList" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *list = [request queryParamForKey:@"list"];
        if (!list) {
            [XrpcErrorHelper setValidationError:response message:@"Missing list parameter"];
            return;
        }
        NSArray *components = [list componentsSeparatedByString:@"/"];
        if (components.count < 5) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid list URI"];
            return;
        }
        NSString *did = components[2];
        NSDictionary *listView = XrpcLoadListViewForURI(services.appViewDatabase, actorService, list);
        if (!listView) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"List not found"}];
            return;
        }
        NSString *itemQuery = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ? ORDER BY rkey DESC LIMIT 100";
        NSArray *itemRows = [services.appViewDatabase executeParameterizedQuery:itemQuery params:@[did, @"app.bsky.graph.listitem"] error:nil];
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *itemRow in itemRows) {
            NSString *itemCidStr = itemRow[@"cid"];
            CID *itemCid = [CID cidFromString:itemCidStr];
            if (!itemCid) continue;
            PDSDatabaseBlock *itemBlock = [services.appViewDatabase getBlockWithCid:itemCid.bytes repoDid:did error:nil];
            if (!itemBlock || !itemBlock.blockData) continue;
            NSDictionary *itemRecord = [ATProtoCBORSerialization JSONObjectWithData:itemBlock.blockData error:nil];
            if (!itemRecord) continue;
            NSString *itemList = itemRecord[@"list"];
            if (![itemList isEqualToString:list]) continue;
            NSString *subjectDID = itemRecord[@"subject"];
            if (subjectDID) {
                NSDictionary *subjectProfile = [actorService getProfileForActor:subjectDID error:nil];
                [items addObject:@{
                    @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.graph.listitem/%@", did, itemRow[@"rkey"]],
                    @"subject": subjectProfile ?: @{@"did": subjectDID, @"handle": @"handle.invalid"}
                }];
            }
        }
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"list"] = listView;
        result[@"items"] = items;
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getKnownFollowers - Get followers known to the viewer
    [dispatcher registerMethod:@"app.bsky.graph.getKnownFollowers" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSDictionary *subject = [actorService getProfileForActor:actor error:nil] ?: @{@"did": actor};
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"subject": subject, @"followers": @[]}];
    }];

    // app.bsky.graph.getSuggestedFollowsByActor - Suggest follows
    [dispatcher registerMethod:@"app.bsky.graph.getSuggestedFollowsByActor" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"suggestions": @[]}];
    }];

    // app.bsky.graph.muteActorList - Mute a list
    [dispatcher registerMethod:@"app.bsky.graph.muteActorList" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSDictionary *body = request.jsonBody;
        NSString *listURI = [body[@"list"] isKindOfClass:[NSString class]] ? body[@"list"] : nil;
        NSString *did = nil, *collection = nil, *rkey = nil;
        if (listURI.length == 0 || !XrpcParseAtURI(listURI, &did, &collection, &rkey) || ![collection isEqualToString:@"app.bsky.graph.list"]) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid list URI"];
            return;
        }
        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }
        NSMutableArray<NSDictionary *> *prefsList = XrpcMutablePreferenceEntries(currentPrefs);
        NSUInteger existingIndex = NSNotFound;
        NSMutableDictionary *muteState = XrpcGraphMuteStateFromPreferences(prefsList, &existingIndex);
        NSMutableArray<NSString *> *mutedLists = XrpcNormalizedUniqueStringArray(muteState[@"mutedLists"]);
        if (![mutedLists containsObject:listURI]) {
            [mutedLists addObject:listURI];
        }
        muteState[@"mutedLists"] = mutedLists;
        NSError *saveError = nil;
        if (!XrpcPersistGraphMuteState(actorService, actorDID, prefsList, muteState, existingIndex, &saveError)) {
            [XrpcErrorHelper setInternalServerError:response message:saveError.localizedDescription ?: @"Failed to persist list mute"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.unmuteActorList - Unmute a list
    [dispatcher registerMethod:@"app.bsky.graph.unmuteActorList" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSDictionary *body = request.jsonBody;
        NSString *listURI = [body[@"list"] isKindOfClass:[NSString class]] ? body[@"list"] : nil;
        NSString *did = nil, *collection = nil, *rkey = nil;
        if (listURI.length == 0 || !XrpcParseAtURI(listURI, &did, &collection, &rkey) || ![collection isEqualToString:@"app.bsky.graph.list"]) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid list URI"];
            return;
        }
        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }
        NSMutableArray<NSDictionary *> *prefsList = XrpcMutablePreferenceEntries(currentPrefs);
        NSUInteger existingIndex = NSNotFound;
        NSMutableDictionary *muteState = XrpcGraphMuteStateFromPreferences(prefsList, &existingIndex);
        NSMutableArray<NSString *> *mutedLists = XrpcNormalizedUniqueStringArray(muteState[@"mutedLists"]);
        [mutedLists removeObject:listURI];
        muteState[@"mutedLists"] = mutedLists;
        NSError *saveError = nil;
        if (!XrpcPersistGraphMuteState(actorService, actorDID, prefsList, muteState, existingIndex, &saveError)) {
            [XrpcErrorHelper setInternalServerError:response message:saveError.localizedDescription ?: @"Failed to persist list mute"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.muteThread - Mute a thread
    [dispatcher registerMethod:@"app.bsky.graph.muteThread" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSDictionary *body = request.jsonBody;
        NSString *rootURI = [body[@"root"] isKindOfClass:[NSString class]] ? body[@"root"] : nil;
        NSString *did = nil, *collection = nil, *rkey = nil;
        if (rootURI.length == 0 || !XrpcParseAtURI(rootURI, &did, &collection, &rkey)) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid root URI"];
            return;
        }
        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }
        NSMutableArray<NSDictionary *> *prefsList = XrpcMutablePreferenceEntries(currentPrefs);
        NSUInteger existingIndex = NSNotFound;
        NSMutableDictionary *muteState = XrpcGraphMuteStateFromPreferences(prefsList, &existingIndex);
        NSMutableArray<NSString *> *mutedThreads = XrpcNormalizedUniqueStringArray(muteState[@"mutedThreads"]);
        if (![mutedThreads containsObject:rootURI]) {
            [mutedThreads addObject:rootURI];
        }
        muteState[@"mutedThreads"] = mutedThreads;
        NSError *saveError = nil;
        if (!XrpcPersistGraphMuteState(actorService, actorDID, prefsList, muteState, existingIndex, &saveError)) {
            [XrpcErrorHelper setInternalServerError:response message:saveError.localizedDescription ?: @"Failed to persist thread mute"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.unmuteThread - Unmute a thread
    [dispatcher registerMethod:@"app.bsky.graph.unmuteThread" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSDictionary *body = request.jsonBody;
        NSString *rootURI = [body[@"root"] isKindOfClass:[NSString class]] ? body[@"root"] : nil;
        NSString *did = nil, *collection = nil, *rkey = nil;
        if (rootURI.length == 0 || !XrpcParseAtURI(rootURI, &did, &collection, &rkey)) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid root URI"];
            return;
        }
        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }
        NSMutableArray<NSDictionary *> *prefsList = XrpcMutablePreferenceEntries(currentPrefs);
        NSUInteger existingIndex = NSNotFound;
        NSMutableDictionary *muteState = XrpcGraphMuteStateFromPreferences(prefsList, &existingIndex);
        NSMutableArray<NSString *> *mutedThreads = XrpcNormalizedUniqueStringArray(muteState[@"mutedThreads"]);
        [mutedThreads removeObject:rootURI];
        muteState[@"mutedThreads"] = mutedThreads;
        NSError *saveError = nil;
        if (!XrpcPersistGraphMuteState(actorService, actorDID, prefsList, muteState, existingIndex, &saveError)) {
            [XrpcErrorHelper setInternalServerError:response message:saveError.localizedDescription ?: @"Failed to persist thread mute"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.searchStarterPacks - Search starter packs
    [dispatcher registerMethod:@"app.bsky.graph.searchStarterPacks" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *q = [request queryParamForKey:@"q"] ?: @"";

        NSInteger limit = 10;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [graphService searchStarterPacks:q limit:limit cursor:nil error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to search starter packs"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"starterPacks": @[]}];
    }];

    // app.bsky.graph.getStarterPack - Get a starter pack
    [dispatcher registerAppBskyGraphGetStarterPack:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }

        NSError *error = nil;
        NSDictionary *starterPack = [graphService getStarterPack:uri error:&error];
        if (!starterPack) {
            [XrpcErrorHelper setNotFoundError:response message:@"Starter pack not found"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:starterPack];
    }];

    // app.bsky.graph.getActorStarterPacks - Get actor's starter packs
    [dispatcher registerAppBskyGraphGetActorStarterPacks:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }

        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];

        // Resolve handle to DID if needed
        NSString *actorDID = actor;
        if (![actor hasPrefix:@"did:"]) {
            NSString *resolved = [actorService resolveHandleToDID:actor error:nil];
            if (resolved) {
                actorDID = resolved;
            }
        }

        NSError *error = nil;
        NSDictionary *result = [graphService getStarterPacksForActor:actorDID limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to load actor starter packs"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"starterPacks": @[]}];
    }];

    // app.bsky.graph.getStarterPacks - Get multiple starter packs
    [dispatcher registerAppBskyGraphGetStarterPacks:^(HttpRequest *request, HttpResponse *response) {
        id urisParam = request.queryParams[@"uris"];
        NSArray *uris = [urisParam isKindOfClass:[NSArray class]] ? urisParam : (urisParam ? @[urisParam] : @[]);

        NSMutableArray *starterPacks = [NSMutableArray arrayWithCapacity:uris.count];
        for (NSString *uri in uris) {
            if (![uri isKindOfClass:[NSString class]]) continue;
            NSDictionary *pack = [graphService getStarterPack:uri error:nil];
            if (pack) {
                [starterPacks addObject:pack];
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"starterPacks": starterPacks}];
    }];

    // app.bsky.graph.getStarterPacksWithMembership - List starter packs and viewer membership
    [dispatcher registerMethod:@"app.bsky.graph.getStarterPacksWithMembership" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *viewerDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                                jwtMinter:services.jwtMinter
                                                        adminController:services.adminController
                                                                request:request
                                                               response:response];
        if (!viewerDid) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        NSString *actor = [request queryParamForKey:@"actor"];
        if (actor.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }

        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }

        NSError *dbError = nil;
        NSArray *rows = [services.appViewDatabase executeParameterizedQuery:
                         @"SELECT uri, did, rkey FROM records "
                         @"WHERE collection = ? ORDER BY rkey DESC LIMIT ?"
                                                      params:@[@"app.bsky.graph.starterpack", @(limit)]
                                                       error:&dbError];
        if (!rows) {
            [XrpcErrorHelper setInternalServerError:response message:dbError.localizedDescription ?: @"Failed to load starter packs"];
            return;
        }

        NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:rows.count];
        for (NSDictionary *row in rows) {
            NSString *uri = [row[@"uri"] isKindOfClass:[NSString class]] ? row[@"uri"] : nil;
            NSString *creatorDid = [row[@"did"] isKindOfClass:[NSString class]] ? row[@"did"] : nil;
            if (uri.length == 0 || creatorDid.length == 0) {
                continue;
            }

            NSDictionary *creatorProfile = [actorService getProfileForActor:creatorDid error:nil];
            if (!creatorProfile) {
                creatorProfile = @{@"did": creatorDid, @"handle": @"handle.invalid"};
            }

            NSDictionary *starterPack = @{
                @"uri": uri,
                @"creator": creatorProfile
            };
            [entries addObject:@{
                @"starterPack": starterPack,
                @"listItem": [NSNull null]
            }];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"starterPacksWithMembership": entries}];
    }];

    // app.bsky.graph.getListMutes - Get muted lists
    [dispatcher registerMethod:@"app.bsky.graph.getListMutes" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }
        NSMutableArray<NSDictionary *> *prefsList = XrpcMutablePreferenceEntries(currentPrefs);
        NSUInteger existingIndex = NSNotFound;
        NSMutableDictionary *muteState = XrpcGraphMuteStateFromPreferences(prefsList, &existingIndex);
        NSArray<NSString *> *mutedLists = muteState[@"mutedLists"] ?: @[];

        // Apply pagination
        NSInteger startIndex = 0;
        if (cursor.length > 0) {
            startIndex = [cursor integerValue];
        }
        NSInteger endIndex = MIN(startIndex + limit, (NSInteger)mutedLists.count);
        NSMutableArray *paginatedMutes = [NSMutableArray array];
        for (NSInteger i = startIndex; i < endIndex; i++) {
            NSString *listURI = mutedLists[i];
            NSDictionary *listView = XrpcLoadListViewForURI(services.appViewDatabase, actorService, listURI);
            if (listView) {
                [paginatedMutes addObject:listView];
            }
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"lists"] = paginatedMutes;
        if (endIndex < (NSInteger)mutedLists.count) {
            result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)endIndex];
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getListBlocks - Get blocked lists
    [dispatcher registerMethod:@"app.bsky.graph.getListBlocks" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
        if (cursor) {
            query = [query stringByAppendingString:@" AND rkey < ?"];
        }
        query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];
        NSMutableArray *args = [NSMutableArray arrayWithObjects:actorDID, @"app.bsky.graph.listblock", nil];
        if (cursor) [args addObject:cursor];
        [args addObject:@(limit + 1)];
        NSError *error = nil;
        NSArray *rows = [services.appViewDatabase executeParameterizedQuery:query params:args error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to load list blocks"];
            return;
        }

        NSMutableArray *blocks = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            NSString *rkeyCurrent = row[@"rkey"];
            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;

            PDSDatabaseBlock *block = [services.appViewDatabase getBlockWithCid:cid.bytes repoDid:actorDID error:nil];
            if (!block || !block.blockData) continue;

            NSDictionary *blockRecord = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            if (!blockRecord) continue;

            NSString *listURI = blockRecord[@"subject"];
            if (listURI && [listURI isKindOfClass:[NSString class]]) {
                NSDictionary *listView = XrpcLoadListViewForURI(services.appViewDatabase, actorService, listURI);
                if (listView) {
                    [blocks addObject:listView];
                }
            }
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"lists"] = blocks;  // Per lexicon spec: output key is "lists" not "blocks"
        if (rows.count > (NSUInteger)limit && blocks.count > 0) {
            result[@"cursor"] = [rows[limit][@"rkey"] isKindOfClass:[NSString class]] ? rows[limit][@"rkey"] : nil;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getListsWithMembership - Get lists containing an actor
    [dispatcher registerMethod:@"app.bsky.graph.getListsWithMembership" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        // Resolve actor if handle
        NSString *targetDID = actor;
        if (![actor hasPrefix:@"did:"]) {
            NSDictionary *actorProfile = [actorService getProfileForActor:actor error:nil];
            if (!actorProfile || !actorProfile[@"did"]) {
                [XrpcErrorHelper setValidationError:response message:@"Actor not found"];
                return;
            }
            targetDID = actorProfile[@"did"];
        }

        NSString *query = @"SELECT DISTINCT did, rkey FROM records WHERE collection = ? AND subject_did = ?";
        if (cursor.length > 0) {
            query = [query stringByAppendingString:@" AND (did || '/' || rkey) < ?"];
        }
        query = [query stringByAppendingString:@" ORDER BY (did || '/' || rkey) DESC LIMIT ?"];

        NSMutableArray *args = [NSMutableArray arrayWithObjects:@"app.bsky.graph.listitem", targetDID, nil];
        if (cursor.length > 0) [args addObject:cursor];
        [args addObject:@(limit + 1)];

        NSError *error = nil;
        NSArray *rows = [services.appViewDatabase executeParameterizedQuery:query params:args error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to load lists"];
            return;
        }

        NSMutableSet *processedListURIs = [NSMutableSet set];
        NSMutableArray *lists = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            if (lists.count >= (NSUInteger)limit) break;

            NSString *creatorDID = row[@"did"];
            NSString *rkey = row[@"rkey"];
            NSString *listURI = [NSString stringWithFormat:@"at://%@/app.bsky.graph.list/%@", creatorDID, rkey];

            if ([processedListURIs containsObject:listURI]) {
                continue;
            }
            [processedListURIs addObject:listURI];

            NSDictionary *listView = XrpcLoadListViewForURI(services.appViewDatabase, actorService, listURI);
            if (listView) {
                [lists addObject:listView];
            }
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"lists"] = lists;
        if (rows.count > (NSUInteger)limit && rows.count > 0) {
            NSDictionary *lastRow = rows[MIN(limit, (NSInteger)rows.count - 1)];
            NSString *lastDID = lastRow[@"did"];
            NSString *lastRKey = lastRow[@"rkey"];
            result[@"cursor"] = [NSString stringWithFormat:@"%@/%@", lastDID, lastRKey];
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.verification.createVerification
    [dispatcher registerAppBskyGraphVerificationCreateVerification:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        NSDictionary *body = request.jsonBody;
        NSString *subject = body[@"subject"];
        if (!subject) {
            [XrpcErrorHelper setValidationError:response message:@"subject is required"];
            return;
        }

        NSDictionary *record = @{
            @"$type": @"app.bsky.graph.verification",
            @"subject": subject,
            @"createdAt": [NSDateFormatter atproto_stringFromDate:[NSDate date]]
        };

        NSError *error = nil;
        // Use a TID as rkey for verification records
        NSString *rkey = [[TID tid] stringValue];
        if (![services.recordService putRecord:@"app.bsky.graph.verification"
                                rkey:rkey
                               value:record
                              forDid:actorDID
                               error:&error]) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.verification.deleteVerification
    [dispatcher registerAppBskyGraphVerificationDeleteVerification:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:services.jwtMinter
                                                      adminController:services.adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        NSDictionary *body = request.jsonBody;
        NSString *subject = body[@"subject"];
        if (!subject) {
            [XrpcErrorHelper setValidationError:response message:@"subject is required"];
            return;
        }

        // We need to find the record key for the verification of this subject
        NSError *error = nil;
        NSArray *records = [services.recordService listRecords:@"app.bsky.graph.verification"
                                               forDid:actorDID
                                                limit:100
                                               cursor:nil
                                                error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        NSString *foundRKey = nil;
        for (NSDictionary *recordEntry in records) {
            NSDictionary *value = recordEntry[@"value"];
            if ([value[@"subject"] isEqualToString:subject]) {
                foundRKey = recordEntry[@"uri"];
                // Extract rkey from URI: at://did/coll/rkey
                foundRKey = [foundRKey lastPathComponent];
                break;
            }
        }

        if (!foundRKey) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Verification not found"}];
            return;
        }

        if (![services.recordService deleteRecord:@"app.bsky.graph.verification"
                                   rkey:foundRKey
                                 forDid:actorDID
                                  error:&error]) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    GZ_LOG_INFO(@"Registered app.bsky.graph.* endpoints");
}

@end
