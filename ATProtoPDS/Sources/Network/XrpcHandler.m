#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import "Network/XrpcProxyHandler.h"
#import "Auth/JWT.h"
#import "Debug/PDSLogger.h"
#import "App/PDSConfiguration.h"

@interface XrpcDispatcher ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, XrpcMethodHandler> *methodHandlers;

@end

@implementation XrpcDispatcher

+ (instancetype)sharedDispatcher {
    static XrpcDispatcher *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _methodHandlers = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)registerMethod:(NSString *)methodId handler:(XrpcMethodHandler)handler {
    self.methodHandlers[methodId] = [handler copy];
}

- (void)setCorsHeaders:(HttpResponse *)response forRequest:(HttpRequest *)request {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSArray<NSString *> *allowedOrigins = [config arrayForKey:@"cors.allowed_origins"];
    if (!allowedOrigins) {
        allowedOrigins = @[@"*"];
    }

    NSString *origin = [request headerForKey:@"Origin"];

    if (origin && [allowedOrigins containsObject:@"*"]) {
        [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
    } else if (origin && [allowedOrigins containsObject:origin]) {
        [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
    } else if (!origin && [allowedOrigins containsObject:@"*"]) {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    }

    NSString *allowedMethods = [config stringForKey:@"cors.allowed_methods"] ?: @"GET, POST, PUT, DELETE, OPTIONS, HEAD";
    NSString *allowedHeaders = [config stringForKey:@"cors.allowed_headers"] ?: @"DPoP, Authorization, Content-Type, *";
    NSInteger maxAge = [config integerForKey:@"cors.max_age"] ?: 86400;

    [response setHeader:allowedMethods forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:allowedHeaders forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:[NSString stringWithFormat:@"%ld", (long)maxAge] forKey:@"Access-Control-Max-Age"];
    [response setHeader:@"DPoP-Nonce, WWW-Authenticate" forKey:@"Access-Control-Expose-Headers"];
    [response setHeader:@"Origin" forKey:@"Vary"];
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    // Handle CORS preflight immediately — the /xrpc pathHandler prefix match
    // catches OPTIONS before the route trie's explicit OPTIONS route, so we
    // must handle it here to guarantee a 200 response for browsers.
    if (request.method == HttpMethodOPTIONS) {
        [self setCorsHeaders:response forRequest:request];
        response.statusCode = HttpStatusOK;
        return;
    }

    // Set CORS headers for all XRPC responses (not just OPTIONS)
    [self setCorsHeaders:response forRequest:request];

    // Check Rate Limit
    RateLimitResult *rateLimit = [[RateLimiter sharedLimiter] checkRateLimitForIP:request.remoteAddress];
    if (!rateLimit.allowed) {
        response.statusCode = HttpStatusTooManyRequests;
        [response setJsonBody:@{
            @"error": @"RateLimitExceeded",
            @"message": @"Too many requests"
        }];
        
        // Add rate limit headers for client backoff (per reference implementation)
        // Reference: reference/indigo/xrpc/xrpc.go (errorFromHTTPResponse function)
        [response setHeader:[NSString stringWithFormat:@"%ld", (long)rateLimit.limit] forKey:@"X-RateLimit-Limit"];
        [response setHeader:[NSString stringWithFormat:@"%ld", (long)rateLimit.remaining] forKey:@"X-RateLimit-Remaining"];
        [response setHeader:[NSString stringWithFormat:@"%.0f", rateLimit.resetSeconds] forKey:@"X-RateLimit-Reset"];
        [response setHeader:[NSString stringWithFormat:@"%.0f", rateLimit.retryAfter] forKey:@"Retry-After"];
        
        return;
    }

    NSString *path = request.path;
    NSString *methodId = request.pathParameters[@"method"];

    if (!methodId || methodId.length == 0) {
        methodId = nil;
    }

    if (!methodId) {
        if ([path hasPrefix:@"/xrpc/"]) {
            methodId = [path substringFromIndex:6];
        } else if ([path hasPrefix:@"/"]) {
            methodId = [path substringFromIndex:1];
        }
    }

    if (!methodId || methodId.length == 0) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{@"error": @"InvalidMethod", @"message": @"Missing XRPC method name"}];
        return;
    }

    XrpcMethodHandler handler = self.methodHandlers[methodId];

    PDS_LOG_INFO(@"XrpcHandler: methodId=%@, handler=%@", methodId, handler ? @"found" : @"nil");

    if (self.requestInterceptor) {
        BOOL handled = self.requestInterceptor(request, response, methodId, handler != nil);
        if (handled) {
            return;
        }
    }

    if (!handler && self.defaultHandler) {
        self.defaultHandler(request, response);
        return;
    }

    if (!handler) {
        // Fallback to proxying for app.bsky.* methods if an upstream AppView is configured
        if (self.proxyURL && [methodId hasPrefix:@"app.bsky."]) {
            PDS_LOG_INFO(@"Proxying XRPC method '%@' to %@", methodId, self.proxyURL);
            XrpcProxyHandler *proxy = [[XrpcProxyHandler alloc] initWithProxyURL:self.proxyURL
                                                                     upstreamDID:self.upstreamDID
                                                                          minter:self.jwtMinter];
            [proxy handleRequest:request response:response];
            return;
        }

        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
            @"error": @"MethodNotFound",
            @"message": [NSString stringWithFormat:@"XRPC method '%@' not found", methodId]
        }];
        return;
    }

    PDS_LOG_INFO(@"XrpcHandler: About to call handler for method=%@", methodId);
    @try {
        handler(request, response);
    } @catch (NSException *exception) {
        NSString *name = exception.name ?: @"(null)";
        NSString *reason = exception.reason ?: @"(null)";
        NSArray<NSString *> *stack = exception.callStackSymbols ?: @[];
        PDS_LOG_ERROR(@"[XRPC] Unhandled exception in %@: %@ (%@)\n%@",
                      methodId, name, reason, [stack componentsJoinedByString:@"\n"]);

        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": @"Unhandled exception"
        }];
    }
}

