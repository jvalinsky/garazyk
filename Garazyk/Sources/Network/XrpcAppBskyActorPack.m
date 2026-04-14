#import "Network/XrpcAppBskyActorPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/ActorService.h"
#import "Debug/PDSLogger.h"

@implementation XrpcAppBskyActorPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(PDSDatabase *)appViewDatabase
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
        if (!body || ![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }
        
        id preferences = body[@"preferences"];
        if (!preferences || (![preferences isKindOfClass:[NSDictionary class]] && ![preferences isKindOfClass:[NSArray class]])) {
            [XrpcErrorHelper setValidationError:response message:@"Missing preferences in body"];
            return;
        }
        
        NSError *error = nil;
        BOOL success = [actorService putPreferencesForActor:actorDID preferences:preferences error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to save preferences"];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"preferences": preferences}];
    }];
    
    // app.bsky.actor.getProfile - Get actor profile
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
    
    // app.bsky.actor.getSuggestions - Get suggested accounts (stub)
    [dispatcher registerMethod:@"app.bsky.actor.getSuggestions" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"actors": @[]}];
    }];
    
    PDS_LOG_INFO(@"Registered app.bsky.actor.* endpoints");
}

@end
