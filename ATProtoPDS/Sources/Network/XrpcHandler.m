#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"

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

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
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

    if (!handler && self.defaultHandler) {
        self.defaultHandler(request, response);
        return;
    }

    if (!handler) {
        response.statusCode = HttpStatusNotImplemented;
        [response setJsonBody:@{
            @"error": @"MethodNotFound",
            @"message": [NSString stringWithFormat:@"XRPC method '%@' not found", methodId]
        }];
        return;
    }

    handler(request, response);
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

- (void)registerComAtprotoServerGetServiceAuth:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.getServiceAuth" handler:handler];
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

- (void)registerComAtprotoRepoUploadBlob:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.uploadBlob" handler:handler];
}

- (void)registerComAtprotoRepoDeleteBlob:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.repo.deleteBlob" handler:handler];
}

- (void)registerComAtprotoSyncGetRepo:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.sync.getRepo" handler:handler];
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

- (void)registerComAtprotoModerationCreateReport:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.moderation.createReport" handler:handler];
}

- (void)registerComAtprotoAdminUpdateSubjectStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateSubjectStatus" handler:handler];
}

- (void)registerComAtprotoAdminGetSubjectStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getSubjectStatus" handler:handler];
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

- (void)registerAppBskyNotificationRegisterPush:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.notification.registerPush" handler:handler];
}

- (void)registerAppBskyUserGetUserStats:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.user.getUserStats" handler:handler];
}

@end
