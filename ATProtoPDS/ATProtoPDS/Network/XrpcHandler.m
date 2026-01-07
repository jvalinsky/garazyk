#import "XrpcHandler.h"
#import "HttpRequest.h"
#import "HttpResponse.h"

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
    NSString *path = request.path;

    NSString *methodId = nil;
    if ([path hasPrefix:@"/xrpc/"]) {
        methodId = [path substringFromIndex:6];
    } else if ([path hasPrefix:@"/"]) {
        methodId = [path substringFromIndex:1];
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

- (void)registerComAtprotoServerCreateSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createSession" handler:handler];
}

- (void)registerComAtprotoServerCreateAccount:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createAccount" handler:handler];
}

- (void)registerComAtprotoServerRefreshSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.refreshSession" handler:handler];
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

- (void)registerComAtprotoModerationCreateReport:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.moderation.createReport" handler:handler];
}

- (void)registerComAtprotoAdminUpdateSubjectStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.updateSubjectStatus" handler:handler];
}

- (void)registerComAtprotoAdminGetSubjectStatus:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.admin.getSubjectStatus" handler:handler];
}

- (void)registerComAtprotoLabelQueryLabels:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.label.queryLabels" handler:handler];
}

@end