- (void)registerComAtprotoServerDescribeServer:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.describeServer" handler:handler];
}

- (void)registerComAtprotoServerCreateSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createSession" handler:handler];
}

- (void)registerComAtprotoServerGetSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.getSession" handler:handler];
}

- (void)registerComAtprotoServerCreateAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createAccount" handler:handler];
}

- (void)registerComAtprotoServerRefreshSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.refreshSession" handler:handler];
}

- (void)registerComAtprotoServerDeleteSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.deleteSession" handler:handler];
}

- (void)registerComAtprotoServerCreateInviteCode:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createInviteCode" handler:handler];
}

- (void)registerComAtprotoServerCreateInviteCodes:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createInviteCodes" handler:handler];
}

- (void)registerComAtprotoServerGetAccountInviteCodes:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.getAccountInviteCodes" handler:handler];
}

- (void)registerComAtprotoServerCreateAppPassword:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createAppPassword" handler:handler];
}

- (void)registerComAtprotoServerListAppPasswords:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.listAppPasswords" handler:handler];
}

- (void)registerComAtprotoServerRevokeAppPassword:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.revokeAppPassword" handler:handler];
}

- (void)registerComAtprotoServerGetServiceAuth:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.getServiceAuth" handler:handler];
}

- (void)registerComAtprotoServerGetAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.getAccount" handler:handler];
}

- (void)registerComAtprotoServerDeleteAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.deleteAccount" handler:handler];
}

- (void)registerComAtprotoServerCheckAccountStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.checkAccountStatus" handler:handler];
}

- (void)registerComAtprotoServerActivateAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.activateAccount" handler:handler];
}

- (void)registerComAtprotoServerDeactivateAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.deactivateAccount" handler:handler];
}

- (void)registerComAtprotoServerConfirmEmail:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.confirmEmail" handler:handler];
}

- (void)registerComAtprotoServerRequestAccountDelete:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.requestAccountDelete" handler:handler];
}

- (void)registerComAtprotoServerRequestPasswordReset:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.requestPasswordReset" handler:handler];
}

- (void)registerComAtprotoServerReserveSigningKey:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.reserveSigningKey" handler:handler];
}

- (void)registerComAtprotoServerResetPassword:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.resetPassword" handler:handler];
}

- (void)registerComAtprotoTempRevokeAccountCredentials:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.temp.revokeAccountCredentials" handler:handler];
}

- (void)registerComAtprotoLexiconResolveLexicon:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.lexicon.resolveLexicon" handler:handler];
}

- (void)registerComAtprotoServerUpdateEmail:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.updateEmail" handler:handler];
}

- (void)registerComAtprotoServerRequestEmailConfirmation:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.requestEmailConfirmation" handler:handler];
}

- (void)registerComAtprotoServerRequestEmailUpdate:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.requestEmailUpdate" handler:handler];
}

- (void)registerComAtprotoRepoCreateRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.createRecord" handler:handler];
}

- (void)registerComAtprotoRepoGetRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.getRecord" handler:handler];
}

- (void)registerComAtprotoRepoListRecords:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.listRecords" handler:handler];
}

- (void)registerComAtprotoRepoDeleteRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.deleteRecord" handler:handler];
}

- (void)registerComAtprotoRepoApplyWrites:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.applyWrites" handler:handler];
}

- (void)registerComAtprotoRepoDescribeRepo:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.describeRepo" handler:handler];
}

- (void)registerComAtprotoRepoPutRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.putRecord" handler:handler];
}

- (void)registerComAtprotoRepoUpdateRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.updateRecord" handler:handler];
}

- (void)registerComAtprotoRepoGetBlob:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.getBlob" handler:handler];
}

- (void)registerComAtprotoRepoUploadBlob:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.uploadBlob" handler:handler];
}

- (void)registerComAtprotoRepoImportRepo:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.importRepo" handler:handler];
}

- (void)registerComAtprotoRepoListMissingBlobs:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.listMissingBlobs" handler:handler];
}

- (void)registerComAtprotoRepoDeleteBlob:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.deleteBlob" handler:handler];
}

- (void)registerComAtprotoSyncGetRepo:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getRepo" handler:handler];
}

- (void)registerComAtprotoSyncGetCheckout:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getCheckout" handler:handler];
}

- (void)registerComAtprotoSyncGetHead:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getHead" handler:handler];
}

- (void)registerComAtprotoSyncGetBlob:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getBlob" handler:handler];
}

- (void)registerComAtprotoSyncListBlobs:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.listBlobs" handler:handler];
}

- (void)registerComAtprotoSyncGetLatestCommit:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getLatestCommit" handler:handler];
}

- (void)registerComAtprotoSyncGetBlocks:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getBlocks" handler:handler];
}

- (void)registerComAtprotoSyncGetRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getRecord" handler:handler];
}

- (void)registerComAtprotoSyncGetHostStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getHostStatus" handler:handler];
}

- (void)registerComAtprotoSyncListHosts:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.listHosts" handler:handler];
}

- (void)registerComAtprotoSyncListRepos:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.listRepos" handler:handler];
}

- (void)registerComAtprotoSyncGetRepoStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getRepoStatus" handler:handler];
}

- (void)registerComAtprotoSyncListReposByCollection:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.listReposByCollection" handler:handler];
}

- (void)registerComAtprotoSyncNotifyOfUpdate:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.notifyOfUpdate" handler:handler];
}

- (void)registerComAtprotoSyncRequestCrawl:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.requestCrawl" handler:handler];
}

- (void)registerComAtprotoSyncSubscribeRepos:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.subscribeRepos" handler:handler];
}

- (void)registerComAtprotoIdentityResolveDid:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.resolveDid" handler:handler];
}

- (void)registerComAtprotoIdentityResolveIdentity:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.resolveIdentity" handler:handler];
}

- (void)registerComAtprotoIdentityResolveHandle:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.resolveHandle" handler:handler];
}

- (void)registerComAtprotoIdentityGetRecommendedDidCredentials:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.getRecommendedDidCredentials" handler:handler];
}

- (void)registerComAtprotoIdentityRefreshIdentity:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.refreshIdentity" handler:handler];
}

- (void)registerComAtprotoIdentityRequestPlcOperationSignature:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.requestPlcOperationSignature" handler:handler];
}

- (void)registerComAtprotoIdentitySignPlcOperation:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.signPlcOperation" handler:handler];
}

- (void)registerComAtprotoIdentitySubmitPlcOperation:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.submitPlcOperation" handler:handler];
}

- (void)registerComAtprotoIdentityUpdateHandle:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.identity.updateHandle" handler:handler];
}

- (void)registerComAtprotoModerationCreateReport:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.moderation.createReport" handler:handler];
}

- (void)registerComAtprotoAdminUpdateSubjectStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateSubjectStatus" handler:handler];
}

- (void)registerComAtprotoAdminGetSubjectStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getSubjectStatus" handler:handler];
}

- (void)registerComAtprotoAdminGetAccountTakedown:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getAccountTakedown" handler:handler];
}

- (void)registerComAtprotoAdminGetAccountInfo:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getAccountInfo" handler:handler];
}

- (void)registerComAtprotoAdminGetAccountInfos:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getAccountInfos" handler:handler];
}

