#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

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

/*!
 @method sharedDispatcher
 
 @abstract Returns the shared dispatcher instance.
 
 @return The singleton XrpcDispatcher.
 */
+ (instancetype)sharedDispatcher;

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

/*! Registers handler for com.atproto.admin.moderateAccount. */
- (void)registerComAtprotoAdminModerateAccount:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.admin.moderateRecord. */
- (void)registerComAtprotoAdminModerateRecord:(XrpcMethodHandler)handler;

// MARK: - Label Methods

/*! Registers handler for com.atproto.label.queryLabels. */
- (void)registerComAtprotoLabelQueryLabels:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.label.createLabel. */
- (void)registerComAtprotoLabelCreateLabel:(XrpcMethodHandler)handler;

/*! Registers handler for com.atproto.label.getLabels. */
- (void)registerComAtprotoLabelGetLabels:(XrpcMethodHandler)handler;

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

/*! Registers handler for app.bsky.user.getUserStats. */
- (void)registerAppBskyUserGetUserStats:(XrpcMethodHandler)handler;

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

// MARK: - App Bsky Notification Methods

/*! Registers handler for app.bsky.notification.registerPush. */
- (void)registerAppBskyNotificationRegisterPush:(XrpcMethodHandler)handler;

@end

NS_ASSUME_NONNULL_END
