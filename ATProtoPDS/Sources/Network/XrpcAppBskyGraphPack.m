#import "Network/XrpcAppBskyGraphPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/GraphService.h"
#import "AppView/ActorService.h"
#import "Debug/PDSLogger.h"

@implementation XrpcAppBskyGraphPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(PDSDatabase *)appViewDatabase
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController {

    GraphService *graphService = [[GraphService alloc] initWithDatabase:appViewDatabase];
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];

    // app.bsky.graph.getMutes
    [dispatcher registerAppBskyGraphGetMutes:^(HttpRequest *request, HttpResponse *response) {
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
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [graphService getMutesForActor:actorDID limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"mutes": @[]}];
    }];

    // app.bsky.graph.getBlocks
    [dispatcher registerAppBskyGraphGetBlocks:^(HttpRequest *request, HttpResponse *response) {
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

    // app.bsky.graph.getFollowers
    [dispatcher registerMethod:@"app.bsky.graph.getFollowers" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [graphService getFollowersForActor:actor limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"followers": @[]}];
    }];

    // app.bsky.graph.getFollows
    [dispatcher registerMethod:@"app.bsky.graph.getFollows" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [graphService getFollowsForActor:actor limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"follows": @[]}];
    }];

    // app.bsky.graph.muteActor
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

    // app.bsky.graph.unmuteActor
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

    // app.bsky.graph.getRelationships
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
        NSError *error = nil;
        NSArray *relationships = [graphService getRelationships:actor withActors:others error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"relationships": relationships ?: @[]}];
    }];

    PDS_LOG_INFO(@"Registered app.bsky.graph.* endpoints");
}

@end
