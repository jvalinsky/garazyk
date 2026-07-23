// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "Network/AppViewXRpcRoutePack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcRoutePack.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/XrpcServerPack.h"
#import "Network/XrpcAdminPack.h"
#import "Network/XrpcRepoPack.h"
#import "Network/Generated/GZXrpcNSID.h"

// Private category for route lookup (same pattern as PDSHttpPDSAdminRoutePackTests)
@interface HttpServer (RoutePackDecompositionTesting)
- (nullable RequestHandler)handlerForRoute:(NSString *)path
                                    method:(NSString *)method
                                parameters:(NSDictionary<NSString *, NSString *> *_Nullable *_Nullable)parameters;
@end

@interface XrpcRoutePackDecompositionCharacterizationTests : XCTestCase
@end

@implementation XrpcRoutePackDecompositionCharacterizationTests

#pragma mark - XrpcServerPack

- (void)testServerPackConformsToRoutePackProtocol {
    XCTAssertTrue([XrpcServerPack conformsToProtocol:@protocol(XrpcRoutePack)]);
    XCTAssertEqualObjects([XrpcServerPack routePackIdentifier], @"com.atproto.server");
}

- (void)testServerPackRegistersAllExpectedRoutes {
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
    id<XrpcRoutePackServices> services =
        [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                  jwtMinter:nil
                                            adminController:nil
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];

    [XrpcServerPack registerWithDispatcher:dispatcher services:services];

    // describeServer
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_describeServer]);
    // session
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_createAccount]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_createSession]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_getSession]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_refreshSession]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_deleteSession]);
    // invite codes
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_createInviteCode]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_createInviteCodes]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_getAccountInviteCodes]);
    // app passwords
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_createAppPassword]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_listAppPasswords]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_revokeAppPassword]);
    // email & account management
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_requestEmailConfirmation]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_requestEmailUpdate]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_confirmEmail]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_updateEmail]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_requestAccountDelete]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_requestPasswordReset]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_resetPassword]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_reserveSigningKey]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_getServiceAuth]);
    // account lifecycle
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_getAccount]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_deleteAccount]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_checkAccountStatus]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_activateAccount]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_server_deactivateAccount]);
    // health
    XCTAssertTrue([dispatcher hasRegisteredMethod:@"_health"]);
}

#pragma mark - XrpcAdminPack

- (void)testAdminPackConformsToRoutePackProtocol {
    XCTAssertTrue([XrpcAdminPack conformsToProtocol:@protocol(XrpcRoutePack)]);
    XCTAssertEqualObjects([XrpcAdminPack routePackIdentifier], @"com.atproto.admin");
}

- (void)testAdminPackRegistersAllExpectedRoutes {
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
    id<XrpcRoutePackServices> services =
        [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                  jwtMinter:nil
                                            adminController:nil
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];

    [XrpcAdminPack registerWithDispatcher:dispatcher services:services];

    // Account lookup, search & email
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_searchAccounts]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_sendEmail]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_updateAccountEmail]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_updateAccountHandle]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_updateAccountPassword]);
    // Server stats, audit & repair
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_getServerStats]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_queryAuditLog]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_repairRepo]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_runBlobAudit]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_getBlobAuditStatus]);
    // Account info, invites & subject status
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_getAccountUsage]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_getAccountInfo]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_getAccountInfos]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_getInviteCodes]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_disableAccountInvites]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_enableAccountInvites]);
    // Account lifecycle, records & takedown
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_updateSubjectStatus]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_getRecord]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_getSubjectStatus]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_getAccountTakedown]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_deleteAccount]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_disableInviteCodes]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_updateAccountSigningKey]);
    // Moderation (deprecated)
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_moderateAccount]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_moderateRecord]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_takeDownAccount]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_getModerationReports]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_admin_resolveReport]);
}

#pragma mark - XrpcRepoPack

- (void)testRepoPackConformsToRoutePackProtocol {
    XCTAssertTrue([XrpcRepoPack conformsToProtocol:@protocol(XrpcRoutePack)]);
    XCTAssertEqualObjects([XrpcRepoPack routePackIdentifier], @"com.atproto.repo");
}

