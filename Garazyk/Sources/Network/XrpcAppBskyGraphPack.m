#import "Network/XrpcAppBskyGraphPack.h"
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/GraphService.h"
#import "AppView/ActorService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Debug/PDSLogger.h"

@implementation XrpcAppBskyGraphPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                 appViewDatabase:(PDSDatabase *)appViewDatabase
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController {

    GraphService *graphService = [[GraphService alloc] initWithDatabase:appViewDatabase];
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];

    // app.bsky.graph.getMutes - Get muted actors
    [dispatcher registerAppBskyGraphGetMutes:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
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
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
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
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
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
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
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
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
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
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:args error:&error];
        NSMutableArray *lists = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            NSString *rkey = row[@"rkey"];
            NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.list/%@", actor, rkey];
            NSDictionary *listView = XrpcLoadListViewForURI(appViewDatabase, actorService, uri);
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
        NSDictionary *listView = XrpcLoadListViewForURI(appViewDatabase, actorService, list);
        if (!listView) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"List not found"}];
            return;
        }
        NSString *itemQuery = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ? ORDER BY rkey DESC LIMIT 100";
        NSArray *itemRows = [appViewDatabase executeParameterizedQuery:itemQuery params:@[did, @"app.bsky.graph.listitem"] error:nil];
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *itemRow in itemRows) {
            NSString *itemCidStr = itemRow[@"cid"];
            CID *itemCid = [CID cidFromString:itemCidStr];
            if (!itemCid) continue;
            PDSDatabaseBlock *itemBlock = [appViewDatabase getBlockWithCid:itemCid.bytes repoDid:did error:nil];
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
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
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
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
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
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
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
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
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

    // app.bsky.graph.searchStarterPacks - Search starter packs (stub)
    [dispatcher registerMethod:@"app.bsky.graph.searchStarterPacks" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"starterPacks": @[]}];
    }];

    // app.bsky.graph.getStarterPack - Get a starter pack
    [dispatcher registerAppBskyGraphGetStarterPack:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"uri": uri}];
    }];

    // app.bsky.graph.getActorStarterPacks - Get actor's starter packs
    [dispatcher registerAppBskyGraphGetActorStarterPacks:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"starterPacks": @[]}];
    }];

    // app.bsky.graph.getStarterPacks - Get multiple starter packs
    [dispatcher registerAppBskyGraphGetStarterPacks:^(HttpRequest *request, HttpResponse *response) {
        id urisParam = request.queryParams[@"uris"];
        NSArray *uris = [urisParam isKindOfClass:[NSArray class]] ? urisParam : (urisParam ? @[urisParam] : @[]);
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"starterPacks": @[]}];
    }];

    // app.bsky.graph.getStarterPacksWithMembership - List starter packs and viewer membership
    [dispatcher registerMethod:@"app.bsky.graph.getStarterPacksWithMembership" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *viewerDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:jwtMinter
                                                        adminController:adminController
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
        NSArray *rows = [appViewDatabase executeParameterizedQuery:
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

    PDS_LOG_INFO(@"Registered app.bsky.graph.* endpoints");
}

@end
