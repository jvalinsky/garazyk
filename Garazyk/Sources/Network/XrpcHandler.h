// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;
@class JWTMinter;
@protocol XrpcMiddleware;

/*!
 @header XrpcHandler.h
 
 @abstract XRPC dispatcher for ATProto RPC methods.
 
 @discussion This header defines the XrpcDispatcher class for handling
 ATProto XRPC method calls. XRPC is the remote procedure call protocol
 used by ATProto for API requests.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

/*!
 @typedef XrpcMethodHandler
 
 @abstract Block type for handling XRPC method calls.
 
 @param request The incoming HTTP request containing the XRPC call.
 @param response The response object to populate with results.
 */
typedef void (^XrpcMethodHandler)(HttpRequest *request, HttpResponse *response);

/*!
 @typedef XrpcRequestInterceptor

 @abstract Optional pre-dispatch interceptor for XRPC requests.

 @discussion Invoked after method extraction and handler lookup, but before
 normal dispatch/default handling. Return YES to indicate the interceptor
 handled the request and no further dispatch should occur.
 */
typedef BOOL (^XrpcRequestInterceptor)(HttpRequest *request,
                                       HttpResponse *response,
                                       NSString *methodId,
                                       BOOL hasLocalHandler);

/*!
 @class XrpcDispatcher
 
 @abstract Dispatches XRPC method calls to handlers.
 
 @discussion XrpcDispatcher routes incoming XRPC requests to registered
 handlers based on the method NSID. It provides convenience methods for
 registering all standard ATProto XRPC methods.
 
 @code
 XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];
 
 [dispatcher registerComAtprotoServerCreateSession:^(HttpRequest *req, HttpResponse *resp) {
     // Handle createSession call
 }];
 
 [dispatcher handleRequest:request response:response];
 @endcode
 */
@interface XrpcDispatcher : NSObject

/*! Default handler for unrecognized methods. */
@property (nonatomic, copy) void (^defaultHandler)(HttpRequest *, HttpResponse *);

/*! Optional pre-dispatch interceptor for proxying/fallback behavior. */
@property (nonatomic, copy, nullable) XrpcRequestInterceptor requestInterceptor;

/*! Upstream AppView URL for proxying unregistered app.bsky.* methods. */
@property (nonatomic, copy, nullable) NSURL *proxyURL;

/*! Upstream AppView DID for service-to-service auth. */
@property (nonatomic, copy, nullable) NSString *upstreamDID;

/*! Minter for service-to-service auth tokens. */
@property (nonatomic, strong, nullable) JWTMinter *jwtMinter;

/*! Upstream Ozone moderation service URL for proxying unregistered tools.ozone.* methods. */
@property (nonatomic, copy, nullable) NSURL *ozoneURL;

/*! Upstream Ozone moderation service DID for service-to-service auth. */
@property (nonatomic, copy, nullable) NSString *ozoneDID;

/*! Upstream Chat service URL for proxying chat.bsky.* methods. */
@property (nonatomic, copy, nullable) NSURL *chatURL;

/*! Upstream Chat service DID for service-to-service auth. */
@property (nonatomic, copy, nullable) NSString *chatDID;

/*!
 @method sharedDispatcher
  
 @abstract Returns the shared dispatcher instance.
  
 @return The singleton XrpcDispatcher.
 */
+ (instancetype)sharedDispatcher;

/*!
 @method resetSharedDispatcher
 
 @abstract Resets the shared dispatcher instance.
 */
+ (void)resetSharedDispatcher;


/*!
 @method registerMethod:handler:
 
 @abstract Registers a handler for an XRPC method.
 
 @param methodId The method NSID (e.g., com.atproto.server.createSession).
 @param handler The handler to invoke for this method.
 */
- (void)registerMethod:(NSString *)methodId handler:(XrpcMethodHandler)handler;

/*!
 @method handleRequest:response:
 
 @abstract Dispatches an XRPC request to the appropriate handler.
 
 @param request The incoming request.
 @param response The response object to populate.
 */
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

// MARK: - Server Methods