- (void)testRepoPackRegistersAllExpectedRoutes {
    XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
    id<XrpcRoutePackServices> services =
        [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                  jwtMinter:nil
                                            adminController:nil
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];

    [XrpcRepoPack registerWithDispatcher:dispatcher services:services];

    // Records
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_listRecords]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_getRecord]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_createRecord]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_deleteRecord]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_putRecord]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_updateRecord]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_applyWrites]);
    // Blobs
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_uploadBlob]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_listMissingBlobs]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_getBlob]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_deleteBlob]);
    // Import & describe
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_importRepo]);
    XCTAssertTrue([dispatcher hasRegisteredMethod:kGZXrpcNSID_com_atproto_repo_describeRepo]);
}

#pragma mark - AppViewXRpcRoutePack

- (void)testAppViewPackRegistersAllExpectedRoutes {
    HttpServer *server = [HttpServer serverWithPort:0];
    // NOTE: feedService, actorService, and notificationService are not nullable in the
    // AppViewXRpcRoutePack init signature, but the init only stores ivars without
    // validating them. Passing nil here is intentional — it tests unconditional route
    // registration without requiring real service objects. Conditional routes (graph.*,
    // contact.*, and write-proxy) are not tested here; they require non-nil services.
    AppViewXRpcRoutePack *pack = [[AppViewXRpcRoutePack alloc] initWithFeedService:nil
                                                                      actorService:nil
                                                                      graphService:nil
                                                                notificationService:nil
                                                               ageAssuranceService:nil
                                                                       draftService:nil
                                                                    bookmarkService:nil
                                                                     contactService:nil
                                                                 searchIndexService:nil
                                                                        writeProxy:nil
                                                                         database:nil
                                                                        jwtMinter:nil];
    [pack registerRoutesWithServer:server];

    // app.bsky.actor (always registered)
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.actor.getProfile" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.actor.getProfiles" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.actor.searchActors" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.actor.searchActorsTypeahead" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.actor.getPreferences" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.actor.putPreferences" method:@"POST" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.actor.getSuggestions" method:@"GET" parameters:nil]);

    // app.bsky.feed (always registered)
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.feed.getTimeline" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.feed.getAuthorFeed" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.feed.getPostThread" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.feed.getFeed" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.feed.getActorLikes" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.feed.getPosts" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.feed.getFeedGenerators" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.feed.getLikes" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.feed.getRepostedBy" method:@"GET" parameters:nil]);

    // app.bsky.graph (getStarterPacks is unconditional; remaining graph.* routes require _graphService)
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.graph.getStarterPacks" method:@"GET" parameters:nil]);

    // app.bsky.notification (always registered)
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.notification.listNotifications" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.notification.getUnreadCount" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.notification.updateSeen" method:@"POST" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.notification.registerPush" method:@"POST" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.notification.unregisterPush" method:@"POST" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.notification.listActivitySubscriptions" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.notification.putActivitySubscription" method:@"POST" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.notification.getPreferences" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.notification.putPreferences" method:@"POST" parameters:nil]);

    // com.atproto.* (proxied, unconditional)
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/com.atproto.identity.resolveHandle" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/com.atproto.repo.getRecord" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/com.atproto.label.queryLabels" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/com.atproto.admin.getAccountInfos" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/com.atproto.admin.getSubjectStatus" method:@"GET" parameters:nil]);

    // app.bsky.ageassurance (always registered)
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.ageassurance.begin" method:@"POST" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.ageassurance.getConfig" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.ageassurance.getState" method:@"GET" parameters:nil]);

    // app.bsky.draft (always registered)
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.draft.getDrafts" method:@"GET" parameters:nil]);

    // app.bsky.bookmark (always registered)
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.bookmark.getBookmarks" method:@"GET" parameters:nil]);

    // app.bsky.unspecced search skeleton (always registered)
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.unspecced.searchActorsSkeleton" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.unspecced.searchPostsSkeleton" method:@"GET" parameters:nil]);
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.unspecced.searchStarterPacksSkeleton" method:@"GET" parameters:nil]);

    // app.bsky.labeler (always registered)
    XCTAssertNotNil([server handlerForRoute:@"/xrpc/app.bsky.labeler.getServices" method:@"GET" parameters:nil]);
}

@end
