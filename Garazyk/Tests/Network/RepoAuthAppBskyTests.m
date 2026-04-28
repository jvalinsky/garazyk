#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "AppView/Services/ActorService.h"

@interface RepoAuthAppBskyTests : RepoAuthXrpcTestBase
@end

@implementation RepoAuthAppBskyTests

static NSString *const kGraphMuteStatePreferenceType = @"com.atproto.pds.app.bsky.graph.muteState";

- (NSDictionary *)graphMutePreferenceForDid:(NSString *)did {
    NSError *dbError = nil;
    PDSDatabase *db = [[self serviceDatabases] serviceDatabaseWithError:&dbError];
    XCTAssertNotNil(db, @"Failed to open service database: %@", dbError.localizedDescription);
    if (!db) {
        return @{};
    }

    ActorService *actorService = [[ActorService alloc] initWithDatabase:db];
    NSError *prefsError = nil;
    NSDictionary *prefs = [actorService getPreferencesForActor:did error:&prefsError];
    [db close];
    XCTAssertNil(prefsError);

    NSArray *entries = [prefs[@"preferences"] isKindOfClass:[NSArray class]] ? prefs[@"preferences"] : @[];
    for (id entry in entries) {
        if ([entry isKindOfClass:[NSDictionary class]] &&
            [entry[@"$type"] isEqualToString:kGraphMuteStatePreferenceType]) {
            return (NSDictionary *)entry;
        }
    }
    return @{};
}

- (void)testNotificationPreferencesHandlersRequireAuthAndPersist {
    HttpResponse *unauthorized = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getPreferences"
                                                      headers:@{}];
    XCTAssertEqual(unauthorized.statusCode, 401);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *update = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferencesV2"
                                                    body:@{@"follow": @{@"include": @"all", @"list": @NO, @"push": @YES}}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(update.statusCode, 200);

    HttpResponse *fetch = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getPreferences"
                                               headers:@{@"authorization": authHeader}];
    XCTAssertEqual(fetch.statusCode, 200);
    NSDictionary *preferences = fetch.jsonBody[@"preferences"];
    NSDictionary *follow = preferences[@"follow"];
    XCTAssertTrue([follow isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(follow[@"list"], @NO);
    XCTAssertEqualObjects(follow[@"push"], @YES);
}

- (void)testGraphMuteActorListValidationAndIdempotence {
    NSString *listURI = [NSString stringWithFormat:@"at://%@/app.bsky.graph.list/test-list", self.did1];

    HttpResponse *unauthorized = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteActorList"
                                                          body:@{@"list": listURI}
                                                       headers:@{}];
    XCTAssertEqual(unauthorized.statusCode, 401);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *invalid = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteActorList"
                                                     body:@{@"list": @"not-an-at-uri"}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(invalid.statusCode, 400);

    HttpResponse *firstMute = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteActorList"
                                                       body:@{@"list": listURI}
                                                    headers:@{@"authorization": authHeader}];
    XCTAssertEqual(firstMute.statusCode, 200);

    HttpResponse *secondMute = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteActorList"
                                                        body:@{@"list": listURI}
                                                     headers:@{@"authorization": authHeader}];
    XCTAssertEqual(secondMute.statusCode, 200);

    NSDictionary *pref = [self graphMutePreferenceForDid:self.did1];
    NSArray *mutedLists = [pref[@"mutedLists"] isKindOfClass:[NSArray class]] ? pref[@"mutedLists"] : @[];
    XCTAssertEqual(mutedLists.count, 1);
    XCTAssertEqualObjects(mutedLists.firstObject, listURI);

    HttpResponse *firstUnmute = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.unmuteActorList"
                                                         body:@{@"list": listURI}
                                                      headers:@{@"authorization": authHeader}];
    XCTAssertEqual(firstUnmute.statusCode, 200);

    HttpResponse *secondUnmute = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.unmuteActorList"
                                                          body:@{@"list": listURI}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(secondUnmute.statusCode, 200);

    pref = [self graphMutePreferenceForDid:self.did1];
    mutedLists = [pref[@"mutedLists"] isKindOfClass:[NSArray class]] ? pref[@"mutedLists"] : @[];
    XCTAssertEqual(mutedLists.count, 0);
}

- (void)testGraphMuteThreadValidationAndIdempotence {
    NSString *threadRoot = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/thread-root", self.did1];
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    HttpResponse *invalid = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteThread"
                                                     body:@{@"root": @"bad-root"}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(invalid.statusCode, 400);

    HttpResponse *firstMute = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteThread"
                                                       body:@{@"root": threadRoot}
                                                    headers:@{@"authorization": authHeader}];
    XCTAssertEqual(firstMute.statusCode, 200);

    HttpResponse *secondMute = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.muteThread"
                                                        body:@{@"root": threadRoot}
                                                     headers:@{@"authorization": authHeader}];
    XCTAssertEqual(secondMute.statusCode, 200);

    NSDictionary *pref = [self graphMutePreferenceForDid:self.did1];
    NSArray *mutedThreads = [pref[@"mutedThreads"] isKindOfClass:[NSArray class]] ? pref[@"mutedThreads"] : @[];
    XCTAssertEqual(mutedThreads.count, 1);
    XCTAssertEqualObjects(mutedThreads.firstObject, threadRoot);

    HttpResponse *firstUnmute = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.unmuteThread"
                                                         body:@{@"root": threadRoot}
                                                      headers:@{@"authorization": authHeader}];
    XCTAssertEqual(firstUnmute.statusCode, 200);

    HttpResponse *secondUnmute = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.graph.unmuteThread"
                                                          body:@{@"root": threadRoot}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(secondUnmute.statusCode, 200);

    pref = [self graphMutePreferenceForDid:self.did1];
    mutedThreads = [pref[@"mutedThreads"] isKindOfClass:[NSArray class]] ? pref[@"mutedThreads"] : @[];
    XCTAssertEqual(mutedThreads.count, 0);
}

@end