/*! Registers handler for com.atproto.server.describeServer. */
- (void)registerComAtprotoServerDescribeServer:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.createSession. */
- (void)registerComAtprotoServerCreateSession:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.getSession. */
- (void)registerComAtprotoServerGetSession:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.createAccount. */
- (void)registerComAtprotoServerCreateAccount:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.refreshSession. */
- (void)registerComAtprotoServerRefreshSession:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.deleteSession. */
- (void)registerComAtprotoServerDeleteSession:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.createInviteCode. */
- (void)registerComAtprotoServerCreateInviteCode:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.createInviteCodes. */
- (void)registerComAtprotoServerCreateInviteCodes:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.getAccountInviteCodes. */
- (void)registerComAtprotoServerGetAccountInviteCodes:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.createAppPassword. */
- (void)registerComAtprotoServerCreateAppPassword:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.listAppPasswords. */
- (void)registerComAtprotoServerListAppPasswords:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.revokeAppPassword. */
- (void)registerComAtprotoServerRevokeAppPassword:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.getServiceAuth. */
- (void)registerComAtprotoServerGetServiceAuth:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.getAccount. */
- (void)registerComAtprotoServerGetAccount:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.deleteAccount. */
- (void)registerComAtprotoServerDeleteAccount:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.checkAccountStatus. */
- (void)registerComAtprotoServerCheckAccountStatus:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.activateAccount. */
- (void)registerComAtprotoServerActivateAccount:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.deactivateAccount. */
- (void)registerComAtprotoServerDeactivateAccount:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.confirmEmail. */
- (void)registerComAtprotoServerConfirmEmail:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.requestAccountDelete. */
- (void)registerComAtprotoServerRequestAccountDelete:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.requestPasswordReset. */
- (void)registerComAtprotoServerRequestPasswordReset:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.reserveSigningKey. */
- (void)registerComAtprotoServerReserveSigningKey:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.resetPassword. */
- (void)registerComAtprotoServerResetPassword:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.temp.revokeAccountCredentials. */
- (void)registerComAtprotoTempRevokeAccountCredentials:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.lexicon.resolveLexicon. */
- (void)registerComAtprotoLexiconResolveLexicon:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.updateEmail. */
- (void)registerComAtprotoServerUpdateEmail:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.requestEmailConfirmation. */
- (void)registerComAtprotoServerRequestEmailConfirmation:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.server.requestEmailUpdate. */
- (void)registerComAtprotoServerRequestEmailUpdate:(XrpcMethodHandler)handler;

// MARK: - Repository Methods

/*! Registers handler for com.atproto.repo.createRecord. */
- (void)registerComAtprotoRepoCreateRecord:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.getRecord. */
- (void)registerComAtprotoRepoGetRecord:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.listRecords. */
- (void)registerComAtprotoRepoListRecords:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.deleteRecord. */
- (void)registerComAtprotoRepoDeleteRecord:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.deleteBlob. */
- (void)registerComAtprotoRepoDeleteBlob:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.applyWrites. */
- (void)registerComAtprotoRepoApplyWrites:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.describeRepo. */
- (void)registerComAtprotoRepoDescribeRepo:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.putRecord. */
- (void)registerComAtprotoRepoPutRecord:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.updateRecord. */
- (void)registerComAtprotoRepoUpdateRecord:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.getBlob. */
- (void)registerComAtprotoRepoGetBlob:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.uploadBlob. */
- (void)registerComAtprotoRepoUploadBlob:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.importRepo. */
- (void)registerComAtprotoRepoImportRepo:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.listMissingBlobs. */
- (void)registerComAtprotoRepoListMissingBlobs:(XrpcMethodHandler)handler;

// MARK: - Sync Methods