- (void)registerComAtprotoAdminGetInviteCodes:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getInviteCodes" handler:handler];
}

- (void)registerComAtprotoAdminDeleteAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.deleteAccount" handler:handler];
}

- (void)registerComAtprotoAdminDisableAccountInvites:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.disableAccountInvites" handler:handler];
}

- (void)registerComAtprotoAdminEnableAccountInvites:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.enableAccountInvites" handler:handler];
}

- (void)registerComAtprotoAdminDisableInviteCodes:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.disableInviteCodes" handler:handler];
}

- (void)registerComAtprotoAdminSearchAccounts:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.searchAccounts" handler:handler];
}

- (void)registerComAtprotoAdminSendEmail:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.sendEmail" handler:handler];
}

- (void)registerComAtprotoAdminUpdateAccountEmail:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateAccountEmail" handler:handler];
}

- (void)registerComAtprotoAdminUpdateAccountHandle:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateAccountHandle" handler:handler];
}

- (void)registerComAtprotoAdminUpdateAccountPassword:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateAccountPassword" handler:handler];
}

- (void)registerComAtprotoAdminUpdateAccountSigningKey:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateAccountSigningKey" handler:handler];
}

- (void)registerComAtprotoAdminModerateAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.moderateAccount" handler:handler];
}

- (void)registerComAtprotoAdminModerateRecord:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.moderateRecord" handler:handler];
}

- (void)registerComAtprotoLabelQueryLabels:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.label.queryLabels" handler:handler];
}

- (void)registerComAtprotoLabelCreateLabel:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.label.createLabel" handler:handler];
}

- (void)registerComAtprotoLabelGetLabels:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.label.getLabels" handler:handler];
}

- (void)registerComAtprotoLabelSubscribeLabels:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.label.subscribeLabels" handler:handler];
}

- (void)registerAppBskyActorGetProfile:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.getProfile" handler:handler];
}

- (void)registerAppBskyActorGetProfiles:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.getProfiles" handler:handler];
}

- (void)registerAppBskyActorGetPreferences:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.getPreferences" handler:handler];
}

- (void)registerAppBskyActorPutPreferences:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.putPreferences" handler:handler];
}

- (void)registerAppBskyActorSearchActors:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.searchActors" handler:handler];
}

- (void)registerAppBskyActorSearchActorsTypeahead:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.actor.searchActorsTypeahead" handler:handler];
}

- (void)registerAppBskyFeedGetTimeline:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getTimeline" handler:handler];
}

- (void)registerAppBskyFeedGetAuthorFeed:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getAuthorFeed" handler:handler];
}

- (void)registerAppBskyFeedGetPostThread:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getPostThread" handler:handler];
}

- (void)registerAppBskyFeedGetFeed:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getFeed" handler:handler];
}

- (void)registerAppBskyFeedGetActorLikes:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getActorLikes" handler:handler];
}

- (void)registerAppBskyFeedGetPosts:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getPosts" handler:handler];
}

- (void)registerAppBskyGraphGetMutes:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.graph.getMutes" handler:handler];
}

- (void)registerAppBskyGraphGetBlocks:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.graph.getBlocks" handler:handler];
}

- (void)registerAppBskyFeedGetFeedGenerators:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.feed.getFeedGenerators" handler:handler];
}

- (void)registerAppBskyNotificationRegisterPush:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.notification.registerPush" handler:handler];
}

- (void)registerAppBskyUserGetUserStats:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.user.getUserStats" handler:handler];
}

- (void)registerAppBskyBookmarkGetBookmarks:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.bookmark.getBookmarks" handler:handler];
}

- (void)registerAppBskyBookmarkCreateBookmark:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.bookmark.createBookmark" handler:handler];
}

- (void)registerAppBskyBookmarkDeleteBookmark:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.bookmark.deleteBookmark" handler:handler];
}

- (void)registerAppBskyGraphGetStarterPack:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.graph.getStarterPack" handler:handler];
}

- (void)registerAppBskyGraphGetStarterPacks:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.graph.getStarterPacks" handler:handler];
}

- (void)registerAppBskyGraphGetActorStarterPacks:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.graph.getActorStarterPacks" handler:handler];
}

- (void)registerComAtprotoAdminGetModerationReports:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getModerationReports" handler:handler];
}

- (void)registerComAtprotoAdminResolveReport:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.resolveReport" handler:handler];
}

@end
