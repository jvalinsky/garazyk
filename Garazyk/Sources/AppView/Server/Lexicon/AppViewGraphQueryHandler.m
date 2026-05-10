/*!
 @file AppViewGraphQueryHandler.m

 @abstract Custom query handler for app.bsky.graph XRPC endpoints.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppViewGraphQueryHandler.h"

#import "AppView/Services/GraphService.h"
#import "AppView/Server/AppViewDatabase.h"

@interface AppViewGraphQueryHandler ()

@property (nonatomic, strong) GraphService *graphService;

@end

@implementation AppViewGraphQueryHandler

- (instancetype)initWithGraphService:(GraphService *)graphService {
    self = [super init];
    if (self) {
        _graphService = graphService;
    }
    return self;
}

#pragma mark - AppViewLexiconQueryHandler

- (BOOL)handleQueryWithParams:(NSDictionary<NSString *, NSString *> *)params
                        input:(nullable NSDictionary *)input
                     database:(AppViewDatabase *)database
                    callerDID:(nullable NSString *)callerDID
                       result:(NSDictionary *_Nullable *_Nullable)result
                        error:(NSError **)error {
    NSString *nsid = params[@"_nsid"] ?: @"";

    if ([nsid isEqualToString:@"app.bsky.graph.getStarterPack"]) {
        return [self handleGetStarterPack:params result:result error:error];
    }

    if ([nsid isEqualToString:@"app.bsky.graph.getStarterPacks"]) {
        return [self handleGetStarterPacks:params result:result error:error];
    }

    if ([nsid isEqualToString:@"app.bsky.graph.getActorStarterPacks"]) {
        return [self handleGetActorStarterPacks:params result:result error:error];
    }

    if (error) {
        *error = [NSError errorWithDomain:@"AppViewGraphQueryHandler"
                                      code:1
                                  userInfo:@{NSLocalizedDescriptionKey:
                                      [NSString stringWithFormat:@"Unhandled NSID: %@", nsid]}];
    }
    return NO;
}

- (nullable NSString *)nsid {
    return nil; // Registered for multiple NSIDs
}

- (BOOL)requiresAuth {
    return NO;
}

#pragma mark - app.bsky.graph.getStarterPack

- (BOOL)handleGetStarterPack:(NSDictionary<NSString *, NSString *> *)params
                       result:(NSDictionary *_Nullable *_Nullable)result
                        error:(NSError **)error {
    NSString *uri = params[@"uri"];
    if (!uri.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"AppViewGraphQueryHandler"
                                          code:2
                                      userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameter: uri"}];
        }
        return NO;
    }

    NSDictionary *view = [self.graphService getStarterPack:uri error:error];
    if (!view) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"AppViewGraphQueryHandler"
                                          code:404
                                      userInfo:@{NSLocalizedDescriptionKey:
                                          [NSString stringWithFormat:@"Starter pack not found: %@", uri]}];
        }
        return NO;
    }

    if (result) *result = view;
    return YES;
}

#pragma mark - app.bsky.graph.getStarterPacks

- (BOOL)handleGetStarterPacks:(NSDictionary<NSString *, NSString *> *)params
                        result:(NSDictionary *_Nullable *_Nullable)result
                         error:(NSError **)error {
    NSString *urisParam = params[@"uris"];
    if (!urisParam.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"AppViewGraphQueryHandler"
                                          code:2
                                      userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameter: uris"}];
        }
        return NO;
    }

    NSArray<NSString *> *uris = [urisParam componentsSeparatedByString:@","];
    NSArray<NSDictionary *> *views = [self.graphService getStarterPacks:uris error:error];
    if (!views) {
        return NO;
    }

    if (result) *result = @{@"starterPacks": views};
    return YES;
}

#pragma mark - app.bsky.graph.getActorStarterPacks

- (BOOL)handleGetActorStarterPacks:(NSDictionary<NSString *, NSString *> *)params
                            result:(NSDictionary *_Nullable *_Nullable)result
                             error:(NSError **)error {
    NSString *actor = params[@"actor"];
    if (!actor.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"AppViewGraphQueryHandler"
                                          code:2
                                      userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameter: actor"}];
        }
        return NO;
    }

    NSInteger limit = params[@"limit"] ? [params[@"limit"] integerValue] : 50;
    NSString *cursor = params[@"cursor"];

    NSDictionary *resultDict = [self.graphService getStarterPacksForActor:actor
                                                                    limit:limit
                                                                   cursor:cursor
                                                                    error:error];
    if (!resultDict) {
        return NO;
    }

    if (result) *result = resultDict;
    return YES;
}

@end