/*! Registers handler for com.atproto.sync.getRepo. */
- (void)registerComAtprotoSyncGetRepo:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.getCheckout. */
- (void)registerComAtprotoSyncGetCheckout:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.getHead. */
- (void)registerComAtprotoSyncGetHead:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.getBlob. */
- (void)registerComAtprotoSyncGetBlob:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.listBlobs. */
- (void)registerComAtprotoSyncListBlobs:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.getLatestCommit. */
- (void)registerComAtprotoSyncGetLatestCommit:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.getBlocks. */
- (void)registerComAtprotoSyncGetBlocks:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.getRecord. */
- (void)registerComAtprotoSyncGetRecord:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.getHostStatus. */
- (void)registerComAtprotoSyncGetHostStatus:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.listHosts. */
- (void)registerComAtprotoSyncListHosts:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.listRepos. */
- (void)registerComAtprotoSyncListRepos:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.getRepoStatus. */
- (void)registerComAtprotoSyncGetRepoStatus:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.listReposByCollection. */
- (void)registerComAtprotoSyncListReposByCollection:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.notifyOfUpdate. */
- (void)registerComAtprotoSyncNotifyOfUpdate:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.requestCrawl. */
- (void)registerComAtprotoSyncRequestCrawl:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.sync.subscribeRepos. */
- (void)registerComAtprotoSyncSubscribeRepos:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.repo.deleteBlob. */
- (void)registerComAtprotoRepoDeleteBlob:(XrpcMethodHandler)handler;

// MARK: - Identity Methods

/*! Registers handler for com.atproto.identity.resolveDid. */
- (void)registerComAtprotoIdentityResolveDid:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.identity.resolveIdentity. */
- (void)registerComAtprotoIdentityResolveIdentity:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.identity.resolveHandle. */
- (void)registerComAtprotoIdentityResolveHandle:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.identity.getRecommendedDidCredentials. */
- (void)registerComAtprotoIdentityGetRecommendedDidCredentials:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.identity.refreshIdentity. */
- (void)registerComAtprotoIdentityRefreshIdentity:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.identity.requestPlcOperationSignature. */
- (void)registerComAtprotoIdentityRequestPlcOperationSignature:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.identity.signPlcOperation. */
- (void)registerComAtprotoIdentitySignPlcOperation:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.identity.submitPlcOperation. */
- (void)registerComAtprotoIdentitySubmitPlcOperation:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.identity.updateHandle. */
- (void)registerComAtprotoIdentityUpdateHandle:(XrpcMethodHandler)handler;

// MARK: - Moderation Methods

/*! Registers handler for com.atproto.moderation.createReport. */
- (void)registerComAtprotoModerationCreateReport:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.updateSubjectStatus. */
- (void)registerComAtprotoAdminUpdateSubjectStatus:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.getSubjectStatus. */
- (void)registerComAtprotoAdminGetSubjectStatus:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.getAccountTakedown. */
- (void)registerComAtprotoAdminGetAccountTakedown:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.getAccountInfo. */
- (void)registerComAtprotoAdminGetAccountInfo:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.getAccountInfos. */
- (void)registerComAtprotoAdminGetAccountInfos:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.getInviteCodes. */
- (void)registerComAtprotoAdminGetInviteCodes:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.deleteAccount. */
- (void)registerComAtprotoAdminDeleteAccount:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.disableAccountInvites. */
- (void)registerComAtprotoAdminDisableAccountInvites:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.enableAccountInvites. */
- (void)registerComAtprotoAdminEnableAccountInvites:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.disableInviteCodes. */
- (void)registerComAtprotoAdminDisableInviteCodes:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.searchAccounts. */
- (void)registerComAtprotoAdminSearchAccounts:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.sendEmail. */
- (void)registerComAtprotoAdminSendEmail:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.updateAccountEmail. */
- (void)registerComAtprotoAdminUpdateAccountEmail:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.updateAccountHandle. */
- (void)registerComAtprotoAdminUpdateAccountHandle:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.updateAccountPassword. */
- (void)registerComAtprotoAdminUpdateAccountPassword:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.updateAccountSigningKey. */
- (void)registerComAtprotoAdminUpdateAccountSigningKey:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.moderateAccount. */
- (void)registerComAtprotoAdminModerateAccount:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.moderateRecord. */
- (void)registerComAtprotoAdminModerateRecord:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.getModerationReports. */
- (void)registerComAtprotoAdminGetModerationReports:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.resolveReport. */
- (void)registerComAtprotoAdminResolveReport:(XrpcMethodHandler)handler;

