#import "Network/XrpcAppBskyActorPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/ActorService.h"
#import "Debug/PDSLogger.h"

@implementation XrpcAppBskyActorPack

+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                     jwtMinter:(JWTMinter *)jwtMinter
                               adminController:(id<PDSAdminController>)adminController {
    
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
    
    // app.bsky.actor.getPreferences - Get actor preferences
    [dispatcher registerAppBskyActorGetPreferences:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) {
            return;
        }
        
        NSError *error = nil;
        NSDictionary *preferences = [actorService getPreferencesForActor:actorDID error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:preferences ?: @{@"preferences": @{}}];
    }];
    
    // app.bsky.actor.putPreferences - Update actor preferences
    [dispatcher registerAppBskyActorPutPreferences:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) {
            return;
        }
        
        NSDictionary *body = request.jsonBody;
        NSArray *preferences = body[@"preferences"];
        if (!preferences || ![preferences isKindOfClass:[NSArray class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid preferences JSON (expected array under 'preferences' key)"];
            return;
        }
        
        NSError *error = nil;
        BOOL success = [actorService putPreferencesForActor:actorDID preferences:preferences error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to store preferences"];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                       jwtMinter:(JWTMinter *)jwtMinter
                 adminController:(id<PDSAdminController>)adminController {
    
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
    
    // app.bsky.actor.getProfile - Get an actor profile
    [dispatcher registerAppBskyActorGetProfile:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *profile = [actorService getProfileForActor:actor error:&error];
        if (error) {
            [XrpcErrorHelper setNotFoundError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:profile];
    }];
    
    // app.bsky.actor.getProfiles - Get multiple actor profiles
    [dispatcher registerAppBskyActorGetProfiles:^(HttpRequest *request, HttpResponse *response) {
        id actorsParam = request.queryParams[@"actors"];
        NSArray<NSString *> *actors = nil;
        
        if ([actorsParam isKindOfClass:[NSArray class]]) {
            actors = actorsParam;
        } else if ([actorsParam isKindOfClass:[NSString class]]) {
            actors = @[actorsParam];
        } else {
            [XrpcErrorHelper setValidationError:response message:@"Missing actors parameter"];
            return;
        }
        
        if (actors.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actors parameter"];
            return;
        }
        
        NSError *error = nil;
        NSArray<NSDictionary *> *profiles = [actorService getProfilesForActors:actors error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"profiles": profiles ?: @[]}];
    }];
    
    // app.bsky.actor.searchActors - Search actors with pagination
    [dispatcher registerAppBskyActorSearchActors:^(HttpRequest *request, HttpResponse *response) {
        NSString *term = [request queryParamForKey:@"q"];
        if (!term || term.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing search term (q parameter)"];
            response.statusCode = HttpStatusBadRequest;
            return;
        }
        
        NSInteger limit = 25;
        NSString *limitParam = request.queryParams[@"limit"];
        if (limitParam && limitParam.length > 0) {
            NSScanner *scanner = [NSScanner scannerWithString:limitParam];
            NSInteger parsed = 0;
            if ([scanner scanInteger:&parsed] && scanner.isAtEnd) {
                if (parsed >= 1 && parsed <= 100) {
                    limit = parsed;
                }
            }
        }
        
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        NSError *error = nil;
        NSDictionary *result = [actorService searchActors:term limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
    
    // app.bsky.actor.searchActorsTypeahead - Typeahead search for actors
    [dispatcher registerAppBskyActorSearchActorsTypeahead:^(HttpRequest *request, HttpResponse *response) {
        NSString *term = [request queryParamForKey:@"q"];
        if (!term || term.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing search term (q parameter)"];
            response.statusCode = HttpStatusBadRequest;
            return;
        }
        
        NSInteger limit = 10;
        NSString *limitParam = request.queryParams[@"limit"];
        if (limitParam && limitParam.length > 0) {
            NSScanner *scanner = [NSScanner scannerWithString:limitParam];
            NSInteger parsed = 0;
            if ([scanner scanInteger:&parsed] && scanner.isAtEnd) {
                if (parsed >= 1 && parsed <= 100) {
                    limit = parsed;
                }
            }
        }
        
        NSError *error = nil;
        NSArray<NSDictionary *> *actors = [actorService searchActorsTypeahead:term limit:limit error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"actors": actors ?: @[]}];
    }];
    
    // app.bsky.actor.getSuggestions - Get suggested accounts
    // app.bsky.actor.getSuggestions - Get suggested accounts
    [dispatcher registerMethod:@"app.bsky.actor.getSuggestions" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) {
            return;
        }

        NSInteger limit = 30;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];

        ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
        NSError *error = nil;
        NSDictionary *result = [actorService getSuggestionsForActor:actorDID
                                                              limit:limit
                                                             cursor:cursor
                                                              error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to get suggestions"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"actors": @[], @"cursor": [NSNull null]}];
    }];
    
    PDS_LOG_INFO(@"Registered app.bsky.actor.* endpoints");
}

@end