// MARK: - Middleware Support

/*!
 @method registerMethod:middlewares:handler:
 
 @abstract Registers a handler with middleware chain.
 
 @discussion The middleware chain is executed before the handler. If any middleware
 returns NO, the chain stops and the response is returned immediately.
 
 @param methodId The method NSID.
 @param middlewares Array of middleware to execute before handler (can be nil).
 @param handler The handler to invoke if all middleware pass.
 */
- (void)registerMethod:(NSString *)methodId
           middlewares:(nullable NSArray<id<XrpcMiddleware>> *)middlewares
               handler:(XrpcMethodHandler)handler;

// MARK: - Label Methods

/*! Registers handler for com.atproto.label.queryLabels. */
- (void)registerComAtprotoLabelQueryLabels:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.label.createLabel. */
- (void)registerComAtprotoLabelCreateLabel:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.label.getLabels. */
- (void)registerComAtprotoLabelGetLabels:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.label.subscribeLabels. */
- (void)registerComAtprotoLabelSubscribeLabels:(XrpcMethodHandler)handler;

// MARK: - App Bsky Actor Methods

/*! Registers handler for app.bsky.actor.getProfile. */
- (void)registerAppBskyActorGetProfile:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.actor.getProfiles. */
- (void)registerAppBskyActorGetProfiles:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.actor.getPreferences. */
- (void)registerAppBskyActorGetPreferences:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.actor.putPreferences. */
- (void)registerAppBskyActorPutPreferences:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.actor.searchActors. */
- (void)registerAppBskyActorSearchActors:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.actor.searchActorsTypeahead. */
- (void)registerAppBskyActorSearchActorsTypeahead:(XrpcMethodHandler)handler;

// MARK: - App Bsky Feed Methods

/*! Registers handler for app.bsky.feed.getTimeline. */
- (void)registerAppBskyFeedGetTimeline:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.feed.getAuthorFeed. */
- (void)registerAppBskyFeedGetAuthorFeed:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.feed.getPostThread. */
- (void)registerAppBskyFeedGetPostThread:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.feed.getFeed. */
- (void)registerAppBskyFeedGetFeed:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.feed.getActorLikes. */
- (void)registerAppBskyFeedGetActorLikes:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.feed.getPosts. */
- (void)registerAppBskyFeedGetPosts:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.graph.getMutes. */
- (void)registerAppBskyGraphGetMutes:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.graph.getBlocks. */
- (void)registerAppBskyGraphGetBlocks:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.feed.getFeedGenerators. */
- (void)registerAppBskyFeedGetFeedGenerators:(XrpcMethodHandler)handler;

// MARK: - App Bsky Notification Methods

/*! Registers handler for app.bsky.notification.registerPush. */
- (void)registerAppBskyNotificationRegisterPush:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.notification.unregisterPush. */
- (void)registerAppBskyNotificationUnregisterPush:(XrpcMethodHandler)handler;

// MARK: - App Bsky Bookmark Methods

/*! Registers handler for app.bsky.bookmark.getBookmarks. */
- (void)registerAppBskyBookmarkGetBookmarks:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.bookmark.createBookmark. */
- (void)registerAppBskyBookmarkCreateBookmark:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.bookmark.deleteBookmark. */
- (void)registerAppBskyBookmarkDeleteBookmark:(XrpcMethodHandler)handler;

// MARK: - App Bsky Graph Methods

/*! Registers handler for app.bsky.graph.getStarterPack. */
- (void)registerAppBskyGraphGetStarterPack:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.graph.getStarterPacks. */
- (void)registerAppBskyGraphGetStarterPacks:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.graph.getActorStarterPacks. */
- (void)registerAppBskyGraphGetActorStarterPacks:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.graph.verification.createVerification. */
- (void)registerAppBskyGraphVerificationCreateVerification:(XrpcMethodHandler)handler;

/*! Registers handler for app.bsky.graph.verification.deleteVerification. */
- (void)registerAppBskyGraphVerificationDeleteVerification:(XrpcMethodHandler)handler;

@end

NS_ASSUME_NONNULL_END
